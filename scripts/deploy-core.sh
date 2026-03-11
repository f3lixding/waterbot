#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'EOF'
Usage:
  deploy-core.sh <build|deploy> [options]

Options:
  --flake-attr <attr>         Flake attribute to build/deploy (default: default).
  --pkg <name>                Package folder under pkgs/ (shorthand for --flake-attr).
  --target-host <host>        Target host for deployment (required for deploy).
  --target-user <user>        Target SSH user (default: pi).
  --target-dir <dir>          Target directory for package deploy (default: ~/.local/bin).

Examples:
  deploy-core.sh build --flake-attr default
  deploy-core.sh build --pkg main_compute
  deploy-core.sh deploy --pkg main_compute --target-host raspberrypi.local
EOF
}

if [[ $# -lt 1 ]]; then
  print_usage
  exit 2
fi

command="$1"
shift

flake_attr="default"
pkg_name=""
target_host=""
target_user="pi"
target_dir="~/.local/bin/waterbot"
target_dir_bak="~/.local/bin/waterbot_bak"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flake-attr)
      flake_attr="$2"
      shift 2
      ;;
    --pkg)
      pkg_name="$2"
      shift 2
      ;;
    --target-host)
      target_host="$2"
      shift 2
      ;;
    --target-user)
      target_user="$2"
      shift 2
      ;;
    --target-dir)
      target_dir="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage
      exit 2
      ;;
  esac
done

if [[ "$command" != "build" && "$command" != "deploy" ]]; then
  echo "Unknown command: $command" >&2
  print_usage
  exit 2
fi

if [[ -n "$pkg_name" ]]; then
  flake_attr="$pkg_name"
fi

if [[ "$command" == "deploy" && -z "$target_host" ]]; then
  echo "--target-host is required for deploy" >&2
  exit 2
fi

nix build ".#${flake_attr}"

if [[ "$command" == "deploy" ]]; then
  if [[ ! -d "./result/bin" ]]; then
    echo "Expected ./result/bin to exist after build" >&2
    exit 1
  fi

  shopt -s nullglob
  bin_files=(./result/bin/*)
  shopt -u nullglob

  if [[ ${#bin_files[@]} -eq 0 ]]; then
    echo "No files found in ./result/bin to deploy" >&2
    exit 1
  fi

  # back up first and then move
  ssh "${target_user}@${target_host}" "mkdir -p ${target_dir_bak}"
  ssh "${target_user}@${target_host}" "mkdir -p ${target_dir}"
  ssh "${target_user}@${target_host}" \
    "bash -lc 'shopt -s nullglob; files=(${target_dir}/*); if (( \${#files[@]} )); then cp -r ${target_dir}/* ${target_dir_bak}/; fi'"
  scp "${bin_files[@]}" "${target_user}@${target_host}:${target_dir}/"

  # TODO: kill existing process (if any) and then restart the process 
fi
