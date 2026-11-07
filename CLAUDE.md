# CLAUDE.md

Ridiculous Stream: a transparent, click-through Godot overlay for Twitch streams. It has to work on **Windows and Linux** alike.

## Engine and language
- Godot **4.6** (`config/features` in `project.godot`), Compatibility renderer (`gl_compatibility`). Physics `Rapier2D` (`addons/godot-rapier2d`).
- **GDScript only.** There is no C# on main, so a stock (non-.NET) Godot works. The upstream project, https://github.com/iRadEntertainment/ridiculous-stream-overlay, has moved to Godot 4.7 + C#. **Decided: we stay on our Godot 4.6 GDScript fork.** Treat upstream as a reference only; port ideas as GDScript, never bring C# back.
- Native C++ only in `addons/rs_clickthrough/` (GDExtension for Windows click-through; the Linux build is a no-op stub). Rebuild steps are in its README.
- Autoload `RS` = `rs_main.tscn` (script `RSMain.gd`). Core classes are in `classes/`, scenes and panels in `instances/`, OBS WebSocket code in `lib/no-obs-ws/`.

## Running
- Open `project.godot` in the Godot editor, run `<godot-binary> --path <repo>`, or use an exported build.
- `start.sh` is a gitignored local Linux helper for an experimental engine build. It is not in the repo, so don't reference it or rely on it.
- For setup (Twitch, nivek relay, OBS, user data) see `README.md`. Plans, decisions and known issues are in `ROADMAP.md`.
- Enabled editor plugins: `kanban_tasks`, `script-ide`, `twitcher` (all bundled). `editorscriptmanager` and `ridiculous_coding` are gitignored upstream tools and are no longer enabled; don't re-add them to `project.godot`.
- The app boots into config mode; closing the config window enters overlay mode (`RSMain.enter_config_mode` / `enter_overlay_mode`). The first-run welcome flow and the OBS module are disabled in code.
- Startup window size: `project.godot` still sets 1920x1080 and `RSUtl.fit_and_center_window_to_display()` shrinks it at boot. That fix is not confirmed on the small Windows laptop where it overflowed, so don't treat the oversized-window issue as resolved.
- Tests: `docs/TESTING.md` (headless smoke test `tests/smoke_all.tscn`, laser stress test; always use the `tests/run_smoke.*` wrappers so the real data dir isn't touched). Feature inventory and manual checklist: `docs/FEATURES.md`. `test/` is old manual experiments.
- Linux/Wayland details, including the patched-engine overlay, are in `LINUX.md` and `godot-patches/README.md`.

## nivek relay (`classes/RSNivekRelay.gd`)
- Websocket client created by `RSMain.start_everything()`. It replays events after the cursor in `user://nivek_relay_cursor.txt`.
- Config: `cp nivek_relay.env.example nivek_relay.env` (gitignored, never commit). Token lookup order: OS env, `res://nivek_relay.env`, then `RS.settings`. With no token the relay is disabled and `RS.cheer_source()` falls back to Twitch.

## Twitch (`classes/RSTwitcher.gd`, `addons/twitcher`)
- Credentials come from `RSSettings` (user data dir), not the scene. The secret baked into `rs_main.tscn` is encrypted per install and can't be decrypted elsewhere. That failure is silent: EventSub reconnects in a loop with code 4003 (see comments in `RSTwitcher.gd`).
- OAuth files `twitch_oauth_setting.tres` and `twitch_oauth_token.tres` are gitignored.

## Effects
- Dispatch is in `classes/RSCustom.gd`: `on_channel_points_redeemed`, `on_power_up`, `on_extension_interaction`.
- Kevin's channel-specific triggers (chat words, first-session-message handler, channel-specific reward titles in `_on_kevin_channel_reward`, power-up titles, extension SKUs) are gated by `RSSettings.kevin_channel_extras`, **default off**. Kevin turns it on with the "Kevin channel extras" checkbox in the config window, or `kevin_channel_extras = true` in `settings.tres`. Put new channel-specific triggers behind this gate. Details: `docs/FEATURES.md`.
- Example: `RSCustom.jumpscare_woman()` (extension SKU `jumpscare_woman`) uses `local_res/scary-face-scaled.jpg` and `local_res/scream-clipped.ogg`. Media lives in `local_res/`.
- Physics objects are in `instances/objects/` and `instances/physics_scene.gd`. Shaders are in `shaders/`.
- User-added content (sounds, videos, custom beans) **stays on the user's PC**; never design an upload or hosting path for it. Godot plays WAV/Ogg/MP3 audio and only Ogg Theora (`.ogv`) video. Automatic ffmpeg conversion is a low-priority late addition, and bundling ffmpeg is undecided.

## Windows gotchas
- `addons/rs_clickthrough/bin/*.dll` / `*.so` **must be committed**, or exports won't include them. Without the DLL, `RSMousePass` falls back to `FLAG_MOUSE_PASSTHROUGH`, which doesn't pass clicks through on Windows.
- Never reference Wayland-only `DisplayServer` methods directly (e.g. `window_set_mouse_passthrough_regions`). Stock templates lack them, and GDScript rejects the reference at parse time, which breaks the Windows build. Guard them with `has_method` + `call`, as `classes/RSMousePass.gd` does.
- DWM can drop the overlay's per-pixel alpha after a fullscreen app, a resolution change or sleep/wake, and it also leaves a black bar at startup. `classes/RSDisplay.gd` works around this by re-asserting `FLAG_TRANSPARENT` on resize, on focus, and after startup. Keep that in place.
- Keep `RSDisplay.supports_desktop_overlay()` detecting the patched engine via `ClassDB.class_has_integer_constant(...)`, so stock Godot (Windows included) still runs.

## Other gotchas
- `lib/no-obs-ws/NoOBSWS.gd` and `RSCustom.gd` hardcode OBS source and scene names. Missing names only log a warning. The OBS module is currently disabled (`RSMain.start_everything`).
- `settings.tres` in the user data dir can hold credentials. Never commit or print it.
