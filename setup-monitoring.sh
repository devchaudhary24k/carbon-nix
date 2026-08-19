#!/usr/bin/env bash

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

install -d -m 0700 -o root -g root /etc/carbon-monitor
umask 0077
printf '%s\n' "$heartbeat_url" > /etc/carbon-monitor/heartbeat-url
chown root:root /etc/carbon-monitor/heartbeat-url
chmod 0600 /etc/carbon-monitor/heartbeat-url
unset heartbeat_url
unset heartbeat_token

systemctl start carbon-health.service
echo
echo "Health check result:"
cat /var/lib/carbon-monitor/last-report
echo
echo "The checker is a one-shot service, so inactive between runs is normal."
systemctl status carbon-health.timer --no-pager
