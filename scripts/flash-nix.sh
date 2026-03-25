#!/user/bin/env bash 
set -euo pipefail 

print_usage() {
  cat <<'EOF'
Usage: 
  flash-nix.sh [options]

Options:
  --sd-dir <str>        Directory to the SD card
  --wifi-name <str>     SSID of the wifi you intend to join
  --wifi-pwd <str>      Password to the wifi you intend to join
EOF
}

if [[ $# -lt 1 ]]; then 
  print_usage
  exit 2
fi 

sd_dir=""
wifi_name=""
wifi_pwd=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sd-dir)
      sd_dir="$2"
      shift 2
      ;;
    --wifi-name)
      wifi_name="$2"
      shift 2
      ;;
    --wifi-pwd)
      wifi_pwd="$2"
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

