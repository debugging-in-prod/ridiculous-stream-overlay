# Ridiculous Stream

A transparent, click-through Godot overlay for Twitch streams, with Twitch chat
and channel-point actions, physics-based effects, follow/raid/sub alerts, user
management and session summaries. It is meant to run on Windows and Linux.

This is a GDScript fork of
[iRadEntertainment/ridiculous-stream-overlay](https://github.com/iRadEntertainment/ridiculous-stream-overlay).
Upstream has moved to Godot 4.7 with C#. This fork stays on Godot 4.6 and
GDScript; see [ROADMAP.md](ROADMAP.md).

Channel-specific behaviour of the author's channel is off by default (see
[Kevin channel extras](docs/FEATURES.md#kevin-channel-extras-kevin_channel_extras-off-by-default)).

## Development requirements

- Godot **4.6**. A stock (non-.NET) build works; no .NET SDK is needed.
- Linux/Wayland: a true overlay (always-on-top, click-through) needs the
  patched engine. See [LINUX.md](LINUX.md) and
  [godot-patches/README.md](godot-patches/README.md). On a stock Godot it runs
  as an ordinary window.
- The bundled add-ons and native libraries, including Rapier2D and the
  `rs_clickthrough` GDExtension.
- A Twitch account and a Twitch application (client ID and secret) for Twitch
  features.
- Optional: a nivek relay device token for Bits/extension events.

## Opening and running the project

1. Clone the repository and open `project.godot` in the Godot 4.6 editor, or
   run `<godot-binary> --path <repo>`. Let the first import finish.
2. Enabled editor plugins (**Project Settings > Plugins**) are `kanban_tasks`,
   `script-ide` and `twitcher`, all bundled. The upstream local tools
   `editorscriptmanager` and `ridiculous_coding` are not enabled and not in
   the repo.
3. Press **F5**. The `RS` autoload loads `rs_main.tscn`; the configured main
   scene is `instances/empty.tscn`. The app opens in config mode: an ordinary
   window showing the config window. Close the config window to switch to the
   transparent overlay. The floating menu's settings button brings the config
   window back.

## Twitch setup

Twitch credentials come from `settings.tres` in the data directory (see below),
not from `rs_main.tscn`. The secret baked into that scene is encrypted per
install and cannot be decrypted on your machine; if it is used, Twitch sign-in
looks successful but EventSub keeps reconnecting with code 4003.

The first-run welcome flow, which used to collect these values, is disabled.
Until it is replaced, set them by hand with the app closed: in
`<data_dir>/settings.tres` under `[resource]`, set `broadcaster_id`,
`broadcaster_name`, `client_id`, `client_secret` and `redirect_url` (it must
match the OAuth redirect URL registered on your Twitch application;
`redirect_port` defaults to 7170). Then start the app and use **Connect with
Twitcher** in the config window.

Keep credentials and tokens out of commits and builds. The OAuth resource files
`twitch_oauth_setting.tres` and `twitch_oauth_token.tres` are gitignored.

## nivek relay (optional)

The relay delivers cheers, power-ups and Twitch Extension interactions over a
websocket and replays missed events. To enable it:

```bash
cp nivek_relay.env.example nivek_relay.env   # gitignored; paste the device token
```

The token is looked up in this order: the `NIVEK_DEVICE_TOKEN` environment
variable, `nivek_relay.env`, then the device token field in the config window.
Without a token the relay is disabled and cheers come from Twitch EventSub.

## OBS

The OBS WebSocket module (`lib/no-obs-ws/`) is currently disabled in code
(`RSMain.start_everything`). OBS buttons and rewards only log a warning. Its
input, scene and filter names are hardcoded to the author's setup in
`lib/no-obs-ws/NoOBSWS.gd` and `classes/RSCustom.gd`.

## Settings and local data

`user://settings.ini` selects the application's data directory. It defaults to
Godot's user-data directory (for example
`~/.local/share/godot/app_userdata/Ridiculous Stream` on Linux,
`%APPDATA%\Godot\app_userdata\Ridiculous Stream` on Windows). That directory
holds `settings.tres`, user records, summaries, caches and custom media
folders. Back it up before experimenting. `settings.tres` can contain
credentials, so never commit or share it.

Media you add (sounds, videos, custom beans) stays on your PC. Godot plays
WAV, Ogg Vorbis and MP3 audio, and Ogg Theora (`.ogv`) video. Convert other
video formats yourself, for example
`ffmpeg -i input.mp4 -q:v 6 -q:a 6 -g:v 64 output.ogv`.

Git ignore rules do not control which files Godot includes in an export.

## Platform status

| | Windows | Linux |
| --- | --- | --- |
| Click-through | `classes/RSMousePass.gd` + the `rs_clickthrough` GDExtension (`addons/rs_clickthrough/bin/*.dll`) | Wayland (patched engine): input regions. X11: the GDExtension's Linux build is a stub, so likely broken. |
| Always-on-top | `Window.always_on_top` | Patched engine only (layer-shell) |
| Transparency | Re-asserted on resize/focus/startup (`classes/RSDisplay.gd`) | Needs a compositor |

The headless smoke test has wrappers for both. The manual by-eye checklist
(transparency, always-on-top, click-through, window fit) has not yet passed on
Windows. macOS is untested. A few features are Windows-only (the Brave history
reward and the floating-menu test button, which uses PowerShell).

## Testing

- Feature inventory and manual checklist: [docs/FEATURES.md](docs/FEATURES.md).
- Headless smoke test and laser stress test: [docs/TESTING.md](docs/TESTING.md).
  Use the wrappers (`tests/run_smoke.sh`, `tests/run_smoke.ps1`); they use a
  throwaway data directory so your real settings and relay cursor are not
  touched.

`test/` holds older manual experiments, not automated tests.

## Code and dependencies

| Location | Purpose |
| --- | --- |
| `RSMain.gd`, `rs_main.tscn` | Application startup, global services and UI |
| `classes/` | Application behaviour, settings and data models |
| `instances/` | Feature scenes and their scripts |
| `lib/no-obs-ws/` | OBS WebSocket integration with application-specific actions |
| `lib/games_info/` | Steam and itch.io information |
| `lib/polygon2d-fracture/` | Polygon fracture support |
| `addons/twitcher/` | Bundled Twitcher 2.2.2 and its dependencies |
| `addons/godot-rapier2d/` | Native Rapier2D physics extension |
| `addons/rs_clickthrough/` | Windows click-through GDExtension (C++; see its README to rebuild) |
| `godot-patches/` | Engine patches for the Linux/Wayland overlay |
| `local_res/`, `ui/`, `shaders/` | Media, UI assets and visual effects |
| `tests/` | Automated headless smoke and stress tests |
| `test/`, `tools/`, `example/` | Manual experiments, developer tools and examples |

Generated Twitch API files can be overwritten by regeneration; consult
`addons/twitcher/generated/README.md` before changing them.

## License

Project code is covered by the root [MIT license](LICENSE). Bundled dependencies
include their own license files. Review third-party media and font licenses
separately before redistributing assets.
