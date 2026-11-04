# Feature inventory

All user-visible features of the overlay, taken from the code on branch
`test/feature-checklist-smoke` (based on `main` @ 9a8cf29). "unknown" means
the code doesn't settle the question.

Columns:
- **Trigger**: how a viewer or the streamer fires it.
- **Entry point**: `file:function`.
- **Correct run**: what you should see or hear.
- **Headless**: whether `tests/smoke_all.gd` can check it. A smoke line name
  means it's covered. "no" gives the reason.
- **Platform**: Linux/Windows differences. "same" means plain Godot nodes with
  no OS-specific code.

How events reach `RSCustom`:
- Twitch EventSub → `RSTwitcher.on_event` → signals `followed`,
  `channel_points_redeemed`, `raided`, `cheered`, `subscribed`
  (`classes/RSTwitcher.gd`).
- Chat commands are registered in `RSCustom.add_commands`, but only after
  `RSTwitcher.connected_to_twitch`. They go through the twitcher addon's
  `TwitchCommand`.
- The nivek relay (`classes/RSNivekRelay.gd:_handle_event`) emits `cheered`,
  `power_up_redeemed` and `extension_interaction`.
- The floating menu calls handlers in `instances/btn_floating_menu.gd`.

---

## 1. Floating menu (`instances/btn_floating_menu.tscn`, script `btn_floating_menu.gd`)

The round menu button opens sub-menus (`RSSubMenuButton`). You can drag it. On
release it slides to the nearest window edge (`calculate_anchored_pos`,
`_process`). It's hidden in config mode and shown in overlay mode.

| Button (node) | Entry point | Correct run | Headless | Platform |
|---|---|---|---|---|
| Physics → beans (`btn_beans`) | `btn_floating_menu.gd:_on_btn_beans_pressed` → `RSCustom.beans("")` | Can sprites (or a random known user's custom beans) drop from the centre with can sfx. The body count on the nuke button goes up. | yes, `menu_beans` | same |
| Physics → laser (`btn_laser`) | `_on_btn_laser_pressed` → `RSCustom.laser` → `RSPhysicsScene.add_laser` | A laser emitter sits at the centre and sweeps ±~63° five times over ~20 s. Bodies it hits shatter (`destroy`) or get pushed. The counter label rises. The emitter frees itself 1.5 s after returning to 0°. Holding left mouse pauses firing (`laser_emitter.gd:_physics_process`). | yes, `menu_laser` (also `tests/laser_stress.gd`) | same. Holding the left mouse only registers when the window gets mouse input. |
| Physics → nuke (`btn_nuke`) | `_on_btn_nuke_pressed` → `RSPhysicsScene.nuke` | Alert sfx (~1.3 s), then boom. A fire shader rises along the bottom for ~2.5 s. All bodies and the laser are removed. Re-trigger is blocked for ~10 s. | yes, `menu_nuke` | same |
| Physics → zero-G (`btn_zerog`) | `_on_btn_zerog_pressed` → `RSCustom.zero_g()` | Gravity drops to 0 and bodies get shaken. After 30 s (default) gravity tweens back over 5 s. | yes, `cmd_zero_g` + `cmd_zero_g_restore` (test uses `!zeroG 1` so it's short) | same |
| Physics → names (`btn_names`) | `_on_btn_names_pressed` → `RSCustom.destructibles_names("", 5, 48)` | 5 copies of a random known user's display name fall as physics text, in their chat colour (default green). Does nothing if there are no known users or "Names on screen" is off. | partial: `names_disabled_by_config` checks the toggle only. The text texture is read back from a SubViewport (`label_renderer.gd`), and the headless dummy renderer returns null ("Parameter t is null"). | same |
| Physics → grenade (`btn_granade`) | `_on_btn_granade_pressed` → `RSPhysicsScene.spawn_grenade` | A grenade spawns (max 69 alive). After a 4 s fuse it explodes, destroys bodies in range and pushes others. | yes, `menu_grenade` | same |
| Body count label (`lb_count`) | `update_obj_count` on `RSPhysicsScene.count_updated` | Shows the live body count. Hidden at 0. | indirectly (count used by every physics test) | same |
| OBS → cig break (`btn_cig`) | `_on_btn_cig_pressed` → `RSCustom.suggest_no_ads` + `toggle_cig_overlay` | Toggles OBS item `BRB_text` in scene `Overlay Stream`. May post a "don't watch the ads" chat message naming a live known streamer. | no: needs OBS WebSocket and Twitch. The noOBS module is disabled in `RSMain.start_everything` (start commented out), so today it only logs `WebSocket not initialized`. | same |
| OBS → mic (`btn_mic`) | `_on_btn_mic_pressed` → `NoOBSWS.toggle_mic_mute` | Toggles mute on OBS input `Mic/Aux`. The mic indicator turns salmon/green. | no: OBS (module disabled, see above) | same |
| OBS → browser sound (`btn_brave_sound`) | `_on_btn_brave_sound_pressed` → `NoOBSWS.toggle_brave_mute` | Toggles mute on OBS input `Brave` | no: OBS | same |
| OBS → pixelate (`btn_pixelate`) | `_on_btn_pixelate_pressed` | Toggles OBS filter `Blur` on source `main_desk` | no: OBS | same |
| Chat (`btn_chat`) | `_on_btn_chat_pressed` | Shows/hides the chat panel | yes, `menu_panel_toggles` | same |
| User list (`btn_user_list`) | `_on_btn_user_list_pressed` | Opens settings panel tab 1 and toggles it | yes, `menu_panel_toggles` | same |
| Settings (`btn_settings_v2`) | `_on_btn_settings_v2_pressed` → `RSMain.enter_config_mode` | Overlay goes away (menu hidden, full passthrough) and the config window appears | yes, `overlay_config_switch` | Wayland: see config mode in §5 |
| Settings → display → maximize (`btn_maximize`) | `_on_btn_maximize_pressed` → `RSDisplay.set_borderless_maximized` | Toggles a borderless window sized to the overlay output, at (0,0) | no: needs a real display server | Wayland layer-shell: position is output-relative (0,0). Windows: unknown beyond the code path. |
| Settings → display → debug (`btn_debug`) | `_on_btn_debug_pressed` | Toggles the debug view overlay | yes, `menu_panel_toggles` | same |
| Settings → panels (`btn_panels`) | `generate_panels_buttons` | One button per panel in `RS.pnls_to_start` (chat, settings, summary). Each toggles its panel. | no (not separately; same toggle as above) | same |
| Settings → test (`btn_test`) | `_on_btn_test_pressed` | Dev tool: prints each user file's creation time | no: runs `powershell` | **Windows only** (shells out to PowerShell with `\` paths) |
| End → summary (`btn_summary`) | `_on_btn_summary_pressed` | Toggles the end-of-stream summary panel | yes, `menu_panel_toggles` | same |
| End → new summary (`btn_summary_start`) | `_on_btn_summary_start_pressed` → `RSSummaryMng.start_new_summary` | Archives the current summary and starts a new one stamped with the current time | yes, `menu_summary_start` | same |
| End → close (`btn_close`) | `_on_btn_close_pressed` → `RSMain.quit` | Saves settings, users and summary, then exits | no: it quits the process. Not worth testing headless. | same |
| OBS indicators (`indicators`) | `start_indicators` on `NoOBSWS.scenes_updated` | Four ring icons show mic/browser/stream/pixelate state | no: OBS | same |

## 2. Effects triggered by Twitch (`classes/RSCustom.gd`)

### 2a. Channel-point rewards: `RSCustom.on_channel_points_redeemed` (matched on `reward_title`)

Trigger: EventSub `channel.channel_points_custom_reward_redemption.add` →
`RSTwitcher.on_event`. Every reward first looks up the redeemer with
`RSUserMng.get_any_user_from_username`. For users who aren't known, that's a
Twitch API call.

| Reward title | Entry point | Correct run | Headless | Platform |
|---|---|---|---|---|
| `beans` | `RSCustom.beans` | Redeemer's custom beans, or cans | yes, `reward_beans` | same |
| `open useless website` | `open_useless_website` | Opens https://theuselessweb.com/ in the default browser | no: opens a browser | same (`OS.shell_open`) |
| `open browser history` | `open_browser_history` | Launches Brave at `brave://history` | no: external program | **Windows only**: hardcoded `C:/Program Files/BraveSoftware/...` |
| `remove the cig break overlay` | `toggle_cig_overlay` | Toggles OBS `BRB_text` | no: OBS | same |
| `Give advice` | `RSVetting.custom_rewards_vetting(give_advice)` | After vetting, appends to `<data_dir>/advice_collection.json` | no: the vetting UI needs a human decision. Unknown users may queue a notification. | same |
| `Get advice` | `get_advice` | Posts a random saved advice line to chat | no: sends Twitch chat | same |
| `Shut down stream` | `alert_on_stop_streaming` → `RSAlertOverlay.initialize_stop_streaming` | An alert bar counts down 10 s, then calls OBS `StopStream`. The bar's close button cancels it. | yes, `reward_shut_down_stream_alert` (bar shown, then cancelled before the OBS call) | same |
| `Raid kani_dev` | `raid_kani` → `RSAlertOverlay.initialize_raid` | An alert bar counts down, then starts a Twitch raid | no: Twitch API | same |
| `Force raid a random streamer` | `RSAlertOverlay.wheel_of_random_raid` | Currently only posts "Raid random wheel is broken!" to chat (early `return`) | no: sends chat | same |
| `Impersonate iRadDev` | vetting → `impersonate_iRad` | Sends the message as the named known user | no: Twitch | same |
| `Change Stream Title` | vetting → `change_stream_title` | Sets the stream title to `<input> - <user>` | no: Twitch API | same |
| `Do it!` | `play_doit` | Restarts OBS media `do_it_<1-3>.mp4` | no: OBS | same |
| `Toggle mute mic on stream` | inline | Toggles OBS `Mic/Aux`. Posts a teasing chat line if the redeemer is `trickylady`. | no: OBS | same |
| `Granades!` | `RSPhysicsScene.spawn_grenade` | One grenade | yes, `reward_grenade` | same |
| `Change streamer colour` | `change_streamer_colour` | Sets OBS filter `Colour Correction` on `Cam-cutout`/`Cam-composite` | no: OBS | same |
| `Beer Nye!` | `beer_nye_the_science_guy` | Shows and plays `res://local_res/beer-nye.ogv`, hidden again when it finishes | yes, `reward_beer_nye` | same |
| `smoke chirp` | `play_smoke_chirp_sound` | Plays `local_res/smoke-detector-chirp.ogg` | yes, `sfx_commands` (`reward_smoke_chirp`) | same |
| `fart` | `play_fart` | Plays a random file from `local_res/farts/` | yes, `sfx_commands` (`reward_fart`) | same |
| any other title | none | Ignored silently | n/a | |

### 2b. Other EventSub notifications

| Event | Entry point | Correct run | Headless | Platform |
|---|---|---|---|---|
| `channel.follow` | `RSCustom.on_followed` → `show_event_alert(&"follow")` + `destructibles_names(username)` | Green "<name> just followed!" banner at the top with the discord sfx, gone after ~3.6 s (see the follow/raid/sub alert in §4). It shows even with "Names on screen" off and is gated by the "Follow / raid / sub alerts" toggle. The follower's name also drops as physics text when names are on. | alert: yes, `event_alerts`. Names: partial, `eventsub_follow_raid_cheer_sub` checks dispatch with names disabled; text rendering isn't headless-testable (see names). | same |
| `channel.raid` | `RSCustom.on_raided` → `show_event_alert(&"raid")` + `destructibles_names(raider, viewers)` | Orange "<raider> is raiding with N viewers!" banner + discord sfx (as for follow). One name per raiding viewer when names are on. | alert: yes, `event_alerts`. Names: partial (as above) | same |
| `channel.cheer` (only when the relay is **not** configured, see `RSMain.cheer_source`) | `RSCustom.on_cheered` | Cheerer's name, `clamp(bits/100, 1, 20)` copies. Anonymous cheers do nothing. | partial (as above) | same |
| `channel.subscribe` | `RSCustom.on_subscribed` → `show_event_alert(&"sub")`, and `RSSummaryMng._on_subscribed` | Purple "<name> subscribed at Tier N!" (or "<name> got a gifted Tier N sub!") banner + discord sfx (as for follow). No falling names. Recorded in the summary. | yes, `event_alerts` (alert) and `eventsub_follow_raid_cheer_sub` (summary tracks the user) | same |
| First chat message of the session | `RSCustom.on_first_session_message` | Only if OBS reports the stream is live: refresh the user's colour, drop their name, queue an auto shoutout | no: needs OBS and Twitch | same |
| EventSub payload parsing | `classes/RSTwitchEventData.gd:create_from_event_body` | Fields map correctly for every type | yes, `event_payload_parse` | same |

### 2c. Chat commands: `RSCustom.add_commands` (local, via twitcher `TwitchCommand`)

Registered only after Twitch connects. Every handler takes
`(from_username, TwitchCommandInfo, args)`.

| Command (aliases) | Entry point | Correct run | Headless | Platform |
|---|---|---|---|---|
| `!add_me` | `RSUserMng._on_user_request_add` | Adds the chatter to known users | no: Twitch API lookup | same |
| `!discord` | `RSCustom.discord` | Plays the discord sfx and posts the invite link | no: sends chat | same |
| `!c_source` | `c_source` | Plays `sfx_scissors.ogg` and posts a link | no: sends chat. The sfx isn't in `local_res` (loaded from the user data dir). | same |
| `!knock` | `knock` | Plays `local_res/knock.mp3` | yes, `sfx_commands` | same |
| `!pandano` | `pandano` | Restarts OBS media `Panda_no` | no: OBS | same |
| `!whostream` | `whostream` | Posts which known users are live | no: Twitch API | same |
| `!d` | `play_discord_notification` | Plays the `sfx/discord` player | yes, `sfx_commands` (`d`) | same |
| `!quack` | `RS.play_sfx.bind("quack")` | Plays `sfx_quack_01/02.ogg` | yes, `sfx_commands` (`quack`) | same |
| `!toggle_music` | `toggle_music` | Toggles mute on OBS input `Mozilla` | no: OBS | same |
| `!mika`, `!scawy`, `!irad` | `play_mika_system_of_a_down`, `play_scawy_dunkaccino`, `play_irad_being_irad` | Post chat. `!mika`/`!scawy` also play an sfx from the user data dir. | no: send chat, and the sfx aren't in `local_res` | same |
| `!beginning`, `!yippee`, `!twist_it` | `play_beginning`, `play_yippee`, `play_twist_it` | Play an sfx | no: the files (`sfx_jacob_zuma_*`, `sfx_yippee.ogg`, `twist-it/dick-twist.mp3`) aren't in `local_res`. They come from `<data_dir>/sfx/`, which a clean test dir doesn't have. | same |
| `!fart` | `play_fart` | Random fart | yes, `sfx_commands` (`fart`) | same |
| `!b [n]` | `spawn_fake_beans` | n cans (1 by default; if n > 100, a random 50–100). Named presets: `temptic`, `giganzo`, `jake`, `anihan`, `vex`, `mrwho`. Most of these post chat; `temptic` also triggers zero-G. | yes, `cmd_fake_beans` (numeric only; the presets send chat) | same |
| `!n` | `add_name_to_scene` | The chatter's name as physics text | no: text rendering (see names) | same |
| `!shake` | `shake_bodies` | 10 random impulses over 0.5 s | yes, `cmd_shake` | same |
| `!snow` | `let_it_snow` | The `manadono_snow` shader overlay shows for 10 s | no: posts to Twitch chat before showing the snow | same |
| `!laser [angle]` | `laser` | See menu laser | yes, via `menu_laser` (same function) | same |
| `!nuke` | `nuke` | See menu nuke | yes, via `menu_nuke` (same function) | same |
| `!zeroG [secs]` (`zerog`, `0g`, `0G`) | `zero_g` | Gravity 0 for 1–180 s (default 30) | yes, `cmd_zero_g` | same |
| `!g [n]` (`grenade`, `granade`, `grandma`, `grenades`) | `spawn_grenade` | n grenades, n wrapped to 0–5 (69 allowed) | yes, via `menu_grenade` (same spawn) | same |
| TTS commands | commented out in `add_commands` | n/a | n/a | `DisplayServer.tts_*` is OS-dependent |

Chat text triggers in `RSCustom.on_chat` (any chat message):
- A message not starting with `!` → `add_notification_scene`.
- A message containing `kiwi` → opens a hardcoded Discord CDN image in the
  browser.
- `theyagich` saying `wb!` → `yag_welcome_back`: 10× beans, then TTS.
- A message containing `dawdle` → 10× small "dawdle" names.

These aren't headless-tested because they need a real `TwitchChatMessage` and
a user lookup. The notification itself is covered by `chat_notification`.

### 2d. nivek relay events (`classes/RSNivekRelay.gd`)

Websocket to `NIVEK_RELAY_URL` (default
`wss://peanutbudderbot.com/api/overlay/connect`). Sends
`hello {token, since}`, replays events after the cursor, then gets `ready`.

| Event kind | Entry point | Correct run | Headless | Platform |
|---|---|---|---|---|
| `cheer` | `_handle_event` → `cheered` → `RSCustom.on_cheered` (only when the relay is enabled, via `RSMain.cheer_source`) | Same as the EventSub cheer, with durable replay | partial: cursor and frame parsing are covered by `relay_ready_and_cursor`. The names output isn't renderable headless. | same |
| `power_up` `A mullion beanz` | `RSCustom.on_power_up` | 11 × 69 fake beans (capped at 2500 bodies) | not run: too heavy for the 60 s budget. The same spawn is covered by `cmd_fake_beans`. | same |
| `power_up` `jumpscare` | `on_power_up` → `jumpscare_woman` | Scream starts, then after 0.05 s the scary face covers the screen (CanvasLayer 128). Both cut after 1 s. Re-trigger while showing is ignored. | yes, `relay_power_up_jumpscare` | Linux: the audio device is primed at boot (`_prime_jumpscare`) to avoid a ~200 ms first-sound lag. Windows: same code. |
| `extension` `test_beans` | `RSCustom.on_extension_interaction` | 69 fake beans | yes, `relay_extension_test_beans` | same |
| `extension` `jumpscare_woman` | `on_extension_interaction` → `jumpscare_woman` | As above | yes, `relay_extension_jumpscare_woman` | same |
| `redemption`, legacy `command` | `_handle_event` | Ignored. The cursor still advances. | yes, `relay_ready_and_cursor` | same |
| `ready` | `_on_message` | `is_ready()` becomes true. The config window shows "Connected." when the token comes from settings. | yes, `relay_ready_and_cursor` | same |
| Connection, replay, reconnect | `start`, `_on_open`, `_on_closed`, `restart` | hello sent, events replayed after `user://nivek_relay_cursor.txt`, auto-reconnect | no: network | same |

## 3. Chat display (`instances/pnl_chat.gd`, `instances/entries/entry_chat_message.gd`)

| Feature | Entry point | Correct run | Headless | Platform |
|---|---|---|---|---|
| Live chat list | `RSPnlChat._on_chat_message` → `put_chat_entry` | Each message shows with badges, emotes and the user's colour. Capped at `max_display_messages` (200). Auto-scrolls. | no: `EntryChatMessage.populate` fetches badges/emotes through `TwitchMediaLoader`, and unknown users through the Twitch API | same |
| Click a username | `_on_chat_entry_username_pressed` → `context_menu_chat` | A context menu for that user | no: needs input | same |
| Send chat / announcement | `_on_ln_msg_text_submitted`, `_on_ln_announce_text_submitted` | Posts a message or announcement as the broadcaster | no: Twitch | same |
| Chat text effects (`!rb`, `!big`, `!wave`…) | `RSPnlChat.format_msg` | unknown: `format_msg` and `commands_string_format` aren't called anywhere | n/a | |
| Chat notification burst | `RSCustom.add_notification_scene` → `instances/msg_notification.gd:start` | Particles in the four corners plus a per-user notification sfx. Freed after 1.5 s. Suppressed when "Chat notifications" is off. | yes, `chat_notification` | same |

## 4. Other panels and alerts

| Feature | Entry point | Correct run | Headless | Platform |
|---|---|---|---|---|
| Alert bar overlay | `instances/alert_overlay.gd:instantiate_new_bar`, `alert_bar.gd` | Shaking pink text with a countdown bar. Runs its action when the time is up unless closed. | yes (via `reward_shut_down_stream_alert`) | same |
| Follow / raid / sub alert | `RSCustom.show_event_alert(kind, text, color)` | A `CanvasLayer` named `EventAlert` (layer 100, below the jumpscare's 128; group `rs_event_alert`; meta `event_kind`) holding the Label `lb_event_alert`: 64 px outlined text centred across the top. It fades in over 0.3 s, holds 3 s, fades out over 0.3 s and frees itself. Alerts that overlap stack 90 px apart. The label ignores the mouse and isn't in the `UI` group, so it stays click-through. Plays `sfx/discord` through `RS.play_sfx`. | yes, `event_alerts` (node spawned, kind and text, freed, suppressed when disabled; no pixel checks) | same |
| Vetting notifications | `RSVetting.custom_rewards_vetting` → `pnl_notifications.append_vetting_reward` | Unknown or flagged users' reward requests wait for streamer approval | no: needs a human decision | same |
| Auto shoutout | `RSShoutoutMng.add_shoutout` / `_process` | Queued `/shoutout` with a cooldown | no: Twitch | same |
| Summary panel | `instances/pnl_summary.gd` | End-of-stream list of chatters, cheerers, subs, raiders | toggle only (`menu_panel_toggles`) | same |
| Settings panel (users, etc.) | `instances/settings/pnl_settings.gd:open_tab` | Tabbed settings and user management | toggle only | same |
| Welcome panel | `RSMain.welcome_panel_check` | Disabled: always hidden | n/a | |
| Wheel of random | `instances/the_wheel_of_random.gd` | Disabled (see the `Force raid` reward) | n/a | |

## 5. Config window (`instances/settings/win_config.gd`, `RSWinConfig`)

Shown at boot (config mode). Closing it enters overlay mode
(`RSMain.enter_overlay_mode`). The floating-menu settings button brings it back.

| Option | Entry point | Correct run | Headless | Platform |
|---|---|---|---|---|
| Twitch chat login label | `refresh_twitch_identity` | "Twitch chat: <broadcaster_name>" or "(no account configured)" | covered indirectly by `config_window` | same |
| Connect with Twitcher button | `_on_btn_connect_twitch_pressed` → `RSTwitcher.connect_to_twitch` | Status shows "Connecting..." then "Connected." | no: OAuth/network. Status text "Not connected." is checked in `config_window`. | same |
| peanutbudderbot device token + Save & Reconnect | `apply_device_token` | Saves settings immediately, restarts the relay, rebinds cheer consumers (`RSMain.rebind_cheer_source`) | yes with an empty token, `config_window` (save + relay stays disabled + cheers stay on twitcher). A real token needs network. | same |
| Relay status label | `refresh_relay_status` | "No device token set…", "Using NIVEK_DEVICE_TOKEN from the environment…", "Using the token in nivek_relay.env…", "Connecting...", or "Connected." | yes, `config_window` (unset case) | same |
| Chat notifications toggle | `_on_ck_chat_notifications_toggled` | Turns the notification burst on/off | yes, `config_window` + `chat_notification` | same |
| Names on screen toggle | `_on_ck_names_on_screen_toggled` | Turns names on/off for follows, raids, cheers, `!n` and the names button. Doesn't affect the follow/raid/sub alerts. | yes, `config_window` + `names_disabled_by_config` | same |
| Follow / raid / sub alerts toggle (`ck_event_alerts`) | `_on_ck_event_alerts_toggled` → `RSSettings.event_alerts_enabled` (default on) | Turns the follow/raid/sub banner and its sound on/off | yes, `config_window` + `event_alerts` | same |
| Toggle Debug View | `_on_btn_debug_pressed` | Toggles the debug view | same toggle as the menu (`menu_panel_toggles`) | same |
| Config ↔ overlay mode | `RSMain.enter_config_mode` / `enter_overlay_mode`, `RSDisplay.start` / `exit_overlay` | Config: overlay invisible and fully click-through, config window visible. Overlay: transparent, always-on-top, click-through except UI. | state switch yes, `overlay_config_switch`. The visual result is manual (checklist below). | Wayland (patched engine): layer-shell surface, input regions. Wayland (stock engine): ordinary window for OBS capture (`RSDisplay.set_capture_window`). Windows: `always_on_top` plus the `rs_clickthrough` DLL (`WS_EX_TRANSPARENT`). |

## 6. Platform-specific plumbing (not effects, but user-visible)

| Feature | Entry point | Linux | Windows |
|---|---|---|---|
| Transparency | `RSDisplay.start`, `RSMain.enter_config_mode` | Needs a compositor. Wayland honours per-pixel alpha. | Can lose alpha after fullscreen apps or monitor changes. Re-asserted on resize/focus (`_reassert_overlay`). |
| Always-on-top | `RSDisplay.start` | Patched engine only (layer-shell layer 4 = Overlay). Stock Wayland ignores it silently. | `Window.always_on_top` |
| Click-through | `classes/RSMousePass.gd:SetClickThrough`, `RSMouseTracker` | Wayland (patched): input regions from the rects of `UI`-group controls. X11: `RSClickThrough` exists, but the Linux build is a no-op stub, so X11 click-through is **unknown/likely broken**. Stock Wayland: none. | `RSClickThrough` GDExtension (`addons/rs_clickthrough/bin/*.dll`). Without it, falls back to `FLAG_MOUSE_PASSTHROUGH`, which doesn't pass clicks through. |
| Window fit | `RSDisplay.set_borderless_maximized`, `overlay_screen_index` | Patched: the output picked by `display/window/wayland/layer_screen` (-1 = largest), position (0,0). GNOME has no layer-shell. | Borderless at screen size and (0,0). Multi-monitor: unknown. |

---

## Manual by-eye checklist

Run the overlay for real (not headless), with a desktop and something busy
behind it (a browser, a video).

1. **Boot / config mode**
   - [ ] The app opens showing only the config window, as a normal movable
     window. No black full-screen rectangle.
2. **Transparency** (close the config window → overlay mode)
   - [ ] Everything outside the floating menu, panels and effects is fully see-through.
   - [ ] No black or grey bar at the top or edges (Windows: the startup
     "black bar" should clear within a few frames).
   - [ ] Windows: run a fullscreen game or change resolution, then come back.
     The overlay is still transparent.
3. **Always-on-top**
   - [ ] Focus another app and maximise it. The floating menu and effects
     (press beans) stay on top.
   - [ ] Linux: on stock Godot under Wayland this is expected to fail (ordinary
     window). Only the patched engine passes.
4. **Click-through**
   - [ ] Clicking and scrolling on transparent areas reaches the app underneath.
   - [ ] The floating menu, open panels and beans (left-drag, right-click to
     destroy) still take clicks.
   - [ ] Hover off the menu and back on several times. It never becomes
     permanently unclickable or permanently blocking.
   - [ ] Text fields in the chat panel accept typing (on Wayland, keyboard focus
     on the layer surface is a known risk; see `RSMousePass.PIN_INPUT_REGION_TO_WINDOW`).
5. **Window fit**
   - [ ] The overlay covers exactly the intended monitor, with no offset and no
     strip missing. Exception: a strip under a desktop panel on GNOME is
     expected (no layer-shell).
   - [ ] Multi-monitor: it sits on the largest output, or on
     `display/window/wayland/layer_screen`.
   - [ ] Beans land on the visible bottom edge, and the floating menu snaps to
     the real screen edges.
6. **Config round-trip**
   - [ ] Menu → settings brings back the config window with the overlay hidden.
     Closing it restores the overlay with the same transparency and click-through.
7. **Audio/visual sync** (needs the relay, or a local trigger)
   - [ ] The jumpscare image and scream start together, and both stop after ~1 s.
