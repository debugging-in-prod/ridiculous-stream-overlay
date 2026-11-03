# CLAUDE.md

Ridiculous Stream: a transparent, click-through Godot overlay for Twitch streams (Linux fork).

## Engine and language
- Godot **4.6** (`config/features` in `project.godot`); LINUX.md was tested on 4.6.1. Renderer `gl_compatibility`, physics `Rapier2D` (`addons/godot-rapier2d`).
- **GDScript only.** No tracked `.cs` files; the old `RSMousePass.cs` was ported to GDScript, so a stock (non-.NET) Godot works. `Ridiculous Stream.csproj.old*` are leftovers.
- Native C++ only in `addons/rs_clickthrough/` (GDExtension, Windows click-through; Linux build is a no-op stub). Prebuilt binaries in its `bin/`; rebuild steps in its README.
- Autoload `RS` = `rs_main.tscn` (script `RSMain.gd`). Core classes in `classes/`, scenes and panels in `instances/`.

## Running
- There is no `start.sh` and no root `README.md` in this repo. Open the project in the Godot editor, or run:
  `<godot-binary> --path /path/to/repo`
- On Wayland, overlay behaviour (always-on-top, click-through) needs the patched engine: apply `godot-patches/*.patch` to `4.6.1-stable` (see `godot-patches/README.md`). On a stock Godot it falls back to an ordinary window for OBS capture.
- `project.godot` forces `display_server/driver.linuxbsd="wayland"` and `window/wayland/layer=4` (Overlay).

## nivek relay (`classes/RSNivekRelay.gd`)
- Websocket client created in code by `RSMain.start_everything()`. Sends a `hello` frame `{token, since}`, then replays events after the persisted cursor (`user://nivek_relay_cursor.txt`) and waits for `ready`.
- Event kinds: `cheer`, `power_up`, `extension`. `redemption` and legacy `command` frames are received but ignored (the cursor still advances); redemptions stay on Twitch EventSub.
- Config: `cp nivek_relay.env.example nivek_relay.env` and fill in `NIVEK_DEVICE_TOKEN` (gitignored, never commit). Optional `NIVEK_RELAY_URL`, which defaults to `wss://peanutbudderbot.com/api/overlay/connect`.
- Token lookup order: OS env var, then `res://nivek_relay.env`, then `RS.settings.nivek_device_token` (set from the config window, `instances/settings/win_config.gd`).
- If no token is set, the relay is disabled and `RS.cheer_source()` falls back to `RSTwitcher` for cheers.

## Twitch (`classes/RSTwitcher.gd`, `addons/twitcher`)
- Uses the twitcher addon: `TwitchEventsub`, `TwitchChat`, `TwitchIRC`. It connects on start if `settings.auto_connect` is set.
- `client_id`/`client_secret` come from `RSSettings` (user data dir), not the scene. The credentials baked into `rs_main.tscn` can't be decrypted on other machines. That failure is silent: you get "Connected to Twitch!" and then a reconnect loop on EventSub 4003.
- OAuth token files `twitch_oauth_setting.tres` and `twitch_oauth_token.tres` are gitignored.

## Effects
- Reward, command and power-up dispatch is in `classes/RSCustom.gd`: `on_channel_points_redeemed`, `on_power_up`, `on_extension_interaction`.
- Jumpscare: `RSCustom.jumpscare_woman()`, triggered by extension SKU `jumpscare_woman`. Assets are `local_res/scary-face-scaled.jpg` and `local_res/scream-clipped.ogg`. Nodes live under `JumpscareLayer` (CanvasLayer 128) in `rs_main.tscn`.
- Physics objects are in `instances/objects/` (grenade, laser emitter, etc.) and `instances/physics_scene.gd`. Shaders are in `shaders/`.

## Gotchas (from LINUX.md)
- Stock Godot's Wayland backend silently ignores passthrough, position and always-on-top, but `get_flag()`/`position` still read back the value you set.
- Wayland click-through uses input regions (`window_set_mouse_passthrough_regions`, patched engine only). `%split_chat` is in the `UI` group on purpose, so be careful with it.
- Layer-shell `Window.position` is output-relative. `RSDisplay` and `RSUtl.fit_and_center_window_to_display()` use `(0,0)` on the patched engine.
- `RSDisplay.supports_desktop_overlay()` detects the patched engine via `ClassDB.class_has_integer_constant(...)`. Keep it that way so the project still runs on a stock Godot.
- User data dir differs between a native build (`~/.local/share/godot/app_userdata/Ridiculous Stream/`) and the Flatpak. `settings.tres` holds the OBS WebSocket password and is created world-readable, so `chmod 600` it.
- `NoOBSWS` and `RSCustom` hardcode OBS source and scene names (`Mic/Aux`, `Brave`, `main_desk`/`Blur`, `Overlay Stream`/`BRB_text`). Missing names only log a warning.
- GNOME Wayland has no layer-shell support. A strip under the desktop panel isn't covered.
