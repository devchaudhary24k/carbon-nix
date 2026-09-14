# Minecraft Console Client as a set of systemd services, one per account.
#
# This replaces a tmux session that was acting as the process supervisor.
# systemd already does everything the old runner hand-rolled: restart on exit,
# backoff, start-rate limiting, status, and logging. tmux is no longer involved,
# so the bots survive a reboot and a closed SSH session.
#
# Each bot still runs on a real pty, because MCC's console reads keys directly
# and ignores a plain pipe. dtach supplies that pty and makes it detachable, so
# "mcc attach" gives a fully interactive console and "mcc dash" lays all of them
# out side by side, while systemd keeps owning the process.
#
# Console output therefore goes to the pty rather than journald, so MCC's own
# file logging is turned on and "mcc logs" reads that.
#
# Each account also gets MCC's embedded MCP server on its own port, for
# scripted control that does not need a terminal.
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

  accountDir = name: "${cfg.stateDir}/accounts/${name}";
  configOf = name: "${accountDir name}/MinecraftClient.ini";
  socketOf = name: "${socketDir}/${name}.sock";
  logOf = name: "${accountDir name}/console-log.txt";
  socketDir = "/run/mcc";

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

        # dtach -N runs in the foreground rather than daemonising, so systemd
        # still supervises the real process, and the pty survives detaching.
        ExecStart = lib.concatStringsSep " " [
          "${lib.getExe pkgs.dtach}"
          "-N"
          (socketOf name)
          "-r"
          "winch"
          (lib.getExe cfg.package)
          (configOf name)
          "--Logging.LogToFile=true"
          "--Logging.LogFile=${logOf name}"
          "--ChatBot.McpServer.Enabled=${lib.boolToString cfg.mcp.enable}"
          "--ChatBot.McpServer.Transport.BindHost=${cfg.mcp.bindHost}"
          "--ChatBot.McpServer.Transport.Port=${toString (portOf name)}"
        ];

        # MCC exits cleanly on SIGTERM, so the default kill signal is enough to
        # let it flush SessionCache.db.
        KillSignal = "SIGTERM";
        TimeoutStopSec = 30;

        Restart = "always";
        RestartSec = 15;

        # The self-contained .NET bundle unpacks native libraries on startup.
        # Give it one predictable place rather than whatever HOME happens to be.
        CacheDirectory = "mcc";
        Environment = [ "DOTNET_BUNDLE_EXTRACT_BASE_DIR=/var/cache/mcc" ];

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        # MCC writes SessionCache.db and ProfileKeyCache.ini beside its config.
        ReadWritePaths = [
          cfg.stateDir
          socketDir
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
      dtach
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
        logs    <account> [-f|N]     Recent console output, or follow it
        attach  <account>            Interactive console for one bot
        dash                         All bots side by side, one pane each
        say     <account> <text>     Send chat or a slash command
        chat    <account> [lines]    Recent chat that bot has seen
        who     <account>            Players online
        info    <account>            Session and connection status
        leave   <account>            Disconnect from the server, keep running
        tools   <account>            MCP tool names that bot exposes
        mcp     <account> <method> [params-json]
                                     Raw JSON-RPC to that bot's MCP server

      Bots connect at boot on their own, staggered so the server does not reject
      them. They keep running when you detach or close SSH.

      In attach, Ctrl-\\ detaches. In dash, Ctrl-B then D detaches, and Ctrl-B
      then an arrow key moves between bots. Neither stops the bot.

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
          [[ $# -ge 1 ]] || { echo "usage: mcc attach <account>" >&2; exit 2; }
          known "$1" || { echo "Unknown account: $1" >&2; exit 1; }
          socket=${lib.escapeShellArg socketDir}/"$1".sock
          if [[ ! -S "$socket" ]]; then
            echo "$1 is not running, so there is no console to attach to." >&2
            exit 1
          fi
          echo "Attaching to $1. Detach with Ctrl-\\ (this leaves the bot running)."
          exec dtach -a "$socket" -r winch
          ;;

        dash)
          # One pane per account, each a live console. Ctrl-B then arrows to
          # move between them, Ctrl-B then D to leave the whole thing running.
          session=mcc
          if tmux has-session -t "$session" 2>/dev/null; then
            exec tmux attach-session -t "$session"
          fi
          first=1
          while read -r account; do
            socket=${lib.escapeShellArg socketDir}/"$account".sock
            if [[ -S "$socket" ]]; then
              pane_command="dtach -a $socket -r winch"
            else
              pane_command="echo '$account is not running. Start it with: mcc start $account'; exec sleep infinity"
            fi
            if ((first)); then
              tmux new-session -d -s "$session" -n bots "$pane_command"
              first=0
            else
              tmux split-window -t "$session:bots" "$pane_command"
              tmux select-layout -t "$session:bots" tiled >/dev/null
            fi
            tmux select-pane -t "$session:bots.{last}" -T "$account"
          done < <(accounts)
          tmux select-layout -t "$session:bots" tiled >/dev/null
          tmux set-window-option -t "$session:bots" pane-border-status top >/dev/null
          tmux set-window-option -t "$session:bots" pane-border-format ' #{pane_title} ' >/dev/null
          exec tmux attach-session -t "$session"
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

    # dtach sockets. ProtectSystem=strict would otherwise leave /run read-only.
    systemd.tmpfiles.rules = [
      "d ${socketDir} 0700 ${cfg.user} ${cfg.group} -"
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
