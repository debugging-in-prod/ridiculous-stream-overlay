# Roadmap

Draft for Kevin's review. Milestones are in priority order. Each one should be
done before the next starts, unless Kevin decides otherwise.

## 1. Current state

- `main` runs on Godot 4.6 with GDScript only. A stock (non-.NET) Godot works.
- Windows click-through is a GDExtension in `addons/rs_clickthrough`. It loads on
  the Windows 10 test laptop, and a headless run there is clean. Transparency and
  click-through have not been checked visually yet; that check is manual.
- Linux/Wayland overlay behaviour needs the patched engine (`godot-patches/`).
  On a stock Godot it falls back to an ordinary window.
- The Twitch Extension is in draft mode.
- Extension backend (nivek): there is a Panel extension in `nivek/twitch-extension/`.
  The core-api endpoint `POST /api/overlay/extension` verifies the signed Bits
  receipt and pushes an `extension` event through the overlay relay. A test
  product (`test_beans`) is set up as "In Development". It has not gone through
  Hosted Test, Review or Release.

Known issues:

- Laser + beans hang when Rapier physics runs threaded ([issue #9](https://github.com/debugging-in-prod/ridiculous-stream-overlay/issues/9), fix in PR #10).
- The window starts at a fixed 1920x1080 with a title bar and a 1.6x UI scale in
  config mode. `RSUtl.fit_and_center_window_to_display()` is commented out in
  `RSMain.gd`.
- The Twitcher add-on settings in `rs_main.tscn` hardcode a Windows ImageMagick
  path.
- Two enabled editor add-ons are missing from the repo: `ridiculous_coding` and
  `editorscriptmanager`.
- Rapier prints warnings on Godot 4.6.3.
- `README.md` still describes the upstream Godot 4.7.2 .NET setup, which doesn't
  match `main`.

## 2. How it fits together

```
viewer clicks a redeem in the Twitch Extension (panel under the stream)
  -> peanutbudder API (nivek)
  -> websocket
  -> streamer's overlay: runs the effect locally in a transparent,
     click-through window over the main monitor
```

- Effects run on the streamer's PC. Only trigger events go over the network,
  which keeps hosting cheap.
- Current redeems: jumpscare and beans.

## 3. Milestones

### M1: Stable everywhere

Goal: the overlay runs reliably on Linux and Windows, with full click-through
over a transparent scene.

Done when:
- Every effect runs on both OSes without errors, crashes or hangs (smoke test).
- The visual checklist passes on both OSes: transparent, on top, click-through.
- The window fits the screen at boot, with no fixed size and no forced UI scale.

Work items:
- Fix the laser + beans hang ([issue #9](https://github.com/debugging-in-prod/ridiculous-stream-overlay/issues/9), fix in PR #10).
- Fit the window to the screen at boot and drop the 1.6x scale.
- Remove the hardcoded ImageMagick path.
- Resolve the two missing add-ons (vendor them or disable them in `project.godot`).
- Look into the Rapier warnings on 4.6.3.
- Update `README.md` to match `main`.

### M2: Streamer basics

Goal: give new users a reason to install it. Raid, follow and chat
notifications work out of the box.

Done when:
- A fresh install shows raid, follow and chat notifications with no
  per-event configuration.
- Each notification is covered by the smoke test and the feature checklist.

Work items:
- Wire the EventSub raid and follow events to default notification scenes.
- Add a default chat display.
- Remove channel-specific behaviour from the default path (the hardcoded OBS
  names in `NoOBSWS` and `RSCustom`).

### M3: Near-zero setup

Goal: the only required setup is the first Twitcher auth and the peanutbudder
token for the extension.

Done when:
- A new user gets to a working overlay with just those two steps.
- Everything else has a working default or is optional.

Work items:
- New config menus and changed first-run flows. This is intentional; the
  current flows can change.
- Re-enable or replace the disabled first-run welcome flow.
- Remove the need for users to bring their own Twitch client ID/secret where
  the relay can cover it.

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
- Define the product list and the SKU-to-effect mapping in the overlay.
- Take the extension through Hosted Test, Review and Release.
- Complete the pre-launch items in section 7.

### M5: Copyright-safe content

Goal: built-in interactions contain no copyrighted material. Users upload
their own sounds and visual effects.

Done when:
- Every built-in asset is original or licensed for redistribution.
- Users can add their own sounds and videos, and they play in effects.
- Users agree not to breach copyright when uploading (as Tangia does).

Proposal (not decided): uploaded content stays local on the streamer's PC, so
there is no hosting cost.

Formats (checked against the Godot 4.6 docs):
- Video: core Godot only supports Ogg Theora (`.ogv`). Convert mp4 to `.ogv`
  automatically, for example:
  `ffmpeg -i input.mp4 -q:v 6 -q:a 6 -g:v 64 output.ogv`
  The docs recommend ffmpeg with libtheora/libvorbis, at 1080p30 or below.
- Audio: Godot 4 imports WAV, Ogg Vorbis and MP3, so mp3 is fine.

Work items:
- Audit `local_res/` and replace copyrighted assets.
- Build the upload and import flow, including automatic `.ogv` conversion.
- Decide on ffmpeg bundling. It raises licensing and download-size questions.

## 4. Testing and quality

- Feature checklist: an inventory doc listing every effect, notification and
  setting, with the expected behaviour for each.
- Headless smoke tests on Linux and the Windows test laptop. They trigger each
  effect and catch errors, crashes and hangs.
- Manual visual checklist for each OS: transparency, always-on-top,
  click-through.
- Failures are filed as GitHub issues in this repo with an OS label.
  Issues are enabled on this repo.
- One fix branch and one PR per issue.

## 5. Stable releases

- Kevin streams from a stable tag.
- `main` can move ahead of the tag.
- To stream, go back to the stable tag.
- Move the tag only after a release passes the checklist on both OSes.

## 6. Next five steps

1. Fix the issue #9 hang (PR #10): move laser physics into `_physics_process` and defer
   the destroy.
2. Fit the window to the screen at boot and drop the 1.6x scale.
3. Remove the hardcoded ImageMagick path and resolve the two missing add-ons.
4. Write the feature checklist and the headless smoke test.
5. Do a visual click-through and transparency pass on the Windows laptop.

## 7. Needs Kevin's decision

- Bring in the Godot 4.7 C# version from upstream
  (`iRadEntertainment/ridiculous-stream-overlay`), or stay on GDScript.
- Pre-launch checklist: rotate the exposed Twitch client credentials before
  monetization.
- Twitch Extension review and Bits requirements: still to research.
- Where uploaded user content lives: local on the streamer's PC, or hosted.
- Whether to bundle ffmpeg.
