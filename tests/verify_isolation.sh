#!/usr/bin/env bash
# Runs the isolation verification sequence on a Linux test machine:
#   1. isolation_check  (res://tests/isolation_check.tscn, ISOLATION_OK)
#   2. laser_stress     (res://tests/laser_stress.tscn, STRESS_OK)
#   3. smoke suite      (res://tests/smoke_all.tscn, SMOKE_ALL_OK)
# Each step goes through tests/run_smoke.sh, which supplies the throwaway user
# data dir, clears the relay env vars inside the Godot environment and checks
# the pass marker under a watchdog. The test scenes apply the in-process stubs
# (tests/test_isolation.gd, smoke_all.gd). This script adds the preconditions
# and the sequencing; it does not duplicate those protections.
#
# Usage:
#   tests/verify_isolation.sh /path/to/godot
#     The Godot binary must be given explicitly as a path to an executable
#     file. No PATH lookup and no Flatpak. It must report version 4.6.
#
# Environment (optional):
#   VERIFY_LOG_DIR  directory for the logs (default: a new temp dir, printed).
#                   Must not exist yet or must be empty.
#   SMOKE_TIMEOUT   passed through to run_smoke.sh (watchdog seconds per step).
#
# Refuses to run (exit 2):
#   - on co1n (the streaming PC; its Godot can touch the real overlay data),
#   - in a checkout that contains nivek_relay.env,
#   - with a Godot binary that is not 4.6.
#
# Stops at the first failed step (wrapper exit code, missing pass marker, or a
# missing required line below) and returns nonzero. Steps after it are not run.
#
# Scope: covers the nivek relay and Twitch startup only. Other code paths that
# may use the network are not audited, so this is not proof of offline
# operation. See docs/TESTING.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

die() { echo "verify_isolation: REFUSED: $*" >&2; exit 2; }

# --- Preconditions (no Godot invocation before these pass) -------------------

GODOT_BIN="${1:-}"
[[ -n "$GODOT_BIN" ]] || die "pass the Godot 4.6 binary path as arg 1"
[[ "$GODOT_BIN" == */* ]] || die "'$GODOT_BIN' is not a path; give the binary's path explicitly"
[[ -f "$GODOT_BIN" && -x "$GODOT_BIN" ]] || die "'$GODOT_BIN' is not an executable file"
GODOT_BIN="$(cd "$(dirname "$GODOT_BIN")" && pwd)/$(basename "$GODOT_BIN")"

HOST="$(uname -n)"
HOST_SHORT="${HOST%%.*}"
if [[ "${HOST_SHORT,,}" == "co1n" ]]; then
	die "this is co1n; never run Godot here (see docs/TESTING.md)"
fi

if [[ -e "$REPO/nivek_relay.env" || -L "$REPO/nivek_relay.env" ]]; then
	die "$REPO/nivek_relay.env exists; use a clean clone without it"
fi

# Clear relay config and wrapper overrides for every child process. run_smoke.sh
# clears the relay vars again inside the Godot environment.
unset NIVEK_DEVICE_TOKEN NIVEK_RELAY_URL RSO_SMOKE_DATA_DIR GODOT \
	SMOKE_SCENE SMOKE_MARKER SMOKE_LOG SMOKE_KEEP_DATA

if [[ -n "${VERIFY_LOG_DIR:-}" ]]; then
	LOG_DIR="$VERIFY_LOG_DIR"
	mkdir -p "$LOG_DIR" || die "cannot create $LOG_DIR"
	[[ -z "$(ls -A "$LOG_DIR")" ]] || die "$LOG_DIR is not empty; logs must not mix runs"
else
	LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rso-verify.XXXXXX")"
fi
LOG_DIR="$(cd "$LOG_DIR" && pwd)"

# Godot version, from a throwaway data dir as well, and run from that dir so no
# project.godot is picked up from the working directory.
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_ROOT"
VERSION_DATA="$(mktemp -d "$CACHE_ROOT/rso-verify-version.XXXXXX")"
trap 'rm -rf "$VERSION_DATA"' EXIT
VERSION_LOG="$LOG_DIR/00-godot-version.log"
(cd "$VERSION_DATA" && XDG_DATA_HOME="$VERSION_DATA" timeout 60 "$GODOT_BIN" --headless --version) >"$VERSION_LOG" 2>&1
version_rc=$?
GODOT_VERSION="$(grep -m1 -E '^[0-9]+\.[0-9]+' "$VERSION_LOG")"
if (( version_rc != 0 )) || [[ ! "$GODOT_VERSION" =~ ^4\.6(\.|$) ]]; then
	die "Godot version check failed (exit $version_rc, version '${GODOT_VERSION:-none}'); need 4.6. See $VERSION_LOG"
fi

COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
DIRTY="$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null | wc -l)"

# --- Steps --------------------------------------------------------------------

STEPS=(isolation_check laser_stress smoke_all)
declare -A RESULT=([isolation_check]="not run" [laser_stress]="not run" [smoke_all]="not run")
declare -A LOGS=()

summary() {
	echo
	echo "verify_isolation: summary"
	echo "  commit:   $COMMIT$( (( DIRTY > 0 )) && echo " (+$DIRTY modified tracked file(s))")"
	echo "  godot:    $GODOT_VERSION ($GODOT_BIN)"
	echo "  platform: $(uname -srm)"
	echo "  logs:     $LOG_DIR"
	local s
	for s in "${STEPS[@]}"; do
		printf '  %-16s %s%s\n' "$s" "${RESULT[$s]}" "${LOGS[$s]:+  (${LOGS[$s]})}"
	done
	echo "  scope:    nivek relay and Twitch startup only; other network paths are unaudited"
}

# require_lines LOG STEP PATTERN... : every extended-regex PATTERN must match a line.
require_lines() {
	local log="$1" step="$2"; shift 2
	local p missing=0
	for p in "$@"; do
		if ! grep -qE "$p" "$log"; then
			echo "verify_isolation: $step: required line missing: $p"
			missing=1
		fi
	done
	return "$missing"
}

# run_step NAME SCENE MARKER NN : runs one scene through run_smoke.sh.
run_step() {
	local name="$1" scene="$2" marker="$3" n="$4"
	local log="$LOG_DIR/$n-$name.log"
	LOGS[$name]="$log"
	echo
	echo "verify_isolation: step $n: $name"
	SMOKE_SCENE="$scene" SMOKE_MARKER="$marker" SMOKE_LOG="$log" \
		"$SCRIPT_DIR/run_smoke.sh" "$GODOT_BIN"
	local rc=$?
	if (( rc != 0 )); then
		RESULT[$name]="FAIL (run_smoke.sh exit $rc)"
		summary
		exit "$rc"
	fi
	RESULT[$name]="PASS"
}

fail_step() {
	RESULT[$1]="FAIL ($2)"
	summary
	exit 1
}

echo "verify_isolation: commit=$COMMIT godot=$GODOT_VERSION host=$HOST_SHORT logs=$LOG_DIR"

# 1. Isolation check. ISOLATION_OK already requires every check, but require
# the positive control explicitly so it cannot silently drop out.
run_step isolation_check res://tests/isolation_check.tscn ISOLATION_OK 01
require_lines "${LOGS[isolation_check]}" isolation_check \
	'^ISOLATION stubs_in_time OK' '^ISOLATION data_dir OK' '^ISOLATION clean_checkout OK' \
	'^ISOLATION relay_no_connection OK' '^ISOLATION network_inert OK' \
	'^ISOLATION control_connects OK' \
	|| fail_step isolation_check "required ISOLATION line missing"

# 2. Laser stress, including its post-boot inert check.
run_step laser_stress res://tests/laser_stress.tscn STRESS_OK 02
require_lines "${LOGS[laser_stress]}" laser_stress '^STRESS: relay and Twitch inert$' \
	|| fail_step laser_stress "inert check line missing"

# 3. Smoke suite.
run_step smoke_all res://tests/smoke_all.tscn SMOKE_ALL_OK 03
if grep -qE '^SMOKE .* FAIL' "${LOGS[smoke_all]}"; then
	fail_step smoke_all "SMOKE FAIL line(s) in log"
fi

summary
echo "verify_isolation: PASS"
exit 0
