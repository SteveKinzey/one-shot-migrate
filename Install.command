#!/bin/bash
# Install.command — v1.1.1
# Double-clickable launcher for macOS (Finder).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

chmod +x ./one-shot-migrate.sh 2>/dev/null || true

has_osascript=0
command -v osascript >/dev/null 2>&1 && has_osascript=1

choose_preset() {
  if [[ "$has_osascript" == "1" ]]; then
    osascript <<'OSA'
set choices to {"Keep current exclude.txt","minimal (Library + macOS metadata)","developer-heavy (skip caches)","media-keeper (keep project deps)"}
set c to choose from list choices with prompt "Pick an exclusion preset (you can edit later):" default items {"Keep current exclude.txt"}
if c is false then return "KEEP"
set v to item 1 of c
if v is "Keep current exclude.txt" then return "KEEP"
if v is "minimal (Library + macOS metadata)" then return "minimal.txt"
if v is "developer-heavy (skip caches)" then return "developer-heavy.txt"
if v is "media-keeper (keep project deps)" then return "media-keeper.txt"
return "KEEP"
OSA
  else
    echo "Pick an exclusion preset:"
    echo "  1) Keep current exclude.txt"
    echo "  2) minimal"
    echo "  3) developer-heavy"
    echo "  4) media-keeper"
    read -r -p "Choose [1-4]: " n
    case "${n:-1}" in
      2) echo "minimal.txt" ;;
      3) echo "developer-heavy.txt" ;;
      4) echo "media-keeper.txt" ;;
      *) echo "KEEP" ;;
    esac
  fi
}

ask_yesno() {
  local prompt="$1"
  local default="$2"
  if [[ "$has_osascript" == "1" ]]; then
    osascript <<OSA
display dialog "$prompt" buttons {"No","Yes"} default button "$default"
button returned of result
OSA
  else
    read -r -p "$prompt (y/N): " yn
    [[ "$yn" =~ ^[Yy]$ ]] && echo "Yes" || echo "No"
  fi
}

ask_mode() {
  if [[ "$has_osascript" == "1" ]]; then
    osascript <<'OSA'
set choices to {"DRYRUN","RUN"}
set c to choose from list choices with prompt "Choose run mode:" default items {"DRYRUN"}
if c is false then return "DRYRUN"
return item 1 of c
OSA
  else
    echo "Choose run mode:"
    echo "  1) DRYRUN (preview only)"
    echo "  2) RUN (real copy)"
    read -r -p "Choose [1-2]: " n
    [[ "${n:-1}" == "2" ]] && echo "RUN" || echo "DRYRUN"
  fi
}

preset="$(choose_preset)"
if [[ "$preset" != "KEEP" ]]; then
  cp -f "./presets/$preset" ./exclude.txt
fi

edit="$(ask_yesno "Do you want to edit exclude.txt now?" "Yes")"
if [[ "$edit" == "Yes" ]]; then
  open -t ./exclude.txt || true
fi

mode="$(ask_mode)"
verify="$(ask_yesno "Enable checksum verification after copy?" "Yes")"
bg="$(ask_yesno "Run in background (recommended for many files)?" "Yes")"

export DRYRUN=0
export VERIFY=1
[[ "$mode" == "DRYRUN" ]] && export DRYRUN=1
[[ "$verify" == "No" ]] && export VERIFY=0

echo ""
echo "Mode: DRYRUN=$DRYRUN  VERIFY=$VERIFY"
echo ""

if [[ "$bg" == "Yes" && "$DRYRUN" == "0" ]]; then
  mkdir -p "$HOME/migration_logs"
  nohup ./one-shot-migrate.sh > "$HOME/migration_logs/one_shot_run.out" 2>&1 &
  msg="Migration started in background.\n\nLog: ~/migration_logs/one_shot_run.out\n\nFollow: tail -f ~/migration_logs/one_shot_run.out"
  echo "$msg"
  [[ "$has_osascript" == "1" ]] && osascript -e "display dialog \"$msg\" buttons {\"OK\"} default button \"OK\""
  exit 0
fi

./one-shot-migrate.sh
