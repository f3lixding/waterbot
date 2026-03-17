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

verify_no_gpiod_runtime_dep() {
  local bin_path="$1"
  local bundle_dir="$2"

  if ! command -v readelf >/dev/null 2>&1; then
    echo "warning: readelf not found; skipping runtime dependency verification for ${bin_path}" >&2
    return 0
  fi

  if readelf -d "${bin_path}" 2>/dev/null | grep -Fq 'libgpiod.so'; then
    if [[ -d "${bundle_dir}" ]] && find "${bundle_dir}" -maxdepth 1 -name 'libgpiod.so*' | grep -q .; then
      return 0
    fi

    echo "Refusing to continue: ${bin_path} still has a runtime dependency on libgpiod.so but no bundled lib/ was found" >&2
    readelf -d "${bin_path}" >&2
    exit 1
  fi
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

if [[ -d "./result/bin" ]]; then
  shopt -s nullglob
  built_bins=(./result/bin/*)
  shopt -u nullglob

  for bin_path in "${built_bins[@]}"; do
    if [[ -f "${bin_path}" && -x "${bin_path}" ]]; then
      verify_no_gpiod_runtime_dep "${bin_path}" "./result/lib"
    fi
  done
fi

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

  staged_target_dir="${target_dir}.next"
  stage_libs=0

  if [[ -d "./result/lib" ]]; then
    stage_libs=1
  fi

  # stage the new build in a fresh directory, then swap it into place remotely
  ssh "${target_user}@${target_host}" \
    "bash -lc 'rm -rf ${staged_target_dir}; mkdir -p ${staged_target_dir}/bin'"
  scp "${bin_files[@]}" "${target_user}@${target_host}:${staged_target_dir}/bin/"

  if [[ ${stage_libs} -eq 1 ]]; then
    ssh "${target_user}@${target_host}" \
      "bash -lc 'mkdir -p ${staged_target_dir}/lib'"
    scp ./result/lib/* "${target_user}@${target_host}:${staged_target_dir}/lib/"
  fi

  # restart the process
  ssh "${target_user}@${target_host}" "pkill -9 main_compute >/dev/null 2>&1 || true"
  ssh "${target_user}@${target_host}" \
    "bash -lc 'rm -rf ${target_dir_bak}; if [[ -e ${target_dir} ]]; then mv ${target_dir} ${target_dir_bak}; fi; mv ${staged_target_dir} ${target_dir}; nohup ${target_dir}/bin/main_compute >/dev/null 2>&1 &'"
fi
