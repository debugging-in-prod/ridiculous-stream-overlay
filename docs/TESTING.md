# Testing

There are two automated headless tests and one manual checklist:

| Test | What it covers | Pass marker | Typical time |
|---|---|---|---|
| `tests/smoke_all.tscn` | Every headless-testable feature in [FEATURES.md](FEATURES.md): one `SMOKE <name> OK\|FAIL <detail>` line per feature | `SMOKE_ALL_OK` | ~30 s |
| `tests/laser_stress.tscn` | Regression test for the beans + laser physics hang (issue #9 / PR #10) | `STRESS_OK` | ~30 s |
| [FEATURES.md → Manual by-eye checklist](FEATURES.md#manual-by-eye-checklist) | Transparency, always-on-top, click-through, window fit, config round-trip. These can't be checked headless. | you | ~5 min |

Both automated tests boot the real `RS` autoload (`rs_main.tscn`). They must
run with a **throwaway user data dir**. Otherwise they load your real
`settings.tres`, connect the nivek relay with your device token, replay relay
events and move your real relay cursor forward. Use the wrapper scripts below,
which set this up for you.

## Requirements

- Godot **4.6** (4.5+ is needed for the `Logger` API the smoke test uses).
  Stock or patched both work, since the tests are headless. On Windows, use
  `godot_*_console.exe` so output is captured.
- A one-time asset import. A fresh clone has no `.godot/` folder, and
  `rs_main.tscn` then fails to load ("referenced non-existent resource"). The
  wrappers run `--headless --import` automatically when `.godot/imported` is
  missing. To do it by hand: `<godot> --headless --path <repo> --import`.

## Running on Linux

```bash
# native binary (arg 1, or $GODOT, or godot4/godot on PATH)
tests/run_smoke.sh /path/to/godot
GODOT=/path/to/godot tests/run_smoke.sh

# Flathub build (org.godotengine.Godot), or flatpak:<app-id> for another one
tests/run_smoke.sh flatpak

# laser stress through the same wrapper (isolation + watchdog)
SMOKE_SCENE=res://tests/laser_stress.tscn SMOKE_MARKER=STRESS_OK tests/run_smoke.sh flatpak
```

Options (environment variables):
- `SMOKE_TIMEOUT`: watchdog in seconds, default 90.
- `SMOKE_LOG`: log path. By default a temp file, whose path is printed.
- `SMOKE_KEEP_DATA=1`: keep the throwaway data dir.

Exit codes:
- `0`: the marker was printed and Godot exited 0.
- `124`: the watchdog killed it (a hang; the last `SMOKE`/`STRESS:` line shows
  where).
- anything else: failure.

How the isolation works:
- The data dir is `mktemp -d ~/.cache/rso-smoke.XXXXXX`, exported as
  `XDG_DATA_HOME`.
- **Flatpak:** the Flathub Godot forces its own `XDG_DATA_HOME` and ignores
  `flatpak run --env=...`. The wrapper therefore exports it *inside* the
  sandbox (`flatpak run --command=sh … -c 'export XDG_DATA_HOME=…; exec godot …'`).
  The dir sits under `$HOME` because the sandbox's `/tmp` is private. If you
  run laser_stress by hand with `XDG_DATA_HOME=$(mktemp -d) flatpak run …`, as
  its header comment suggests, **it uses your real data dir**.
- The Flatpak needs filesystem access to the repo. The Flathub build ships
  with `filesystems=host`.

Manual run without the wrapper (native binary only):

```bash
D=$(mktemp -d)
RSO_SMOKE_DATA_DIR=$D XDG_DATA_HOME=$D /path/to/godot --headless --path . res://tests/smoke_all.tscn
XDG_DATA_HOME=$D /path/to/godot --headless --path . res://tests/laser_stress.tscn
```

## Running on Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File tests\run_smoke.ps1 C:\Godot\Godot_v4.6.1-stable_win64_console.exe
$env:GODOT = 'C:\Godot\Godot_v4.6.1-stable_win64_console.exe'; .\tests\run_smoke.ps1

# laser stress
$env:SMOKE_SCENE = 'res://tests/laser_stress.tscn'; $env:SMOKE_MARKER = 'STRESS_OK'
.\tests\run_smoke.ps1 C:\Godot\Godot_v4.6.1-stable_win64_console.exe
Remove-Item Env:SMOKE_SCENE, Env:SMOKE_MARKER
```

The wrapper takes the same options and exit codes as on Linux. It isolates the
data dir by pointing `APPDATA` at a temp folder. Godot stores user data in
`%APPDATA%\Godot\app_userdata\Ridiculous Stream`. On timeout it kills the whole
process tree (`taskkill /T /F`).

> `run_smoke.ps1` hasn't been run yet. It was written on Linux without
> PowerShell available. Please report the first Windows run, pass or fail.

## How the smoke test works

- `tests/smoke_all.gd` runs as the main scene. Its `_ready` runs before
  `RSMain.start_everything()` resumes (that function awaits one frame first).
  `_ready` does two things:
  1. **Refuses to run** unless `OS.get_user_data_dir()` is inside
     `RSO_SMOKE_DATA_DIR`. You get `SMOKE isolation FAIL` and exit 1.
  2. **Stubs the network** in memory:
     - Clears the Twitch `client_id`/`client_secret` and `auto_connect`, so
       `RSTwitcher.start()` aborts.
     - Clears the relay token and url, and unsets the `NIVEK_*` env vars.
     - Pins the relay's `nivek_relay.env` cache empty, so the relay stays
       disabled.
- Features are triggered through their real entry points:
  - floating-menu handlers;
  - `RSCustom` command and reward functions;
  - `RSTwitcher.on_event(...)` with EventSub-shaped payloads;
  - `RSNivekRelay._on_message(...)` with relay JSON frames.
- Each check then waits on frames or timers and verifies state: body counts,
  gravity, visibility, playing audio, cursor file, settings file.
- A feature also FAILs if it raised a GDScript error, or an engine error with a
  GDScript backtrace, while running (via `OS.add_logger`).
- Users are resolved through an injected fake known user (`rso_smoke_user`), so
  no Twitch API lookups happen.
- `event_alerts` feeds EventSub `channel.follow`, `channel.raid` and
  `channel.subscribe` payloads into `RSTwitcher.on_event` with "Names on
  screen" off. For each one it asserts that exactly one new `CanvasLayer` in
  group `rs_event_alert` (`RSCustom.EVENT_ALERT_GROUP`) appears, with meta
  `event_kind` = `follow`/`raid`/`sub` and a child Label `lb_event_alert` whose
  text contains the user's name. It then waits for the alerts to free
  themselves, sets `RS.settings.event_alerts_enabled = false`, replays the three
  events and asserts that no alert spawns. Only nodes are checked, no pixels.
- `event_alerts_gift_bomb` fires 15 gifted `channel.subscribe` events in one
  frame. It asserts that at most `RSCustom.EVENT_ALERT_MAX_SLOTS` (4) alerts are
  live, that every `lb_event_alert` sits in a valid slot whose bottom fits the
  configured window height (`display/window/size/viewport_height`, not the
  64x64 headless viewport), and that the
  sfx was requested exactly once (`RS.custom.event_alert_sfx_plays`). Then it
  waits for the alerts to free themselves.

Not covered, and why: see the "Headless" column in [FEATURES.md](FEATURES.md).
In short: anything that needs OBS, Twitch chat/API, a browser or external
program, a human decision, real rendering (the names text is read back from a
SubViewport, which the dummy renderer can't do), or a real window manager.

All 29 checks are expected to pass.

## Turning failures into GitHub issues

Repo: **debugging-in-prod/ridiculous-stream-overlay**.

Rules:
- **One issue per failing feature line** (`SMOKE <name> FAIL …`), per timeout,
  or per failed manual-checklist item. Don't bundle them.
- **Search first** so you don't file duplicates. If an issue exists, add your
  platform and log as a comment:
  `gh issue list -R debugging-in-prod/ridiculous-stream-overlay --search "<name> in:title" --state all`
- **Labels:** `bug`, plus the platform you saw it on: `linux` and/or
  `windows`. If both show it, use both labels on one issue.
  - The `windows` label exists. **`linux` doesn't exist yet**; create it once:
    `gh label create linux -R debugging-in-prod/ridiculous-stream-overlay --color FCC624 --description "Linux-specific"`
- **Title:** `smoke: <feature name> fails – <short symptom>`. For a hang use
  `smoke: timeout after <last SMOKE line>`. For a manual item use
  `manual: <checklist item>`.

Body template:

````markdown
## What failed
`SMOKE <name> FAIL <detail>`  (or: timeout / manual checklist item "<item>")

## Environment
- OS / session: e.g. Pop!_OS 24.04, Wayland (COSMIC) | Windows 11 23H2
- Godot: 4.6.1-stable, native / Flatpak / patched (godot-patches)
- Commit: `git rev-parse --short HEAD`

## Repro steps
1. `git checkout <commit>`
2. `tests/run_smoke.sh <godot>`  (or `tests\run_smoke.ps1 <godot>`)
3. Observe the line above. (Manual items: the exact clicks and what you saw.)

## Expected
<the "Correct run" column for this feature in docs/FEATURES.md>

## Log excerpt
```
<the FAIL line, the 10-20 lines before it, any SCRIPT ERROR / backtrace lines,
 and the final "SMOKE summary" line>
```

## Notes
<entry point from docs/FEATURES.md, suspected cause if known>
````

Filing from the command line (after checking that the log excerpt contains no
tokens or other secrets):

```bash
gh issue create -R debugging-in-prod/ridiculous-stream-overlay \
  --title "smoke: <feature name> fails – <short symptom>" \
  --label bug --label linux \
  --body-file /tmp/issue.md
```

Log hygiene: the throwaway data dir means logs shouldn't contain your
credentials. Still, skim the excerpt before posting. Never attach
`settings.tres`, `nivek_relay.env`, `twitch_oauth_*.tres`, or a log from a run
that used your real data dir.
