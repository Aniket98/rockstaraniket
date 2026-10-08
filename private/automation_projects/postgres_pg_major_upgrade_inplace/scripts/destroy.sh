#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS="$ROOT/runs"
ID=""
while (($#)); do
  case "$1" in
    --runid=*) ID="${1#*=}" ;;
    -h|--help) echo "Usage: $0 --runid=R<n>"; exit 0 ;;
    *) echo "[ERROR] Unknown option $1" >&2; exit 1 ;;
  esac
  shift
done
[[ "$ID" =~ ^R[1-9][0-9]*$ ]] || { echo "[ERROR] Invalid run ID" >&2; exit 1; }
TARGET="$RUNS/PG_RUN_ID_$ID"
[[ -d "$TARGET" ]] || { echo "[ERROR] Run does not exist: $ID" >&2; exit 1; }
echo "WARNING: permanently deleting $TARGET"
read -r -p "Type '$ID' to confirm: " C
[[ "$C" == "$ID" ]] || { echo "Cancelled"; exit 1; }
rm -rf -- "$TARGET"
echo "Destroyed PG_RUN_ID_$ID"
