#!/usr/bin/env bash
#
# Store the Better Stack heartbeat URL that modules/health-monitor.nix reads.
#
# The URL is a secret, so it is not in this repo. It is written to
# /etc/health-monitor/heartbeat-url, root-only, and the health service stays
# skipped until that file exists.

set -euo pipefail

if (( EUID != 0 )); then
  exec sudo "$0" "$@"
fi

read -r -s -p "Paste the Better Stack heartbeat URL: " heartbeat_url
printf '\n'
heartbeat_url="${heartbeat_url%/}"

case "$heartbeat_url" in
  https://uptime.betterstack.com/api/v1/heartbeat/*)
    heartbeat_token="${heartbeat_url#https://uptime.betterstack.com/api/v1/heartbeat/}"
    ;;
  *)
    echo "That does not look like a Better Stack heartbeat URL." >&2
    exit 1
    ;;
esac
case "$heartbeat_token" in
  ""|*/*|*[[:space:]]*)
    echo "That Better Stack heartbeat URL has an invalid token." >&2
    exit 1
    ;;
esac

install -d -m 0700 -o root -g root /etc/health-monitor
umask 0077
printf '%s\n' "$heartbeat_url" > /etc/health-monitor/heartbeat-url
chown root:root /etc/health-monitor/heartbeat-url
chmod 0600 /etc/health-monitor/heartbeat-url
unset heartbeat_url
unset heartbeat_token

systemctl start health-monitor.service
echo
echo "Health check result:"
cat /var/lib/health-monitor/last-report
echo
echo "The checker is a one-shot service, so inactive between runs is normal."
systemctl status health-monitor.timer --no-pager
