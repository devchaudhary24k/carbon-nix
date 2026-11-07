#!/usr/bin/env bash
#
# Pin T3 Code to a release from GitHub by rewriting sources.json.
#
#   ./packages/t3code/update.sh              newest nightly (what the app's
#                                            nightly channel would install)
#   ./packages/t3code/update.sh --stable     newest stable release
#   ./packages/t3code/update.sh v0.1.7       one specific tag
#
# Then rebuild. Both the server (carbon) and the desktop app (nukebyte) read
# the same file, so they always run the same version.

set -euo pipefail

repo=pingdotgg/t3code
api=https://api.github.com/repos/$repo

case "${1:-}" in
  "" | --nightly)
    tag=$(curl -fsSL "$api/releases?per_page=30" |
      jq -r '[.[] | select(.prerelease and (.tag_name | test("nightly")))][0].tag_name')
    ;;
  --stable)
    tag=$(curl -fsSL "$api/releases/latest" | jq -r .tag_name)
    ;;
  v*)
    tag=$1
    ;;
  *)
    sed -n '3,12p' "$0" >&2
    exit 2
    ;;
esac

if [[ -z "$tag" || "$tag" == null ]]; then
  echo "Could not find a matching release on github.com/$repo." >&2
  exit 1
fi

version=${tag#v}
base=https://github.com/$repo/releases/download/$tag
server_url=$base/t3-$version-linux-x64.tar.gz
desktop_url=$base/T3-Code-$version-x86_64.AppImage

prefetch() {
  echo "Fetching $1" >&2
  nix store prefetch-file --json "$1" | jq -r .hash
}

server_hash=$(prefetch "$server_url")
desktop_hash=$(prefetch "$desktop_url")

jq -n \
  --arg version "$version" \
  --arg server_url "$server_url" \
  --arg server_hash "$server_hash" \
  --arg desktop_url "$desktop_url" \
  --arg desktop_hash "$desktop_hash" \
  '{
    version: $version,
    server: { url: $server_url, hash: $server_hash },
    desktop: { url: $desktop_url, hash: $desktop_hash }
  }' >"$(dirname "$0")/sources.json"

echo "T3 Code pinned to $version. Rebuild to install it."
