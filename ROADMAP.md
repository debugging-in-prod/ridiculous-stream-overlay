# Roadmap

Milestones are in priority order. Each one should be done before the next
starts, unless Kevin decides otherwise. Checked against `main` @ e069f57.

## 1. Decisions

- **Engine and language: stay on our Godot 4.6 GDScript fork.** We won't bring
  in the upstream Godot 4.7 C# version
  (`iRadEntertainment/ridiculous-stream-overlay`). Upstream is a reference
  only. Port individual ideas or fixes from it as GDScript where they help.
- **User-uploaded content stays on the user's PC.** Sounds and videos that
  streamers add are stored and played locally. Nothing is uploaded or hosted,
  so there is no hosting cost and no content moderation on our side.
- **Automatic ffmpeg conversion (mp4 → `.ogv`) is low priority** and comes late
  in M5, after the local upload/import flow works with formats Godot already
  plays. Whether to bundle ffmpeg is **still undecided** (licensing and
  download size).

## 2. Current state

- `main` runs on Godot 4.6 with GDScript only. A stock (non-.NET) Godot works.
- Windows click-through is a GDExtension in `addons/rs_clickthrough`. It loads
  on the Windows 10 test laptop, and a headless run there is clean.
  Transparency and click-through have not been checked visually yet; that check
  is manual.
- Linux/Wayland overlay behaviour needs the patched engine (`godot-patches/`).
  On a stock Godot it falls back to an ordinary window.
- The app boots into config mode (an ordinary window showing the config
  window). Closing the config window switches to the transparent overlay.
- The OBS module (`NoOBSWS`) and the first-run welcome flow are disabled in
  code (`RSMain.start_everything`, `RSMain.welcome_panel_check`).
- Twitch Extension and nivek backend (tracked outside this repo): a Panel
  extension in `nivek/twitch-extension/`, in draft mode. The core-api endpoint
  `POST /api/overlay/extension` verifies the signed Bits receipt and pushes an
  `extension` event through the overlay relay. A test product (`test_beans`)
  is "In Development". It has not gone through Hosted Test, Review or Release.

Shipped (merged to `main`):

- Laser + beans hang with threaded Rapier physics: laser queries now run in
  `_physics_process` (issue #9, PR #10). Regression test:
  `tests/laser_stress.tscn`.
- Hardcoded Windows ImageMagick path removed from `rs_main.tscn`, and the two
  missing editor add-ons (`editorscriptmanager`, `ridiculous_coding`) dropped
  from the enabled list in `project.godot` (PR #12).
- `window/stretch/scale=1.6` removed from `project.godot`, and
  `RSUtl.fit_and_center_window_to_display()` is called at boot for the main and
  config windows (PR #11). See the window-size issue below: this is not yet
  confirmed as a fix.
- Feature inventory (`docs/FEATURES.md`), manual by-eye checklist, and
  headless smoke test (`tests/smoke_all.tscn`, wrappers `tests/run_smoke.sh` /
  `tests/run_smoke.ps1`, see `docs/TESTING.md`) (PR #13).
- Dead relay-command code removed (PR #14).
- `!d` / `!discord` sfx fixed (issue #15, PR #16).
- Follow, raid and sub banners with sound, capped at 4 on screen with one sfx
  per burst, behind the "Follow / raid / sub alerts" toggle (default on)
  (PR #17).
- Kevin's channel-specific triggers gated by `RSSettings.kevin_channel_extras`
  (default off) and the "Kevin channel extras" checkbox (PR #18).
- `README.md` rewritten for the GDScript fork (this PR).

Known issues:

- **Oversized startup window: not confirmed fixed.** The fit helper exists and
  runs at boot, but `project.godot` still sets a 1920x1080 viewport, so the
  window is created at that size and only shrunk afterwards. PR #11 was checked
  on Linux/X11 only. Nobody has confirmed by eye that the boot and config
  windows fit on the small Windows laptop where the problem was reported, or
  that the config UI is readable at 1x. Keep this open until the manual
  checklist passes there.
- Transparency, always-on-top and click-through have not passed the manual
  checklist on Windows.
- X11 click-through: the Linux `rs_clickthrough` build is a no-op stub, so it is
  unknown and likely broken.
- Rapier prints warnings on Godot 4.6.3. Not investigated.
- Some generic-path behaviour is still channel-specific: hardcoded OBS source
  and scene names in `NoOBSWS` and `RSCustom` (only active once the OBS module
  is re-enabled), and ungated chat commands such as `!discord`, `!mika`,
  `!scawy`, `!irad`, `!pandano`, `!toggle_music`.
- A few features are Windows-only (Brave history reward, the floating-menu
  "test" button, which shells out to PowerShell).
- `rs_main.tscn` still contains the original author's Twitch application
  credentials. They are not used (credentials come from `RSSettings`), but they
  are exposed in the repo.

## 3. How it fits together

```
viewer clicks a redeem in the Twitch Extension (panel under the stream)
  -> peanutbudder API (nivek)
  -> websocket (nivek relay, classes/RSNivekRelay.gd)
  -> streamer's overlay: runs the effect locally in a transparent,
     click-through window over the main monitor
```

- Effects run on the streamer's PC. Only trigger events go over the network,
  which keeps hosting cheap.
- Current extension redeems: jumpscare and beans (both behind
  `kevin_channel_extras` today).

## 4. Milestones

### M1: Stable everywhere

Goal: the overlay runs reliably on Linux and Windows, with full click-through
over a transparent scene.

Done when:
- Every effect runs on both OSes without errors, crashes or hangs (smoke test).
- The manual checklist passes on both OSes: transparent, on top,
  click-through, window fit.
- The window fits the screen at boot on the Windows laptop, confirmed by eye.

Done so far: laser hang (PR #10), ImageMagick path and missing add-ons
(PR #12), fit helper wired in and 1.6x scale dropped (PR #11), smoke test
(PR #13), README (this PR).

Remaining work items:
- Run the smoke test and laser stress test on the Windows laptop.
- Do the manual checklist on Windows, including window fit. If the window
  still overflows, fix the boot size itself (for example a smaller default
  viewport, or sizing before the window is shown) rather than relying only on
  shrinking after creation.
- Look into the Rapier warnings on 4.6.3.

### M1.5: Consistency cleanup (small, before M2)

Goal: remove the leftovers that make the code harder to change, before adding
features. This is a tidy-up, not a rewrite: each item is a small, separate PR,
covered by the smoke test, with no behaviour change unless stated.

Done so far: removed the unused chat-format helper (`RSPnlChat.format_msg`,
`commands_string_format`) and the commented-out TTS command registrations
(this PR). `RSCustom.tts()` is still used by `yag_welcome_back`, and
`parse_tts_command` is kept.

Candidates (pick what is cheap; skip anything that grows):
- Rename the C#-style `RSMousePass.SetClickThrough` to `set_click_through`
  (the only PascalCase method left from the C# port).
- Resolve the two chat limits: `RSSettings.max_messages_in_chat` (100) is
  unused, while `pnl_chat.max_display_messages` (200) is what applies. It is
  an exported setting, so existing `settings.tres` files contain it. Wire it
  up or remove it on purpose in its own PR, not as part of a dead-code
  removal.
- Remove or wire up dead code: long commented-out blocks whose feature is not
  coming back.
- Fix `config/features` in `project.godot`: it lists "Forward Plus", but the
  renderer is `gl_compatibility`.
- Fix obvious typos in user-visible or log text (`RIDICULOS STREAM STARTED`).
  Reward titles such as `Granades!` must match the Twitch reward, so leave
  those unless the reward is renamed too.
- Decide whether `test/` (manual experiments) and `tests/` (automated) stay
  separate, and say so in `docs/TESTING.md`.

### M2: Streamer basics

Goal: give new users a reason to install it. Raid, follow and chat
notifications work out of the box.

Done when:
- A fresh install shows raid, follow and chat notifications with no
  per-event configuration.
- Each notification is covered by the smoke test and the feature checklist.

Done so far: follow/raid/sub banners (PR #17), chat notification burst (smoke
check `chat_notification`), Kevin-specific triggers gated off by default
(PR #18).

Remaining work items:
- Decide whether the chat panel (`instances/pnl_chat.gd`) should be visible by
  default, and check how it looks on a real stream.
- Check the banners on a real stream (font size, colours, stacking). The smoke
  test checks nodes only.
- Gate or make configurable the remaining channel-specific chat commands and
  the hardcoded OBS names before the OBS module is re-enabled.

### M3: Near-zero setup

Goal: the only required setup is the first Twitcher auth and the peanutbudder
token for the extension.

Done when:
- A new user gets to a working overlay with just those two steps.
- Everything else has a working default or is optional.

Work items:
- New config menus and changed first-run flows. This is intentional; the
  current flows can change.
- Re-enable or replace the disabled first-run welcome flow. Today the Twitch
  client ID/secret can only be entered through it, so a new user has to edit
  `settings.tres` by hand.
- Remove the need for users to bring their own Twitch client ID/secret where
  the relay can cover it.
- Agent-friendly setup, so Grok Bot, Claude Code, Gemini and other agents can
  set up the overlay and peanutbudder:
  - An `AGENTS.md`/`SETUP.md` written for agents: install Godot, the Twitcher
    first auth, where the peanutbudder device token goes, running the
    stress/smoke tests, and what "working" looks like.
  - A one-command self-check for install, token, relay connection and Twitch
    connection, printing plain pass/fail lines.
  - Later: an MCP server or small API on the peanutbudder side to create the
    device token, list redeems and trigger a test effect (also useful for
    test automation).
  - Limits: the streamer does the first Twitch sign-in and any consent screen
    in a browser. The device token lives in an env var or the OS keychain,
    never in a repo file or an agent chat.

### M4: Premium interactions (monetization)

Goal: viewers pay Bits through the Twitch Extension for interactions.

Done when:
- Bits products exist for the premium interactions, at about 30-50 Bits each
  (roughly $0.30-$0.50).
- The extension has passed Twitch review and been released.
- A paid interaction runs exactly once per purchase (no double execution).

Notes:
- Twitch splits Bits revenue 80% to the broadcaster and 20% to the extension
  developer. Twitch sets the split.

Work items:
- Define the product list and the SKU-to-effect mapping in the overlay. Move
  the generic SKUs out from behind `kevin_channel_extras`.
- Take the extension through Hosted Test, Review and Release.
- Complete the pre-launch items in section 7.

### M5: Copyright-safe content

Goal: built-in interactions contain no copyrighted material. Users add their
own sounds and visual effects.

Done when:
- Every built-in asset is original or licensed for redistribution.
- Users can add their own sounds and videos, and they play in effects.
- Users agree not to breach copyright when adding content (as Tangia does).

Decided: added content stays local on the streamer's PC (section 1).

Formats (checked against the Godot 4.6 docs):
- Video: core Godot only supports Ogg Theora (`.ogv`).
- Audio: Godot 4 imports WAV, Ogg Vorbis and MP3, so mp3 is fine.

Work items, in order:
1. Audit `local_res/` and replace copyrighted assets.
2. Build the local add/import flow for WAV, Ogg, MP3 and `.ogv`. Tell the user
   how to convert other video formats themselves, for example:
   `ffmpeg -i input.mp4 -q:v 6 -q:a 6 -g:v 64 output.ogv`
   (the Godot docs recommend ffmpeg with libtheora/libvorbis, at 1080p30 or
   below).
3. Late, low priority: automatic mp4 → `.ogv` conversion with ffmpeg. Decide
   on bundling first (section 7).

## 5. Testing and quality

- Feature inventory and manual by-eye checklist: `docs/FEATURES.md`.
- Headless smoke test and laser stress test: `docs/TESTING.md`. Run them on
  Linux and the Windows test laptop.
- Failures are filed as GitHub issues in this repo with an OS label.
- One fix branch and one PR per issue.

## 6. Stable releases

- Kevin streams from a stable tag.
- `main` can move ahead of the tag.
- To stream, go back to the stable tag.
- Move the tag only after a release passes the checklist on both OSes.

## 7. Next five steps

1. Run the smoke and laser stress tests on the Windows laptop.
2. Do the manual checklist on the Windows laptop, including window fit at
   boot. Fix the boot size if it still overflows.
3. Look into the Rapier warnings on 4.6.3.
4. Do the M1.5 consistency cleanup as small PRs.
5. Start M2's remaining items (chat panel default, gating the remaining
   channel-specific commands).

## 8. Needs Kevin's decision

- Pre-launch: rotate the Twitch client credentials exposed in `rs_main.tscn`
  before monetization, and remove them from the scene.
- Twitch Extension review and Bits requirements: still to research.
- Whether to bundle ffmpeg (only needed once automatic conversion is built).
