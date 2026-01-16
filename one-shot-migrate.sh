#!/bin/bash
# one-shot-migrate.sh
# Release: v1.1.1
# Updated: 2026-01-16
# Production: data-only migration between macOS users using Homebrew rsync.
# - Prompts for OLD + NEW usernames (no hard-coded usernames)
# - Forces Homebrew install if missing (non-interactive)
# - Installs + pins rsync (Homebrew) to avoid /usr/bin/rsync limitations
# - Copies: Desktop, Documents, Downloads, Pictures, Movies, Music
# - Excludes patterns from exclude.txt (defaults skip ~/Library)
# - Default verify: checksum comparison pass after copy (VERIFY=1)

set -euo pipefail

# Tip: swap exclude presets: cp -f ./presets/<name>.txt ./exclude.txt


say() { printf "%s\n" "$*"; }
die() { say "ERROR: $*"; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  ./one-shot-migrate.sh

Environment toggles:
  DRYRUN=1   Show what would copy, without copying
  VERIFY=0   Disable checksum verification pass (default VERIFY=1)

Notes:
  - Run from the OLD user account (source).
  - The script will prompt for OLD and NEW usernames.
  - The NEW user must already exist.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

prompt() {
  local label="$1"
  local default="$2"
  local value=""
  read -r -p "${label} [${default}]: " value
  if [[ -z "${value}" ]]; then value="${default}"; fi
  printf "%s" "${value}"
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    die "This script is intended for macOS (Darwin)."
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCLUDE_FILE="${SCRIPT_DIR}/exclude.txt"
[[ -f "${EXCLUDE_FILE}" ]] || die "Missing exclude file: ${EXCLUDE_FILE}"

require_macos

CURRENT_USER="$(whoami)"
OLD_USER="$(prompt "Old username (source)" "${CURRENT_USER}")"
NEW_USER="$(prompt "New username (destination)" "newuser")"

[[ "${OLD_USER}" != "${NEW_USER}" ]] || die "Old and new usernames must be different."

OLD_HOME="/Users/${OLD_USER}"
NEW_HOME="/Users/${NEW_USER}"

[[ -d "${OLD_HOME}" ]] || die "Old home not found: ${OLD_HOME}"
id -u "${NEW_USER}" >/dev/null 2>&1 || die "New user '${NEW_USER}' does not exist. Create it first."
[[ -d "${NEW_HOME}" ]] || die "New home not found: ${NEW_HOME}"

SRC_DIRS=("Desktop" "Documents" "Downloads" "Pictures" "Movies" "Music")

timestamp() { date +"%Y-%m-%d_%H-%M-%S"; }
LOG_DIR="${OLD_HOME}/migration_logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/migration_${OLD_USER}_to_${NEW_USER}_$(timestamp).log"

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  say "Homebrew not found. Installing Homebrew (non-interactive)..." | tee -a "${LOG_FILE}"
  say "If this fails, run: xcode-select --install" | tee -a "${LOG_FILE}"

  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    2>&1 | tee -a "${LOG_FILE}"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    die "Homebrew installed but brew not found in /opt/homebrew or /usr/local."
  fi

  command -v brew >/dev/null 2>&1 || die "brew still not available after install."
}

RSYNC_BIN=""
ensure_rsync_and_pin() {
  say "Ensuring Homebrew rsync is installed..." | tee -a "${LOG_FILE}"

  if ! brew list rsync >/dev/null 2>&1; then
    brew install rsync 2>&1 | tee -a "${LOG_FILE}"
  fi

  brew pin rsync >/dev/null 2>&1 || true

  local BREW_PREFIX
  BREW_PREFIX="$(brew --prefix)"
  [[ -x "${BREW_PREFIX}/bin/rsync" ]] || die "Homebrew rsync not found at ${BREW_PREFIX}/bin/rsync"
  RSYNC_BIN="${BREW_PREFIX}/bin/rsync"
}

ensure_brew
ensure_rsync_and_pin

RSYNC_EXCLUDE_ARGS=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "${line}" ]] && continue
  [[ "${line}" == \#* ]] && continue
  RSYNC_EXCLUDE_ARGS+=(--exclude "${line}")
done < "${EXCLUDE_FILE}"

RSYNC_OPTS=(-aEH --stats)
if "${RSYNC_BIN}" --help 2>&1 | grep -q -- "--info"; then
  RSYNC_OPTS+=(--info=progress2)
else
  RSYNC_OPTS+=(--progress)
fi
if "${RSYNC_BIN}" --help 2>&1 | grep -q -- "--protect-args"; then
  RSYNC_OPTS+=(--protect-args)
fi
RSYNC_OPTS+=(--partial --partial-dir=.rsync-partial)

DRYRUN_ARGS=()
if [[ "${DRYRUN:-0}" == "1" ]]; then
  DRYRUN_ARGS+=(--dry-run)
fi

say "=== One-shot migration started: $(date) ===" | tee -a "${LOG_FILE}"
say "From: ${OLD_HOME}" | tee -a "${LOG_FILE}"
say "To:   ${NEW_HOME}" | tee -a "${LOG_FILE}"
say "Rsync: ${RSYNC_BIN}" | tee -a "${LOG_FILE}"
say "Pinned formulas: $(brew list --pinned 2>/dev/null | tr '\n' ' ')" | tee -a "${LOG_FILE}"
say "Exclude file: ${EXCLUDE_FILE}" | tee -a "${LOG_FILE}"
say "Log:  ${LOG_FILE}" | tee -a "${LOG_FILE}"
if [[ "${DRYRUN:-0}" == "1" ]]; then
  say "Mode: DRYRUN=1 (no files will be copied)" | tee -a "${LOG_FILE}"
fi
if [[ "${VERIFY:-1}" == "0" ]]; then
  say "Mode: VERIFY=0 (checksum verification disabled)" | tee -a "${LOG_FILE}"
fi
say "" | tee -a "${LOG_FILE}"

say "=== Copy phase ===" | tee -a "${LOG_FILE}"
COPIED_TARGETS=()

for d in "${SRC_DIRS[@]}"; do
  src="${OLD_HOME}/${d}/"
  dst="${NEW_HOME}/${d}/"

  if [[ ! -d "${src}" ]]; then
    say "SKIP: ${src} (missing)" | tee -a "${LOG_FILE}"
    continue
  fi

  mkdir -p "${dst}"
  COPIED_TARGETS+=("${dst}")

  say "" | tee -a "${LOG_FILE}"
  say "--- Rsync ${d} ---" | tee -a "${LOG_FILE}"
  say "SRC: ${src}" | tee -a "${LOG_FILE}"
  say "DST: ${dst}" | tee -a "${LOG_FILE}"

  "${RSYNC_BIN}" "${RSYNC_OPTS[@]}" "${DRYRUN_ARGS[@]}" "${RSYNC_EXCLUDE_ARGS[@]}" "${src}" "${dst}" \
    2>&1 | tee -a "${LOG_FILE}"
done

if [[ "${DRYRUN:-0}" != "1" ]]; then
  say "" | tee -a "${LOG_FILE}"
  say "=== Ownership fix (requires sudo) ===" | tee -a "${LOG_FILE}"
  say "You may be prompted for your macOS password." | tee -a "${LOG_FILE}"

  if [[ "${#COPIED_TARGETS[@]}" -gt 0 ]]; then
    sudo /usr/sbin/chown -R "${NEW_USER}:staff" "${COPIED_TARGETS[@]}" 2>&1 | tee -a "${LOG_FILE}"
  fi
fi

if [[ "${DRYRUN:-0}" != "1" && "${VERIFY:-1}" == "1" ]]; then
  say "" | tee -a "${LOG_FILE}"
  say "=== Verify phase (checksum compare, dry-run) ===" | tee -a "${LOG_FILE}"
  say "This reads both sides and can take time." | tee -a "${LOG_FILE}"
  say "Disable with: VERIFY=0 ./one-shot-migrate.sh" | tee -a "${LOG_FILE}"

  VERIFY_FAILED=0

  for d in "${SRC_DIRS[@]}"; do
    src="${OLD_HOME}/${d}/"
    dst="${NEW_HOME}/${d}/"
    [[ -d "${src}" ]] || continue

    say "" | tee -a "${LOG_FILE}"
    say "--- Verify ${d} ---" | tee -a "${LOG_FILE}"

    tmp="${LOG_DIR}/verify_${d}_$(timestamp).txt"
    "${RSYNC_BIN}" -aEHcni --itemize-changes "${RSYNC_EXCLUDE_ARGS[@]}" "${src}" "${dst}" \
      2>&1 | tee -a "${LOG_FILE}" | tee "${tmp}" >/dev/null

    if grep -Eq '^(>f|>d|<f|<d|\*deleting|cd|cD|cS|c\.)' "${tmp}"; then
      VERIFY_FAILED=1
      say "VERIFY: Differences detected in ${d} (see ${tmp})" | tee -a "${LOG_FILE}"
    fi
  done

  if [[ "${VERIFY_FAILED}" == "1" ]]; then
    die "Verify phase found differences. See log: ${LOG_FILE}"
  fi

  say "" | tee -a "${LOG_FILE}"
  say "Verify phase completed: no differences detected." | tee -a "${LOG_FILE}"
fi

say "" | tee -a "${LOG_FILE}"
say "=== Done: $(date) ===" | tee -a "${LOG_FILE}"
say "Log file: ${LOG_FILE}" | tee -a "${LOG_FILE}"
