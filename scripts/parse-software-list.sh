#!/usr/bin/env bash
# Parse Software.list and emit a JSON matrix consumed by the build job.
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: parse-software-list.sh [software-list]" >&2
  exit 1
fi

list_file="${1:-Software.list}"

if [[ ! -f "$list_file" ]]; then
  echo "Error: software list not found: $list_file" >&2
  exit 1
fi

declare -A seen=()
entries=()

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line="${raw_line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue

  if [[ ! "$line" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?/?$ ]]; then
    echo "Error: invalid entry in $list_file: $raw_line" >&2
    echo "Expected an HTTPS GitHub URL such as https://github.com/owner/repo" >&2
    exit 1
  fi

  line="${line%/}"
  line="${line%.git}"

  if [[ -n "${seen[$line]:-}" ]]; then
    echo "Warning: duplicate entry ignored: $line" >&2
    continue
  fi
  seen["$line"]=1
  entries+=("$line")
done < "$list_file"

if (( ${#entries[@]} == 0 )); then
  echo "Error: no software entries found in $list_file" >&2
  exit 1
fi

json="["
for i in "${!entries[@]}"; do
  (( i > 0 )) && json+=","
  json+="{\"url\":\"${entries[$i]}\"}"
done
json+="]"

printf '%s\n' "$json"
echo "Parsed ${#entries[@]} software entry/entries from $list_file" >&2
