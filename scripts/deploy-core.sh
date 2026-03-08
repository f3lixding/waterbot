#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'EOF'
Usage:
  deploy-core.sh <build|deploy> [options]

Options:
  --mode <package|nixos>      Build/deploy a package (default) or a NixOS system.
  --flake-attr <attr>         Flake attribute to build/deploy (default: default).
  --pkg <name>                Package folder under pkgs/ (shorthand for --flake-attr).
  --target-host <host>        Target host for deployment (required for deploy).
  --target-user <user>        Target SSH user (default: pi).

Examples:
  deploy-core.sh build --mode package --flake-attr default
  deploy-core.sh build --mode package --pkg main_compute
  deploy-core.sh deploy --mode package --pkg main_compute --target-host raspberrypi.local
  deploy-core.sh deploy --mode nixos --flake-attr pi --target-host raspberrypi.local
EOF
}

if [[ $# -lt 1 ]]; then
  print_usage
  exit 2
fi

command="$1"
shift

mode="package"
flake_attr="default"
pkg_name=""
target_host=""
target_user="pi"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      mode="$2"
      shift 2
      ;;
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

if [[ "$mode" != "package" && "$mode" != "nixos" ]]; then
  echo "Unknown mode: $mode" >&2
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

if [[ "$mode" == "package" ]]; then
  nix build ".#${flake_attr}"

  if [[ "$command" == "deploy" ]]; then
    nix copy --to "ssh://${target_user}@${target_host}" ./result
  fi
else
  if [[ "$command" == "build" ]]; then
    nix build ".#nixosConfigurations.${flake_attr}.config.system.build.toplevel"
  else
    nixos-rebuild switch \
      --flake ".#${flake_attr}" \
      --target-host "${target_user}@${target_host}" \
      --build-host localhost
  fi
fi
