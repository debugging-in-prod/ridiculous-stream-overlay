# Testing

There are three automated headless tests and one manual checklist:

| Test | What it covers | Pass marker | Typical time |
|---|---|---|---|
| `tests/smoke_all.tscn` | Every headless-testable feature in [FEATURES.md](FEATURES.md): one `SMOKE <name> OK\|FAIL <detail>` line per feature | `SMOKE_ALL_OK` | ~30 s |
| `tests/laser_stress.tscn` | Regression test for the beans + laser physics hang (issue #9 / PR #10) | `STRESS_OK` | ~30 s |
| `tests/isolation_check.tscn` | Regression check for the network stubs `laser_stress` uses (`tests/test_isolation.gd`), with dummy relay config and a local listener | `ISOLATION_OK` | not yet measured |
| [FEATURES.md → Manual by-eye checklist](FEATURES.md#manual-by-eye-checklist) | Transparency, always-on-top, click-through, window fit, config round-trip. These can't be checked headless. | you | ~5 min |

All three automated tests boot the real `RS` autoload (`rs_main.tscn`). The
isolation comes from two places:

- **The wrapper** (`tests/run_smoke.sh`, `tests/run_smoke.ps1`) gives each run
  a throwaway user data dir and unsets `NIVEK_DEVICE_TOKEN` and
  `NIVEK_RELAY_URL`.
- **The test script** blanks the relay and Twitch settings in memory, pins the
  relay's `nivek_relay.env` cache empty so a file in the checkout is never
  read, and refuses to run outside the throwaway data dir.
  - `smoke_all.gd` does this itself.
  - `laser_stress.gd` and `isolation_check.gd` use `tests/test_isolation.gd`.

The wrapper alone is not enough. Without the test-side stubs, a run reads
`res://nivek_relay.env` and can reach the production relay. Without the
wrapper, a run uses your real `settings.tres`, Twitch tokens and relay cursor.

**Scope:** these stubs cover the nivek relay and Twitch startup
(`RSTwitcher.start()` aborts). They do not make the app fully offline. Nodes
in the Twitcher add-on run their `_ready` before any test script, and they
only stay quiet because the throwaway data dir has no Twitch tokens. Other
code paths that may use the network have not been audited for these tests.

## `test/` and `tests/`

The two directories stay separate on purpose:

- `tests/` holds the automated headless tests above and their wrappers
  (`run_smoke.sh`, `run_smoke.ps1`), which isolate the user data dir and
  check for a pass marker under a watchdog.
- `test/` holds manual developer scripts. No scene, script, wrapper or
  setting references them, and nothing runs them automatically.

| File | What it is | How to run it | Notes |
|---|---|---|---|
| `test/twitcher/pagination_test.gd` | Offline repro for the Twitcher paginated-response hang, using a fake transport | `--script`, see below | Prints `PASS`/`FAIL` but always exits 0. Matches the current add-on (`TwitchGetStreams.Response` has `_next_page` and `all()`). |
| `test/user_update_test.gd` | `EditorScript` that prints a before/after table for `RSUser.update_with_user` | Script editor → File → Run | Prints only, no assertions. |
| `test/steam_api_test.tscn` + `.gd` | `@tool` scene for trying `SteamService` / `ItchIOService` (`lib/games_info/`) from the inspector | Open the scene and pick a game in the inspector | Makes live requests to Steam and itch.io. The scene stores data from an earlier fetch. |
| `test/test_browser_history_tab.gd` | `EditorScript` experiment that opens Brave's history page | Script editor → File → Run | Hardcoded Windows Brave path, not used by the app. Kept as is; whether it is still wanted is undecided. |

### Running `test/` scripts with `--script`

**Do not use the command in `pagination_test.gd`'s header comment.** It
runs against your real user data dir and your checkout's relay config.

**Do not run Godot on co1n** (the streaming PC) for any of this: its
Flatpak build can touch the real overlay data.

A `--script` run is not the smoke harness. Godot 4.6 loads the project's
autoloads for a `--script` run just as it does for a scene (`main/main.cpp`).
So the full `RS` autoload boots, and `RSMain.start_everything()` starts the
nivek relay. The smoke harness adds protections that a plain `--script`
run does not get:

| Protection | `tests/run_smoke.*` + the test scene | Plain `--script` run |
|---|---|---|
| Throwaway user data dir | the wrapper sets one, and the test fails and stops if it isn't in use | only if you set it yourself |
| `NIVEK_DEVICE_TOKEN` / `NIVEK_RELAY_URL` env vars cleared | the wrapper clears them | only if you clear them yourself |
| `res://nivek_relay.env` ignored | the test empties the relay's env-file cache | **no**: `RSNivekRelay` reads the file from the checkout |
| Relay and Twitch settings blanked | the test blanks them | only if the data dir is fresh |

This applies to `smoke_all`, `laser_stress` and `isolation_check`.

The relay reads its settings from three places, in this order: env vars,
then `res://nivek_relay.env` in the checkout, then `settings.tres` in the
user data dir. Its URL falls back to the production URL. A fresh data dir
and cleared env vars therefore do **not** stop it: if the checkout has a
`nivek_relay.env` with a device token, the run connects to production
nivek with that token and a fresh cursor.

A `--script` run is only offline when all three of these hold:

1. **A clean test checkout with no `nivek_relay.env`.** Use a separate
   clone, not your working checkout, and don't copy the file into it.
   Moving the file aside in a dev checkout also works, but it's easy to
   forget to move it back, or to have it restored mid-run. A fresh clone
   needs the one-time `--import` (see Requirements).
2. **A throwaway user data dir.** It holds `settings.tres` (Twitch and
   relay credentials), `auth.conf` (Twitch token) and the relay cursor.
   With an empty data dir, `RSTwitcher.start()` stops at
   `is_twitcher_setup()` and the relay has no token from settings.
3. **`NIVEK_DEVICE_TOKEN` and `NIVEK_RELAY_URL` unset** in the environment
   that Godot actually runs in.

Other config sources, checked by reading the code. None needs a precaution
beyond the three above:
- `twitch_oauth_*.tres` are gitignored, and `rs_main.tscn` doesn't reference
  them.
- The Twitch values baked into `rs_main.tscn` are only used after the
  `is_twitcher_setup()` check, which reads from the user data dir.
- `project.godot` has no `ridiculous_stream/*` credential settings.
- The OBS module is disabled.

Not checked: whether Twitcher add-on nodes make network calls on their own
before that gate.

These commands have **not been run**. Check the log for
`nivek relay disabled` before trusting a run.

Linux, native binary, from the clean test checkout:

```bash
if [ -e nivek_relay.env ]; then
  echo "nivek_relay.env present: use a clean checkout" >&2
else
  D=$(mktemp -d)
  env -u NIVEK_DEVICE_TOKEN -u NIVEK_RELAY_URL XDG_DATA_HOME=$D \
    /path/to/godot --headless --path . --script res://test/twitcher/pagination_test.gd
fi
```

Windows: the same three conditions apply. Use a clean test checkout with no
`nivek_relay.env`. In that PowerShell session, set `APPDATA` to a throwaway
folder and remove `Env:NIVEK_DEVICE_TOKEN` and `Env:NIVEK_RELAY_URL`, as
`tests/run_smoke.ps1` does. Use a new PowerShell window so the changed
`APPDATA` doesn't leak into other work.

Flatpak: the same three conditions apply. The clean checkout must be the
directory passed to `--path`. Export `XDG_DATA_HOME` *inside* the sandbox,
because Flatpak overrides the host value (see Requirements). Host variables
such as `NIVEK_DEVICE_TOKEN` can pass into the sandbox, so unset the relay
variables inside it too, as `tests/run_smoke.sh` does.

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

# isolation regression check (from a checkout without nivek_relay.env)
SMOKE_SCENE=res://tests/isolation_check.tscn SMOKE_MARKER=ISOLATION_OK tests/run_smoke.sh flatpak
```

Prerequisites for the laser stress run:
- Use the wrapper. It supplies the throwaway data dir and `RSO_SMOKE_DATA_DIR`.
  Without it, `laser_stress` prints `STRESS_FAIL` and exits 1. But by then the
  Twitcher add-on has already read your real tokens.
- The test itself ignores `nivek_relay.env` and blanks Twitch, and it prints
  `STRESS_FAIL` if the relay or Twitch came up anyway.
- Run `isolation_check` once on a new machine or engine build, from a checkout
  **without** `nivek_relay.env`. It reports `clean_checkout FAIL` if the file
  is present. It proves the stubs land before the relay starts.
- Not on co1n: see the warning above about its Flatpak build.

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
  run a test by hand with `XDG_DATA_HOME=$(mktemp -d) flatpak run …`, **it uses
  your real data dir**. The test then refuses to continue (`RSO_SMOKE_DATA_DIR`
  doesn't match), but Twitcher add-on nodes have already read your real tokens.
- The Flatpak needs filesystem access to the repo. The Flathub build ships
  with `filesystems=host`.

Manual run without the wrapper (native binary only):

```bash
D=$(mktemp -d)
RSO_SMOKE_DATA_DIR=$D XDG_DATA_HOME=$D /path/to/godot --headless --path . res://tests/smoke_all.tscn
RSO_SMOKE_DATA_DIR=$D XDG_DATA_HOME=$D /path/to/godot --headless --path . res://tests/laser_stress.tscn
```

These don't unset `NIVEK_DEVICE_TOKEN` / `NIVEK_RELAY_URL` the way the wrapper
does. The test scripts unset them in-process before the relay starts, but
prefer the wrapper.

## Running on Windows (PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File tests\run_smoke.ps1 C:\Godot\Godot_v4.6.1-stable_win64_console.exe
$env:GODOT = 'C:\Godot\Godot_v4.6.1-stable_win64_console.exe'; .\tests\run_smoke.ps1

# laser stress
$env:SMOKE_SCENE = 'res://tests/laser_stress.tscn'; $env:SMOKE_MARKER = 'STRESS_OK'
.\tests\run_smoke.ps1 C:\Godot\Godot_v4.6.1-stable_win64_console.exe
Remove-Item Env:SMOKE_SCENE, Env:SMOKE_MARKER

# isolation regression check (from a checkout without nivek_relay.env)
$env:SMOKE_SCENE = 'res://tests/isolation_check.tscn'; $env:SMOKE_MARKER = 'ISOLATION_OK'
.\tests\run_smoke.ps1 C:\Godot\Godot_v4.6.1-stable_win64_console.exe
Remove-Item Env:SMOKE_SCENE, Env:SMOKE_MARKER
```

The laser stress prerequisites are the same as on Linux: use the wrapper, and
run `isolation_check` once from a checkout without `nivek_relay.env`. The
isolation check listens on `127.0.0.1` only. Windows Firewall normally doesn't
prompt for loopback, but this hasn't been tried on Windows.

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

Kevin channel extras (`RSSettings.kevin_channel_extras`, see
[FEATURES.md](FEATURES.md#kevin-channel-extras-kevin_channel_extras-off-by-default)):
- The clean data dir starts with the extras **off**. `config_window` checks
  that default and the checkbox.
- `kevin_extras_off` then fires the gated triggers with the extras off: the
  `theyagich` `wb!` chat trigger, the rewards `Beer Nye!`, `smoke chirp` and
  `Shut down stream`, the `jumpscare` power-up, and the `test_beans` /
  `jumpscare_woman` SKUs. It checks that nothing spawns, shows, plays or
  queues an alert. It also checks that the generic `fart` reward still plays.
  The `kiwi` trigger is deliberately not fired (it would open a browser).
- `menu_beans`, `reward_beans` and `cmd_fake_beans` also run with the extras
  off. `_run` then sets `RS.settings.kevin_channel_extras = true` (in memory
  only) before `relay_extension_test_beans`. Every later check, including the
  jumpscare, `reward_smoke_chirp`, `reward_beer_nye` and
  `reward_shut_down_stream_alert`, runs with the extras on.

All 30 checks are expected to pass.

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
