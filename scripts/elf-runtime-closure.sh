#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  elf-runtime-closure.sh [--search-dir DIR]... <elf-file>...

Examples:
  elf-runtime-closure.sh ./result/bin/main_compute
  elf-runtime-closure.sh --search-dir ./result/lib ./result/bin/main_compute

The script walks DT_NEEDED entries recursively, using each ELF object's
RUNPATH/RPATH plus any explicit --search-dir values to resolve dependencies.
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi

if ! command -v readelf >/dev/null 2>&1; then
  echo "error: readelf is required" >&2
  exit 1
fi

declare -a roots=()
declare -a extra_search_dirs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --search-dir)
      extra_search_dirs+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        roots+=("$1")
        shift
      done
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      roots+=("$1")
      shift
      ;;
  esac
done

if [[ ${#roots[@]} -eq 0 ]]; then
  echo "error: at least one ELF file is required" >&2
  exit 2
fi

declare -A seen=()
declare -A resolving=()

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

real_path() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path"
  else
    readlink -f "$path"
  fi
}

elf_needed() {
  local path="$1"
  readelf -d "$path" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'
}

elf_runpath() {
  local path="$1"
  readelf -d "$path" 2>/dev/null | sed -n \
    -e 's/.*Library runpath: \[\(.*\)\]/\1/p' \
    -e 's/.*Library rpath: \[\(.*\)\]/\1/p' | head -n1
}

resolve_needed() {
  local owner="$1"
  local needed="$2"
  local owner_dir
  owner_dir="$(dirname "$owner")"
  local runpath
  runpath="$(elf_runpath "$owner")"

  declare -a search_dirs=()

  if [[ -n "$runpath" ]]; then
    IFS=':' read -r -a runpath_dirs <<<"$runpath"
    for dir in "${runpath_dirs[@]}"; do
      dir="${dir//\$ORIGIN/$owner_dir}"
      search_dirs+=("$dir")
    done
  fi

  for dir in "${extra_search_dirs[@]}"; do
    search_dirs+=("$dir")
  done

  search_dirs+=("/lib" "/usr/lib" "/lib64" "/usr/lib64")

  local candidate
  for dir in "${search_dirs[@]}"; do
    [[ -n "$dir" ]] || continue
    candidate="$dir/$needed"
    if [[ -e "$candidate" ]]; then
      real_path "$candidate"
      return 0
    fi
  done

  return 1
}

walk() {
  local path="$1"
  local indent="${2:-}"
  local canon
  canon="$(real_path "$path")"

  if [[ -n "${seen[$canon]:-}" ]]; then
    printf '%s%s (seen)\n' "$indent" "$canon"
    return 0
  fi

  seen["$canon"]=1
  printf '%s%s\n' "$indent" "$canon"

  local needed
  while IFS= read -r needed; do
    [[ -n "$needed" ]] || continue
    local resolved=""
    if resolved="$(resolve_needed "$canon" "$needed")"; then
      printf '%s  -> %s => %s\n' "$indent" "$needed" "$resolved"
      walk "$resolved" "    $indent"
    else
      printf '%s  -> %s => NOT FOUND\n' "$indent" "$needed"
    fi
  done < <(elf_needed "$canon")
}

for root in "${roots[@]}"; do
  if [[ ! -e "$root" ]]; then
    echo "error: not found: $root" >&2
    exit 1
  fi
  walk "$root"
done
