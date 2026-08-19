#!/usr/bin/env bash

set -Eeuo pipefail

old_home=/home/devtalan
new_home=/home/dev24k
t3_database="$new_home/.t3/userdata/state.sqlite"
utility_file="$new_home/tools/backfill-codex-to-t3.mjs"
mode=${1:-}

usage() {
  cat <<'EOF'
Usage:
  migrate-restored-home.sh --dry-run
  migrate-restored-home.sh --apply

Migrates operational paths in the restored Carbon backup from
/home/devtalan to /home/dev24k. Historical Codex/chat content and generated
project output are intentionally left unchanged.
EOF
}

case "$mode" in
  --dry-run | --apply) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

for command in find git grep readlink sed sqlite3; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  }
done

[[ $(id -un) == dev24k ]] || {
  echo "Run this script as dev24k, without sudo." >&2
  exit 1
}
[[ -d "$new_home/code" && -d "$new_home/.t3" && -d "$new_home/.codex" ]] || {
  echo "The restored data is incomplete under $new_home." >&2
  exit 1
}
[[ -f "$t3_database" ]] || {
  echo "Missing T3 database: $t3_database" >&2
  exit 1
}
[[ ! -e "$old_home" && ! -L "$old_home" ]] || {
  echo "$old_home already exists; remove or investigate it before migrating." >&2
  exit 1
}

git_metadata_files=()
while IFS= read -r -d '' file; do
  if grep --quiet --fixed-strings "$old_home" "$file"; then
    git_metadata_files+=("$file")
  fi
done < <(
  find "$new_home/code" "$new_home/.t3/worktrees" \
    -type f \( -name .git -o -path '*/.git/worktrees/*/gitdir' \) -print0
)

absolute_links=()
while IFS= read -r -d '' link; do
  target=$(readlink "$link")
  if [[ "$target" == "$old_home" || "$target" == "$old_home/"* ]]; then
    absolute_links+=("$link")
  fi
done < <(
  find "$new_home/code" "$new_home/.t3" "$new_home/.codex" "$new_home/tools" \
    -type l -print0
)

utility_needs_update=0
if [[ -f "$utility_file" ]] && grep --quiet --fixed-strings "$old_home" "$utility_file"; then
  utility_needs_update=1
fi

database_path_rows() {
  sqlite3 -readonly "$t3_database" <<SQL
SELECT 'projects', COUNT(*)
FROM projection_projects
WHERE instr(workspace_root, '$old_home') > 0;
SELECT 'thread projections', COUNT(*)
FROM projection_threads
WHERE instr(worktree_path, '$old_home') > 0;
SELECT 'provider runtime cwd', COUNT(*)
FROM provider_session_runtime
WHERE instr(json_extract(runtime_payload_json, '\$.cwd'), '$old_home') > 0;
SELECT 'project events', COUNT(*)
FROM orchestration_events
WHERE event_type = 'project.created'
  AND instr(json_extract(payload_json, '\$.workspaceRoot'), '$old_home') > 0;
SELECT 'thread events', COUNT(*)
FROM orchestration_events
WHERE event_type IN ('thread.created', 'thread.meta-updated')
  AND instr(json_extract(payload_json, '\$.worktreePath'), '$old_home') > 0;
SQL
}

echo "Git metadata files to migrate: ${#git_metadata_files[@]}"
echo "Absolute symlinks to migrate: ${#absolute_links[@]}"
echo "Utility scripts to migrate: $utility_needs_update"
echo "T3 operational database rows:"
database_path_rows | sed 's/|/: /'

if [[ "$mode" == --dry-run ]]; then
  echo "Dry run complete; nothing was changed."
  exit 0
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
database_backup="/var/tmp/carbon-t3-state-before-home-migration-$timestamp.sqlite"
sqlite3 "$t3_database" ".backup '$database_backup'"
echo "T3 database backup: $database_backup"

for file in "${git_metadata_files[@]}"; do
  sed --in-place "s#$old_home#$new_home#g" "$file"
done

for link in "${absolute_links[@]}"; do
  target=$(readlink "$link")
  migrated_target=${target//$old_home/$new_home}
  ln --symbolic --force --no-dereference "$migrated_target" "$link"
done

if (( utility_needs_update == 1 )); then
  sed --in-place "s#$old_home#$new_home#g" "$utility_file"
fi

sqlite3 "$t3_database" <<SQL
.bail on
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

UPDATE projection_projects
SET workspace_root = replace(workspace_root, '$old_home', '$new_home')
WHERE instr(workspace_root, '$old_home') > 0;

UPDATE projection_threads
SET worktree_path = replace(worktree_path, '$old_home', '$new_home')
WHERE instr(worktree_path, '$old_home') > 0;

UPDATE provider_session_runtime
SET runtime_payload_json = json_set(
  runtime_payload_json,
  '\$.cwd',
  replace(json_extract(runtime_payload_json, '\$.cwd'), '$old_home', '$new_home')
)
WHERE instr(json_extract(runtime_payload_json, '\$.cwd'), '$old_home') > 0;

UPDATE orchestration_events
SET payload_json = json_set(
  payload_json,
  '\$.workspaceRoot',
  replace(json_extract(payload_json, '\$.workspaceRoot'), '$old_home', '$new_home')
)
WHERE event_type = 'project.created'
  AND instr(json_extract(payload_json, '\$.workspaceRoot'), '$old_home') > 0;

UPDATE orchestration_events
SET payload_json = json_set(
  payload_json,
  '\$.worktreePath',
  replace(json_extract(payload_json, '\$.worktreePath'), '$old_home', '$new_home')
)
WHERE event_type IN ('thread.created', 'thread.meta-updated')
  AND instr(json_extract(payload_json, '\$.worktreePath'), '$old_home') > 0;

COMMIT;
SQL

for file in "${git_metadata_files[@]}"; do
  if grep --quiet --fixed-strings "$old_home" "$file"; then
    echo "Old path remains in Git metadata: $file" >&2
    exit 1
  fi
done

for link in "${absolute_links[@]}"; do
  target=$(readlink "$link")
  [[ "$target" != "$old_home" && "$target" != "$old_home/"* ]] || {
    echo "Old path remains in symlink: $link" >&2
    exit 1
  }
done

broken_worktrees=0
while IFS= read -r -d '' marker; do
  repository=${marker%/.git}
  if ! git -C "$repository" rev-parse --git-common-dir >/dev/null 2>&1; then
    echo "Broken Git worktree: $repository" >&2
    broken_worktrees=$((broken_worktrees + 1))
  fi
done < <(find "$new_home/code" "$new_home/.t3/worktrees" -type f -name .git -print0)
(( broken_worktrees == 0 )) || exit 1

quick_check=$(sqlite3 -readonly "$t3_database" 'PRAGMA quick_check;')
[[ "$quick_check" == ok ]] || {
  echo "T3 database quick_check failed: $quick_check" >&2
  exit 1
}

remaining_database_rows=$(database_path_rows | awk -F '|' '{ total += $2 } END { print total + 0 }')
[[ "$remaining_database_rows" == 0 ]] || {
  echo "Operational old-home paths remain in the T3 database." >&2
  exit 1
}

echo "Migration completed successfully."
echo "Verified linked Git worktrees: no failures"
echo "T3 database quick_check: ok"
echo "Historical chat/session text and generated project output were not rewritten."
