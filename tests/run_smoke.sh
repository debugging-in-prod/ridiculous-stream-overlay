#!/usr/bin/env bash
# Runs the headless smoke test (res://tests/smoke_all.tscn) under a watchdog.
#
# Usage:
#   tests/run_smoke.sh [GODOT]
#     GODOT    path to a Godot 4.6 binary, or "flatpak" / "flatpak:<app-id>" for the
#              Flathub build (default app id org.godotengine.Godot).
#              Falls back to $GODOT, then godot4/godot on PATH, then the Flatpak.
#
# Environment (all optional):
#   SMOKE_TIMEOUT    watchdog seconds (default 90); the run is killed after this.
#   SMOKE_SCENE      scene to run (default res://tests/smoke_all.tscn).
#   SMOKE_MARKER     line that must appear in the output (default SMOKE_ALL_OK).
#                    For the laser stress test:
#                    SMOKE_SCENE=res://tests/laser_stress.tscn SMOKE_MARKER=STRESS_OK tests/run_smoke.sh
#   SMOKE_LOG        where to write the full log (default: a temp file, path printed).
#   SMOKE_KEEP_DATA  1 to keep the throwaway user data dir after the run.
#
# The run uses a fresh, throwaway user data dir (XDG_DATA_HOME), so your real
# settings.tres, Twitch tokens, users and nivek relay cursor are never touched.
# Note that the Flatpak overrides XDG_DATA_HOME from outside the sandbox, so for
# Flatpak it is exported inside the sandbox instead.
#
# Exit code: 0 only if the marker line appears and Godot exits 0;
#            124 on watchdog timeout; otherwise nonzero.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SCENE="${SMOKE_SCENE:-res://tests/smoke_all.tscn}"
MARKER="${SMOKE_MARKER:-SMOKE_ALL_OK}"
TIMEOUT="${SMOKE_TIMEOUT:-90}"

GODOT_BIN="${1:-${GODOT:-}}"
if [[ -z "$GODOT_BIN" ]]; then
	if command -v godot4 >/dev/null 2>&1; then GODOT_BIN="godot4"
	elif command -v godot >/dev/null 2>&1; then GODOT_BIN="godot"
	elif command -v flatpak >/dev/null 2>&1 && flatpak info org.godotengine.Godot >/dev/null 2>&1; then GODOT_BIN="flatpak"
	else
		echo "run_smoke: no Godot found. Pass the binary as arg 1 or set GODOT." >&2
		exit 2
	fi
fi

# Throwaway data dir under $HOME (the Flatpak sandbox has a private /tmp).
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p "$CACHE_ROOT"
DATA="$(mktemp -d "$CACHE_ROOT/rso-smoke.XXXXXX")"
LOG="${SMOKE_LOG:-$(mktemp "${TMPDIR:-/tmp}/rso-smoke-log.XXXXXX")}"
cleanup() {
	if [[ "${SMOKE_KEEP_DATA:-0}" != "1" ]]; then rm -rf "$DATA"; fi
}
trap cleanup EXIT

# Never let a real relay token/url leak into the run (the test stubs these too).
unset NIVEK_DEVICE_TOKEN NIVEK_RELAY_URL

run_godot() {
	if [[ "$GODOT_BIN" == flatpak || "$GODOT_BIN" == flatpak:* ]]; then
		local app_id="org.godotengine.Godot"
		[[ "$GODOT_BIN" == flatpak:* ]] && app_id="${GODOT_BIN#flatpak:}"
		flatpak run --command=sh "$app_id" -c \
			'export XDG_DATA_HOME="$1" RSO_SMOKE_DATA_DIR="$1"; unset NIVEK_DEVICE_TOKEN NIVEK_RELAY_URL; shift; exec godot "$@"' \
			sh "$DATA" "$@"
	else
		XDG_DATA_HOME="$DATA" RSO_SMOKE_DATA_DIR="$DATA" "$GODOT_BIN" "$@"
	fi
}

# Runs "$@" (a run_godot invocation) with a watchdog of $1 seconds. Output goes
# to stdout and is appended to $LOG. Returns the command's exit code, or 124 on timeout.
with_watchdog() {
	local secs="$1"; shift
	# Job control gives the background pipeline its own process group, so the
	# whole tree (subshell, tee, flatpak/bwrap, godot) can be killed at once.
	set -m
	( "$@" 2>&1 | tee -a "$LOG"; exit "${PIPESTATUS[0]}" ) &
	local pid=$!
	set +m
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if (( waited >= secs * 10 )); then
			echo "run_smoke: TIMEOUT after ${secs}s, killing Godot" | tee -a "$LOG"
			kill -TERM -- "-$pid" 2>/dev/null
			sleep 3
			kill -KILL -- "-$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
			return 124
		fi
		sleep 0.1
		waited=$((waited + 1))
	done
	wait "$pid"
	return $?
}

echo "run_smoke: godot=$GODOT_BIN repo=$REPO scene=$SCENE timeout=${TIMEOUT}s"
echo "run_smoke: log=$LOG"
: > "$LOG"

# A fresh clone has no .godot/ import cache; without it the main scene fails to
# load. Import once first (this only writes the gitignored .godot/ folder).
if [[ ! -d "$REPO/.godot/imported" ]]; then
	echo "run_smoke: no .godot import cache, importing assets first"
	with_watchdog 300 run_godot --headless --path "$REPO" --import
	rc=$?
	if (( rc == 124 )); then echo "run_smoke: FAIL (import timed out)"; exit 124; fi
fi

with_watchdog "$TIMEOUT" run_godot --headless --path "$REPO" "$SCENE"
rc=$?

if (( rc == 124 )); then
	echo "run_smoke: FAIL (timed out after ${TIMEOUT}s; last progress line above shows where it hung)"
	exit 124
fi
if ! grep -q "^${MARKER}\$" "$LOG"; then
	echo "run_smoke: FAIL ($MARKER not found, godot exit code $rc)"
	grep -E "^SMOKE .* FAIL" "$LOG" || true
	exit $(( rc == 0 ? 1 : rc ))
fi
if (( rc != 0 )); then
	echo "run_smoke: FAIL ($MARKER printed but godot exited $rc)"
	exit "$rc"
fi
echo "run_smoke: PASS"
exit 0
