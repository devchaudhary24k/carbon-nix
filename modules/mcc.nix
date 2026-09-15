# Minecraft Console Client as a set of systemd services, one per account.
#
# This replaces a tmux session that was acting as the process supervisor.
# systemd already does everything the old runner hand-rolled: restart on exit,
# backoff, start-rate limiting, status, and logging. tmux is no longer involved,
# so the bots survive a reboot and a closed SSH session.
#
# Each bot runs inside its own GNU screen session, which systemd supervises.
#
# The terminal layer is not optional and not interchangeable. MCC emits
# terminal queries as it runs. screen is a terminal emulator, so it answers
# them continuously whether or not anyone is watching. dtach is not: it only
# shuttles bytes to an attached client, so while detached the queries go
# unanswered, and on attach they are all answered at once and land in MCC's
# input buffer as garbage. Measured over an identical attach, dtach produced
# 379 junk bytes and a corrupted input line, screen produced 3 and a clean
# prompt. That corruption is what disconnected a live bot and made it run
# nonsense as commands.
#
# So: screen for the console, systemd for the lifecycle, and MCP alongside for
# scripted control that does not need a terminal at all.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.minecraft-mcc;
  names = lib.attrNames cfg.accounts;

  # Ports are handed out in account-name order so they stay stable as long as
  # the set of accounts does not change. Pin mcpPort to opt out.
  defaultPorts = lib.listToAttrs (
    lib.imap0 (index: name: lib.nameValuePair name (cfg.mcp.basePort + index)) names
  );
  delayOf = name: cfg.startDelay * (lib.lists.findFirstIndex (n: n == name) 0 names);

  portOf =
    name:
    let
      pinned = cfg.accounts.${name}.mcpPort;
    in
    if pinned == null then defaultPorts.${name} else pinned;

  screenDir = "/run/mcc";
  sessionOf = name: "mcc-${name}";

  screenrc = pkgs.writeText "mcc-screenrc" ''
    startup_message off

    # Attaching should show what the bot has been saying, not a blank pane.
    defscrollback 10000

    # Without these, screen hands the program TERM=screen, which is 8 colours,
    # and MCC's output collapses to a single red. Measured by sending a 24-bit
    # escape through screen and reading it back on the far side: TERM=screen
    # dropped it, screen-256color alone still dropped it, and only truecolor on
    # let it through.
    term screen-256color
    truecolor on
  '';

  accountDir = name: "${cfg.stateDir}/accounts/${name}";
  configOf = name: "${accountDir name}/MinecraftClient.ini";

  mkService =
    name: account:
    lib.nameValuePair "mcc-${name}" {
      description = "Minecraft Console Client (${name})";
      wantedBy = lib.optional account.autoStart "mcc.target";
      partOf = [ "mcc.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
      ];

      # Five failures inside five minutes means something is wrong with the
      # account or the server. Stop rather than reconnecting forever.
      unitConfig = {
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = accountDir name;

        # A clearer failure than MCC generating a default config and silently
        # trying to log in as nobody.
        ExecStartPre = [
          "${pkgs.coreutils}/bin/test -f ${configOf name}"
        ]
        ++ lib.optional (delayOf name > 0) "${pkgs.coreutils}/bin/sleep ${toString (delayOf name)}";

        # ExecStartPre counts against the start timeout, so the stagger has to
        # fit inside it.
        TimeoutStartSec = delayOf name + 120;

        # -D -m runs screen in the foreground without forking, so systemd
        # supervises the real thing rather than a daemon that ran away.
        ExecStart = lib.concatStringsSep " " [
          "${lib.getExe' pkgs.screen "screen"}"
          "-c"
          screenrc
          "-D"
          "-m"
          "-S"
          (sessionOf name)
          (lib.getExe cfg.package)
          (configOf name)
          "--Logging.LogToFile=true"
          # Relative, resolved against WorkingDirectory. An absolute path here
          # silently produced no log file at all.
          "--Logging.LogFile=console-log.txt"
          "--ChatBot.McpServer.Enabled=${lib.boolToString cfg.mcp.enable}"
          "--ChatBot.McpServer.Transport.BindHost=${cfg.mcp.bindHost}"
          "--ChatBot.McpServer.Transport.Port=${toString (portOf name)}"
        ];

        # MCC exits cleanly on SIGTERM, so the default kill signal is enough to
        # let it flush SessionCache.db.
        KillSignal = "SIGTERM";

        # screen returns 1 when its child is terminated, so an ordinary
        # "mcc stop" left the unit in the failed state and the health monitor
        # reported it. A bot that really is broken still shows up: Restart
        # handles the transient case, and a persistent one trips
        # StartLimitBurst, which marks the unit failed regardless of this.
        SuccessExitStatus = "1";
        TimeoutStopSec = 30;

        Restart = "always";
        RestartSec = 15;

        # The self-contained .NET bundle unpacks native libraries on startup.
        # Give it one predictable place rather than whatever HOME happens to be.
        CacheDirectory = "mcc";
        Environment = [
          "DOTNET_BUNDLE_EXTRACT_BASE_DIR=/var/cache/mcc"
          "SCREENDIR=${screenDir}"
          "TERM=xterm-256color"
        ];

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        # MCC writes SessionCache.db and ProfileKeyCache.ini beside its config.
        ReadWritePaths = [
          cfg.stateDir
          screenDir
        ];
      };
    };

  portTable = lib.concatStringsSep "\n" (map (n: "${n} ${toString (portOf n)}") names);

  # One command for the whole thing, replacing 984 lines of tmux orchestration.
  # Everything it does is systemctl, journalctl or an HTTP call.
  mccCli = pkgs.writeShellApplication {
    name = "mcc";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      screen
      gawk
      gnugrep
      jq
      systemd
      tmux
      util-linux
    ];
    text = ''
      accounts() { printf '%s\n' ${lib.escapeShellArg portTable} | awk '{ print $1 }'; }

      port_of() {
        printf '%s\n' ${lib.escapeShellArg portTable} \
          | awk -v want="$1" '$1 == want { print $2; found = 1 } END { exit !found }'
      }

      known() { accounts | grep -qxF "$1"; }

      # "all" expands to every account; anything else must be a real one.
      resolve() {
        if [[ "$1" == all ]]; then
          accounts
        elif known "$1"; then
          printf '%s\n' "$1"
        else
          echo "Unknown account: $1" >&2
          echo "Known: $(accounts | tr '\n' ' ')" >&2
          return 1
        fi
      }

      # MCC speaks the streamable HTTP transport, which refuses any call that is
      # not preceded by initialize and does not carry the session id returned in
      # a header. Responses come back as server-sent events.
      mcp_rpc() {
        local account="$1" method="$2" params="''${3:-{\}}" port url headers session
        port=$(port_of "$account")
        url="http://${cfg.mcp.bindHost}:$port/mcp"
        headers=$(mktemp)
        trap 'rm -f "$headers"' RETURN

        if ! curl --silent --show-error --fail --max-time 10 --dump-header "$headers" \
               --header 'Content-Type: application/json' \
               --header 'Accept: application/json, text/event-stream' \
               --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcc","version":"1"}}}' \
               "$url" >/dev/null; then
          {
            echo "No MCP server answering on $url."
            echo "MCC only runs it while the bot is in game, and it does not come"
            echo "back after an AutoRelog. Try: mcc restart $account"
          } >&2
          return 1
        fi

        session=$(grep -i '^mcp-session-id:' "$headers" | tr -d '\r' | awk '{ print $2 }')

        curl --silent --max-time 10 \
          --header 'Content-Type: application/json' \
          --header 'Accept: application/json, text/event-stream' \
          --header "Mcp-Session-Id: $session" \
          --data '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$url" >/dev/null

        curl --silent --show-error --fail-with-body --max-time 20 \
          --header 'Content-Type: application/json' \
          --header 'Accept: application/json, text/event-stream' \
          --header "Mcp-Session-Id: $session" \
          --data "$(jq --null-input --arg m "$method" --argjson p "$params" \
                      '{jsonrpc: "2.0", id: 2, method: $m, params: $p}')" \
          "$url" | sed -n 's/^data: //p'
      }

      # tools/call, unwrapped to the text the tool returned.
      mcp_tool() {
        local account="$1" tool="$2" args="''${3:-{\}}"
        mcp_rpc "$account" tools/call \
          "$(jq --null-input --arg n "$tool" --argjson a "$args" \
               '{name: $n, arguments: $a}')" \
          | jq --raw-output '
              if .error then "error: " + (.error.message // (.error | tostring))
              elif .result.content then (.result.content[]? | .text // tostring)
              else ((.result // .) | tostring) end'
      }

      status_table() {
        printf '%-20s %-10s %-12s %-7s %s\n' ACCOUNT STATE UPTIME MCP LISTENING
        local account state since uptime port listening
        while read -r account; do
          state=$(systemctl is-active "mcc-$account.service" 2>/dev/null || true)
          since=$(systemctl show "mcc-$account.service" \
                    --property=ActiveEnterTimestamp --value 2>/dev/null || true)
          if [[ "$state" == active && -n "$since" ]]; then
            uptime=$(( ( $(date +%s) - $(date -d "$since" +%s) ) / 60 ))
            uptime="''${uptime}m"
          else
            uptime="-"
          fi
          port=$(port_of "$account")
          if timeout 2 bash -c "</dev/tcp/${cfg.mcp.bindHost}/$port" 2>/dev/null; then
            listening=yes
          else
            listening=no
          fi
          printf '%-20s %-10s %-12s %-7s %s\n' \
            "$account" "$state" "$uptime" "$port" "$listening"
        done < <(accounts)
      }

      usage() {
        cat <<'EOF'
      Usage: mcc <command> [arguments]

        status                       State, uptime and MCP port for every account
        list                         Account names, one per line
        start   <account|all>        Connect
        stop    <account|all>        Disconnect
        restart <account|all>        Reconnect
        logs    <account> [-f|N]     Recent chat log, or follow it
        attach  <account>            The real MCC console for one bot
        dash                         Every bot tiled, one console each
        say     <account> <text>     Send chat or a server command
        cmd     <account> <command>  Run an MCC internal command
        chat    <account> [lines]    Recent chat that bot has seen
        who     <account>            Players online
        info    <account>            Session and connection status
        leave   <account>            Disconnect from the server, keep running
        tools   <account>            MCP tool names that bot exposes
        mcp     <account> <method> [params-json]
                                     Raw JSON-RPC to that bot's MCP server

      Bots connect at boot on their own, staggered so the server does not reject
      them. They keep running when you detach or close SSH.

      In dash, click a pane to focus it and scroll with the wheel. Ctrl-B then D
      leaves the whole window running, and Ctrl-B then an arrow key also moves
      between bots. Inside one bot's console, Ctrl-A then D
      detaches from it. None of these stop a bot.

      say, chat, who, info, leave and cmd go through MCP, which MCC only runs
      while a bot is in game and does not restart after an AutoRelog. attach and
      dash do not need it and always work.

      MCP only answers while a bot is in game, and it does not come back by
      itself after MCC's AutoRelog reconnects. If LISTENING says no for a bot
      that is otherwise fine, "mcc restart <account>" brings it back.
      EOF
      }

      command="''${1:-status}"
      (($# > 0)) && shift

      case "$command" in
        status) status_table ;;
        list) accounts ;;
        ports) printf '%s\n' ${lib.escapeShellArg portTable} ;;

        start | stop | restart)
          [[ $# -ge 1 ]] || { echo "usage: mcc $command <account|all>" >&2; exit 2; }
          mapfile -t targets < <(resolve "$1")
          for account in "''${targets[@]}"; do
            before=$(systemctl is-active "mcc-$account.service" 2>/dev/null || true)
            if [[ "$command" == start && "$before" == active ]]; then
              printf '%-20s already running\n' "$account"
              continue
            fi
            systemctl "$command" "mcc-$account.service"
            printf '%-20s %s\n' "$account" \
              "$(systemctl is-active "mcc-$account.service" 2>/dev/null || echo failed)"
          done
          ;;

        logs)
          # MCC's console goes to its screen terminal, not the journal, so read
          # the file it writes itself.
          [[ $# -ge 1 ]] || { echo "usage: mcc logs <account> [-f]" >&2; exit 2; }
          account="$1"; shift
          known "$account" || { echo "Unknown account: $account" >&2; exit 1; }
          log=${lib.escapeShellArg cfg.stateDir}/accounts/"$account"/console-log.txt
          if [[ ! -f "$log" ]]; then
            echo "No log yet at $log. Has $account started?" >&2
            exit 1
          fi
          if [[ "''${1:-}" == -f ]]; then
            tail --follow=name --lines=50 "$log"
          else
            tail --lines="''${1:-200}" "$log"
          fi
          ;;

        attach)
          # The real MCC console for one bot: chat scrolls in, you type into it.
          [[ $# -ge 1 ]] || { echo "usage: mcc attach <account>" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          if ! systemctl is-active --quiet "mcc-$1.service"; then
            echo "$1 is not running. Start it with: mcc start $1" >&2
            exit 1
          fi
          echo "Attaching to $1. Ctrl-A then D detaches and leaves it running." >&2
          exec env SCREENDIR=${lib.escapeShellArg screenDir} \
            screen -r ${lib.escapeShellArg "mcc-"}"$1"
          ;;

        dash)
          # One real console per bot, tiled. This is the old four-pane window,
          # except systemd owns the bots so they survive a reboot.
          session=mcc
          if tmux has-session -t "$session" 2>/dev/null; then
            exec tmux attach-session -t "$session"
          fi
          # This script's own path, so panes work regardless of PATH.
          self=''${BASH_SOURCE[0]}
          # Read the list into an array first. Looping over a process
          # substitution leaves tmux sharing the loop's stdin, and it eats an
          # account, which silently costs you a pane.
          mapfile -t dash_accounts < <(accounts)
          first=1
          for account in "''${dash_accounts[@]}"; do
            pane_command="$self attach $account"
            if ((first)); then
              # Size the detached session up front. tmux refuses to split when
              # there is no room, which silently drops a bot.
              pane=$(tmux new-session -d -x 200 -y 50 -P -F '#{pane_id}' \
                       -s "$session" -n bots "$pane_command" </dev/null)
              first=0
            else
              if ! pane=$(tmux split-window -t "$session:bots" -P -F '#{pane_id}' \
                            "$pane_command" </dev/null 2>&1); then
                echo "Could not add a pane for $account: $pane" >&2
                continue
              fi
              tmux select-layout -t "$session:bots" tiled >/dev/null
            fi
            tmux select-pane -t "$pane" -T "$account" </dev/null
          done
          tmux select-layout -t "$session:bots" tiled >/dev/null
          # A console that dies should leave a visible pane saying so, not
          # silently shrink the dashboard.
          # Click a pane to focus it and use the wheel to scroll, instead of
          # Ctrl-B and an arrow key for everything.
          tmux set-option -t "$session" mouse on >/dev/null
          tmux set-window-option -t "$session:bots" remain-on-exit on >/dev/null
          tmux set-window-option -t "$session:bots" pane-border-status top >/dev/null
          tmux set-window-option -t "$session:bots" pane-border-format ' #{pane_title} ' >/dev/null
          exec tmux attach-session -t "$session"
          ;;

        cmd)
          # MCC's own internal commands, as opposed to server commands.
          [[ $# -ge 2 ]] || { echo "usage: mcc cmd <account> <internal command>" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          account="$1"; shift
          mcp_tool "$account" mcc_run_internal_command \
            "$(jq --null-input --arg c "$*" '{command: $c}')"
          ;;

        say)
          [[ $# -ge 2 ]] || { echo "usage: mcc say <account> <message or /command>" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          account="$1"; shift
          mcp_tool "$account" mcc_send_chat "$(jq --null-input --arg t "$*" '{text: $t}')"
          ;;

        chat)
          [[ $# -ge 1 ]] || { echo "usage: mcc chat <account> [lines]" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          mcp_tool "$1" mcc_chat_history \
            "$(jq --null-input --argjson n "''${2:-40}" '{maxCount: $n}')"
          ;;

        who)
          [[ $# -ge 1 ]] || { echo "usage: mcc who <account>" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          mcp_tool "$1" mcc_players_list
          ;;

        info)
          [[ $# -ge 1 ]] || { echo "usage: mcc info <account>" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          mcp_tool "$1" mcc_session_status
          ;;

        leave)
          # Leaves the server without stopping the service, so MCC's own
          # reconnect logic can bring it back.
          [[ $# -ge 1 ]] || { echo "usage: mcc leave <account>" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          mcp_tool "$1" mcc_disconnect
          ;;

        tools)
          [[ $# -ge 1 ]] || { echo "usage: mcc tools <account>" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          mcp_rpc "$1" tools/list | jq --raw-output '.result.tools[]? | .name'
          ;;

        mcp)
          [[ $# -ge 2 ]] || { echo "usage: mcc mcp <account> <method> [params-json]" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          mcp_rpc "$1" "$2" "''${3:-{\}}"
          ;;

        -h | --help | help) usage ;;
        *) usage >&2; exit 2 ;;
      esac
    '';
  };
in

{
  options.services.minecraft-mcc = {
    enable = lib.mkEnableOption "Minecraft Console Client bots";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.minecraft-console-client;
      defaultText = lib.literalExpression "pkgs.minecraft-console-client";
      description = "Minecraft Console Client build to run.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      description = "User the bots run as. It must own the account directories.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group the bots run as.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/opt/mcc";
      description = ''
        Directory holding accounts/<name>/MinecraftClient.ini. These hold login
        details and cached session tokens, so they stay out of this repo and are
        not managed by Nix.
      '';
    };

    mcp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run MCC's embedded MCP server for each account. It starts once the bot
          joins the game and stops when it disconnects, so it can control a
          running bot but cannot start one.
        '';
      };

      bindHost = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Address the MCP listener binds to. Left on loopback deliberately;
          reach it from another machine over an SSH tunnel rather than exposing
          an unauthenticated control channel.
        '';
      };

      basePort = lib.mkOption {
        type = lib.types.port;
        default = 33331;
        description = "First MCP port. Accounts get consecutive ports from here.";
      };
    };

    startDelay = lib.mkOption {
      type = lib.types.int;
      default = 20;
      description = ''
        Seconds to wait between one account connecting and the next. Four bots
        logging in at once made the server reject some of them with "Failed to
        login to this server", after which MCC's AutoRelog reconnected but its
        MCP server did not come back. Staggering avoids the rejection.

        Set to 0 to start every account at once.
      '';
    };

    accounts = lib.mkOption {
      description = "Accounts to run, keyed by the directory name under accounts/.";
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            autoStart = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Connect this account automatically at boot.";
            };

            mcpPort = lib.mkOption {
              type = lib.types.nullOr lib.types.port;
              default = null;
              description = "Pin this account's MCP port instead of assigning one.";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.programs.nix-ld.enable;
        message = ''
          services.minecraft-mcc needs programs.nix-ld.enable. MCC is a
          self-contained .NET bundle that cannot be patchelf'd without
          corrupting it, so it still asks for /lib64/ld-linux-x86-64.so.2.
        '';
      }
    ];

    # The interpreter the unpatched bundle asks for.
    programs.nix-ld.libraries = cfg.package.runtimeLibraries;

    # screen's sockets. ProtectSystem=strict leaves /run read-only otherwise.
    systemd.tmpfiles.rules = [
      "d ${screenDir} 0700 ${cfg.user} ${cfg.group} -"
    ];

    systemd.targets.mcc = {
      description = "All Minecraft Console Client bots";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services = lib.mapAttrs' mkService cfg.accounts;

    environment.systemPackages = [
      cfg.package
      mccCli
    ];

    # Starting and stopping your own bots should not need a password.
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id === "org.freedesktop.systemd1.manage-units" &&
            subject.user === "${cfg.user}") {
          var unit = action.lookup("unit");
          if (unit && unit.indexOf("mcc-") === 0) {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };
}
