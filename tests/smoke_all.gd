# Headless smoke test for every overlay feature that can run without a display,
# audio device, network, Twitch, OBS or the nivek relay.
#
# Each feature is triggered through its real code path (floating-menu handler,
# RSCustom command/reward handler, RSTwitcher.on_event for EventSub payloads,
# RSNivekRelay._on_message for relay frames), the scene is advanced, and one line
# is printed per feature:
#   SMOKE <name> OK|FAIL <detail>
# followed by SMOKE_ALL_OK and exit code 0, or SMOKE_ALL_FAIL and exit code 1.
#
# A feature also FAILs if it raised a GDScript error, or an engine error with a
# GDScript backtrace, while it ran (captured with a Logger, Godot 4.5+).
#
# Network is stubbed before RS.start_everything() gets going (it awaits one
# frame first, and this scene's _ready runs inside that frame): the in-memory
# settings lose the Twitch credentials and the relay token/url, the relay env
# vars are unset and the relay's nivek_relay.env cache is pinned empty. On top of
# that, the test refuses to run unless the user data dir is the throwaway one
# passed in RSO_SMOKE_DATA_DIR, so your real settings, tokens, users and the
# relay cursor are never read or written. Use the wrappers:
#   tests/run_smoke.sh  [godot]      (Linux)
#   tests/run_smoke.ps1 [godot.exe]  (Windows)
# Manual run (Linux, native Godot):
#   D=$(mktemp -d); RSO_SMOKE_DATA_DIR=$D XDG_DATA_HOME=$D <godot> --headless --path <repo> res://tests/smoke_all.tscn
extends Node

const BOOT_TIMEOUT_S := 15.0
const SMOKE_USER_ID := 990000001
const SMOKE_USER := "rso_smoke_user"


## Collects errors raised while a feature runs. Called from any thread.
class SmokeLogger extends Logger:
	var _mutex := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		# Only errors caused by game code: GDScript errors, or engine errors that
		# carry a GDScript backtrace. Engine noise with no script on the stack
		# (leaks at exit, headless driver chatter) is ignored.
		if error_type != ERROR_TYPE_SCRIPT and script_backtraces.is_empty():
			return
		var where := "%s:%d" % [file, line]
		if not script_backtraces.is_empty() and script_backtraces[0].get_frame_count() > 0:
			where = "%s:%d" % [script_backtraces[0].get_frame_file(0), script_backtraces[0].get_frame_line(0)]
		var msg := rationale if not rationale.is_empty() else code
		_mutex.lock()
		_errors.append("%s %s (%s)" % [where, msg, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := _errors.duplicate()
		_errors.clear()
		_mutex.unlock()
		return out


var _logger := SmokeLogger.new()
var _failures: int = 0
var _count: int = 0
var _seq: int = 1000
var _t0: int


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	OS.add_logger(_logger)
	_stub_network()
	if not _is_isolated():
		_report("isolation", false, "user data dir '%s' is not inside RSO_SMOKE_DATA_DIR='%s'; run tests/run_smoke.sh or tests/run_smoke.ps1" % [OS.get_user_data_dir(), OS.get_environment("RSO_SMOKE_DATA_DIR")])
		_finish()
		return
	_report("isolation", true, OS.get_user_data_dir())
	_run.call_deferred()


# ============================== harness =======================================
func _stub_network() -> void:
	OS.unset_environment("NIVEK_DEVICE_TOKEN")
	OS.unset_environment("NIVEK_RELAY_URL")
	# RS has already loaded settings in its _ready (synchronous), but has not yet
	# started twitcher/relay: start_everything() awaits a frame first.
	RS.settings.nivek_device_token = ""
	RS.settings.nivek_relay_url = ""
	RS.settings.auto_connect = false
	RS.settings.client_id = "" # RSSettings.is_twitcher_setup() -> false, RSTwitcher.start() aborts
	RS.settings.client_secret = ""
	RS.child_entered_tree.connect(_on_rs_child_entered)


func _on_rs_child_entered(node: Node) -> void:
	if node is RSNivekRelay:
		# Ignore res://nivek_relay.env even if one exists in the checkout.
		node._env_cache = {}
		node._env_loaded = true


func _is_isolated() -> bool:
	var expected := OS.get_environment("RSO_SMOKE_DATA_DIR").replace("\\", "/").trim_suffix("/")
	if expected.is_empty():
		return false
	var actual := OS.get_user_data_dir().replace("\\", "/")
	if OS.get_name() == "Windows":
		return actual.to_lower().begins_with(expected.to_lower())
	return actual.begins_with(expected)


func _report(feature: String, ok: bool, detail: String = "") -> void:
	var errs := _logger.take()
	if not errs.is_empty():
		if ok:
			ok = false
			detail = "raised %d error(s): %s" % [errs.size(), errs[0]]
		else:
			detail += " | first error: %s" % errs[0]
		if errs.size() > 1:
			detail += " (+%d more)" % (errs.size() - 1)
	_count += 1
	if not ok:
		_failures += 1
	print("SMOKE %s %s %s" % [feature, "OK" if ok else "FAIL", detail])


func _begin() -> void:
	_logger.take() # drop anything logged between features


func _finish() -> void:
	var secs := (Time.get_ticks_msec() - _t0) / 1000.0
	if _failures == 0 and _count > 0:
		print("SMOKE summary: %d features OK in %.1f s" % [_count, secs])
		print("SMOKE_ALL_OK")
		get_tree().quit(0)
	else:
		print("SMOKE summary: %d of %d features FAILED in %.1f s" % [_failures, _count, secs])
		print("SMOKE_ALL_FAIL")
		get_tree().quit(1)


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Polls `cond` every process frame until it returns true or `timeout_s` passes.
func _until(cond: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _bodies() -> int:
	return RS.physic_scene.obj_count


## Waits until no new bodies have spawned for 10 physics frames (earlier effects
## spawn over time), so a before/after count belongs to one trigger.
func _settle(timeout_s: float = 4.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var last := _bodies()
	var stable := 0
	while stable < 10 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var now := _bodies()
		stable = stable + 1 if now == last else 0
		last = now


func _relay_frame(kind: String, data: Dictionary) -> int:
	_seq += 1
	var frame := {"type": "event", "event": {"seq": _seq, "kind": kind, "data": data}}
	RS.nivek_relay._on_message(JSON.stringify(frame).to_utf8_buffer())
	return _seq


func _eventsub(type: String, body: Dictionary) -> void:
	RS.twitcher.on_event(type, body)


func _reward_body(title: String, user_input: String = "") -> Dictionary:
	return {
		"user_id": str(SMOKE_USER_ID), "user_login": SMOKE_USER, "user_name": "RsoSmokeUser",
		"user_input": user_input, "status": "unfulfilled",
		"reward": {"title": title, "cost": 1, "prompt": ""},
	}


## A known user so RSUserMng lookups never fall through to the Twitch API.
func _inject_smoke_user() -> RSUser:
	var user := RSUser.new()
	user.user_id = SMOKE_USER_ID
	user.username = SMOKE_USER
	user.display_name = "RsoSmokeUser"
	RS.user_mng.known[SMOKE_USER_ID] = user
	RS.user_mng.username_to_user_id[SMOKE_USER] = SMOKE_USER_ID
	return user


# ================================ tests =======================================
func _run() -> void:
	# --- boot ---
	_begin()
	var started := [false]
	RS.all_started.connect(func(): started[0] = true, CONNECT_ONE_SHOT)
	# _run is deferred from _ready, which runs before RS.start_everything() resumes,
	# so all_started cannot have fired yet.
	var booted: bool = await _until(func(): return started[0], BOOT_TIMEOUT_S)
	if not booted:
		_report("boot", false, "RS.all_started not emitted within %.0f s" % BOOT_TIMEOUT_S)
		_finish()
		return
	await _physics_frames(2)
	var relay_off: bool = not RS.nivek_relay.is_enabled()
	var twitch_off: bool = not RS.twitcher.is_connected_to_twitch
	_report("boot", relay_off and twitch_off and RS.cheer_source() == RS.twitcher,
		"relay_enabled=%s twitch_connected=%s cheer_source=%s" % [not relay_off, not twitch_off, RS.cheer_source().name])
	var user := _inject_smoke_user()

	await _test_config_window()
	await _test_overlay_mode()
	await _test_panels()
	await _test_eventsub_parse()

	# --- Kevin's channel extras: off by default, gated triggers must stay silent ---
	await _test_kevin_extras_off()

	# --- physics effects ---
	# Generic effects run with kevin_channel_extras still off.
	await _test_menu_beans()
	await _test_reward_beans()
	await _test_fake_beans()
	# From here on the Kevin-specific triggers are under test (extension SKUs,
	# power-ups, Beer Nye!, smoke chirp, Shut down stream), so turn the extras on.
	RS.settings.kevin_channel_extras = true
	await _test_relay_extension_beans()
	await _test_relay_cursor()
	var zero_g_started: bool = await _test_zero_g_start()
	await _test_shake()
	await _test_menu_laser()
	await _test_reward_grenade()
	await _test_menu_grenade()

	# --- non-physics effects ---
	await _test_jumpscare_power_up()
	await _test_jumpscare_extension()
	await _test_sfx_commands()
	await _test_beer_nye()
	await _test_chat_notification(user)
	await _test_names_toggle_off()
	await _test_eventsub_events_dispatch()
	await _test_alert_stop_streaming()
	await _test_summary_start()

	if zero_g_started:
		await _test_zero_g_restored()
	await _test_menu_nuke()

	_finish()


func _test_config_window() -> void:
	_begin()
	var wc: RSWinConfig = RS.win_config
	var shown: bool = wc.visible
	var relay_text: String = wc.lb_relay_status.text
	var twitch_text: String = wc.lb_twitch_status.text
	# Toggles write straight into RS.settings.
	wc._on_ck_chat_notifications_toggled(false)
	var notif_off: bool = RS.settings.chat_notifications_enabled == false
	wc._on_ck_chat_notifications_toggled(true)
	wc._on_ck_names_on_screen_toggled(false)
	var names_off: bool = RS.settings.names_on_screen_enabled == false
	wc._on_ck_names_on_screen_toggled(true)
	# Kevin channel extras: off on a clean data dir, and the checkbox drives it.
	var extras_default_off: bool = RS.settings.kevin_channel_extras == false \
		and not wc.ck_kevin_channel_extras.button_pressed
	wc._on_ck_kevin_channel_extras_toggled(true)
	var extras_on: bool = RS.settings.kevin_channel_extras == true
	wc._on_ck_kevin_channel_extras_toggled(false)
	var extras_toggle: bool = extras_default_off and extras_on and RS.settings.kevin_channel_extras == false
	# Save & Reconnect with an empty token: saves settings (to the throwaway data
	# dir), restarts the relay (stays disabled) and rebinds the cheer consumers.
	wc.ln_device_token.text = ""
	wc.apply_device_token()
	await _physics_frames(2)
	var still_off: bool = not RS.nivek_relay.is_enabled()
	var cheer_bound: bool = RS.twitcher.cheered.is_connected(RS.custom.on_cheered) \
		and not RS.nivek_relay.cheered.is_connected(RS.custom.on_cheered)
	var saved: bool = FileAccess.file_exists(RSSettings.get_settings_filepath())
	var ok: bool = shown and relay_text.begins_with("No device token") and twitch_text == "Not connected." \
		and notif_off and names_off and extras_toggle and still_off and cheer_bound and saved
	_report("config_window", ok, "shown_at_boot=%s relay_status='%s' twitch_status='%s' toggles=%s/%s kevin_extras_default_off+toggle=%s relay_still_disabled=%s cheer_on_twitcher=%s settings_saved=%s" % [
		shown, relay_text.left(40), twitch_text, notif_off, names_off, extras_toggle, still_off, cheer_bound, saved])


func _test_overlay_mode() -> void:
	_begin()
	RS.enter_overlay_mode() # what closing the config window does
	await _physics_frames(3)
	var overlay_ok: bool = not RS.win_config.visible and RS.btn_floating_menu.visible and RS.mouse_tracker.is_active
	RS.btn_floating_menu._on_btn_settings_v2_pressed() # floating menu "settings" -> config mode
	await _physics_frames(2)
	var config_ok: bool = RS.win_config.visible and not RS.btn_floating_menu.visible and not RS.mouse_tracker.is_active
	RS.enter_overlay_mode()
	await _physics_frames(2)
	_report("overlay_config_switch", overlay_ok and config_ok and RS.btn_floating_menu.visible,
		"overlay_mode=%s config_mode=%s window_transparent=%s" % [overlay_ok, config_ok, get_window().get_flag(Window.FLAG_TRANSPARENT)])


func _test_panels() -> void:
	_begin()
	var menu: RSFloatingMenu = RS.btn_floating_menu
	var results: PackedStringArray = []
	var ok := true
	var cases := [
		["chat", RS.pnl_chat, menu._on_btn_chat_pressed],
		["summary", RS.pnl_summary, menu._on_btn_summary_pressed],
		["debug", RS.debug_view, menu._on_btn_debug_pressed],
		["user_list", RS.pnl_settings, menu._on_btn_user_list_pressed],
	]
	for c in cases:
		var pnl: Control = c[1]
		var before: bool = pnl.visible
		c[2].call()
		await get_tree().process_frame
		var toggled: bool = pnl.visible != before
		c[2].call()
		await get_tree().process_frame
		var restored: bool = pnl.visible == before
		ok = ok and toggled and restored
		results.append("%s=%s" % [c[0], toggled and restored])
	_report("menu_panel_toggles", ok, " ".join(results))


func _test_eventsub_parse() -> void:
	_begin()
	var cheer := RSTwitchEventData.create_from_event_body("channel.cheer", {"user_id": "1", "user_login": "a", "user_name": "A", "is_anonymous": false, "message": "hi", "bits": 250})
	var raid := RSTwitchEventData.create_from_event_body("channel.raid", {"from_broadcaster_user_id": "2", "from_broadcaster_user_login": "b", "from_broadcaster_user_name": "B", "viewers": 7})
	var sub := RSTwitchEventData.create_from_event_body("channel.subscribe", {"user_id": "3", "user_login": "c", "user_name": "C", "tier": "1000", "is_gift": false})
	var rew := RSTwitchEventData.create_from_event_body("channel.channel_points_custom_reward_redemption.add", _reward_body("beans", "x"))
	var pu := RSTwitchEventData.create_from_event_body("channel.custom_power_up_redemption.add", {"power_up_id": "p", "power_up_title": "jumpscare", "bits": 100})
	var ext := RSTwitchEventData.create_from_event_body("extension.bits", {"product_sku": "test_beans", "bits": 50})
	var ok: bool = cheer.bits == 250 and cheer.username == "a" and raid.viewers == 7 and raid.from_broadcaster_username == "b" \
		and sub.tier == 1000 and rew.reward_title == "beans" and rew.user_input == "x" and pu.power_up_title == "jumpscare" \
		and pu.bits == 100 and ext.product_sku == "test_beans"
	_report("event_payload_parse", ok, "cheer.bits=%d raid.viewers=%d sub.tier=%d reward='%s' power_up='%s' sku='%s'" % [
		cheer.bits, raid.viewers, sub.tier, rew.reward_title, pu.power_up_title, ext.product_sku])


## With kevin_channel_extras off (the default), Kevin's channel-specific triggers
## must do nothing, while a generic reward still works. The "kiwi" text trigger
## is not fired here: if the gate broke it would open a browser on the test box.
func _test_kevin_extras_off() -> void:
	await _settle()
	_begin()
	var default_off: bool = RS.settings.kevin_channel_extras == false
	RS.settings.kevin_channel_extras = false
	var custom_sfx: AudioStreamPlayer = RS.custom.get_node("sfx_custom")
	custom_sfx.stop()
	var vp: VideoStreamPlayer = RS.custom.video_player
	# Snapshot the player itself, not its parent: the parent is the rs_main root
	# Control, which is always visible, so it can't show whether Beer Nye ran.
	var vp_valid := is_instance_valid(vp)
	var vp_visible_before: bool = vp_valid and vp.visible
	var vp_playing_before: bool = vp_valid and vp.is_playing()
	var vp_stream_before: VideoStream = vp.stream if vp_valid else null
	var vb: VBoxContainer = RS.alert_scene.vb_cnt
	var alerts_before := vb.get_child_count()
	var bodies_before := _bodies()

	# Chat text trigger: theyagich saying "wb!" would drop 10x beans.
	var chat := TwitchChatMessage.new()
	chat.chatter_user_id = str(SMOKE_USER_ID)
	chat.chatter_user_name = "theyagich"
	chat.message = TwitchChatMessage.Message.new()
	chat.message.text = "wb!"
	RS.custom.on_chat(chat)
	# Channel-point rewards with Kevin-specific titles.
	_eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("Beer Nye!"))
	_eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("smoke chirp"))
	_eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("Shut down stream", "smoke test"))
	# Power-up titles and extension SKUs.
	_relay_frame("power_up", {"power_up_id": "smoke", "power_up_title": "jumpscare", "bits": 1, "user_login": SMOKE_USER})
	_relay_frame("extension", {"product_sku": "test_beans", "bits": 1, "user_login": SMOKE_USER})
	_relay_frame("extension", {"product_sku": "jumpscare_woman", "bits": 1, "user_login": SMOKE_USER})
	await _wait(1.0)

	var no_beans: bool = _bodies() == bodies_before
	var no_jumpscare: bool = not _jumpscare_visible() and not RS.custom.jumpscare_sfx.playing
	# Beer Nye would assign the .ogv stream, show the player and start playback.
	var no_video: bool = not vp_valid or (vp.visible == vp_visible_before \
		and vp.is_playing() == vp_playing_before and vp.stream == vp_stream_before)
	var no_alert: bool = vb.get_child_count() == alerts_before
	var no_sfx: bool = not custom_sfx.playing
	var silent: bool = no_beans and no_jumpscare and no_video and no_alert and no_sfx

	# Generic rewards are not gated: "fart" must still play with the extras off.
	_eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("fart"))
	var generic_ok: bool = await _until(func(): return custom_sfx.playing and custom_sfx.stream != null, 1.0)
	custom_sfx.stop()

	_report("kevin_extras_off", default_off and silent and generic_ok,
		"default_off=%s no_beans=%s (%d -> %d) no_jumpscare=%s no_beer_nye=%s no_alert=%s no_smoke_chirp=%s generic_fart_plays=%s" % [
		default_off, no_beans, bodies_before, _bodies(), no_jumpscare, no_video, no_alert, no_sfx, generic_ok])


func _test_menu_beans() -> void:
	await _settle()
	_begin()
	var before := _bodies()
	RS.btn_floating_menu._on_btn_beans_pressed()
	var ok: bool = await _until(func(): return _bodies() > before, 3.0)
	await _physics_frames(10)
	_report("menu_beans", ok, "bodies %d -> %d" % [before, _bodies()])


func _test_reward_beans() -> void:
	_begin()
	var before := _bodies()
	_eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("beans"))
	var ok: bool = await _until(func(): return _bodies() > before, 3.0)
	_report("reward_beans", ok, "EventSub channel points 'beans': bodies %d -> %d" % [before, _bodies()])


func _test_fake_beans() -> void:
	await _settle()
	_begin()
	var before := _bodies()
	RS.custom.spawn_fake_beans("", null, PackedStringArray(["5"])) # chat !b 5
	var ok: bool = await _until(func(): return _bodies() >= before + 5, 3.0)
	_report("cmd_fake_beans", ok, "!b 5: bodies %d -> %d" % [before, _bodies()])


func _test_relay_extension_beans() -> void:
	_begin()
	var before := _bodies()
	var seq := _relay_frame("extension", {"product_sku": "test_beans", "bits": 1, "user_login": SMOKE_USER})
	# 69 beans, one every 0.03 s -- just check they are flowing.
	var ok: bool = await _until(func(): return _bodies() >= before + 10, 4.0)
	_report("relay_extension_test_beans", ok and RS.nivek_relay._last_seq == seq,
		"bodies %d -> %d, relay cursor=%d (sent %d)" % [before, _bodies(), RS.nivek_relay._last_seq, seq])


func _test_relay_cursor() -> void:
	_begin()
	RS.nivek_relay._on_message(JSON.stringify({"type": "ready"}).to_utf8_buffer())
	var ready_ok: bool = RS.nivek_relay.is_ready()
	_relay_frame("redemption", {"user_login": SMOKE_USER}) # ignored, but advances the cursor
	var seq := _relay_frame("command", {"action": "beans", "args": ["3"], "user_login": SMOKE_USER}) # legacy kind: same
	var f := FileAccess.open(RSNivekRelay._CURSOR_PATH, FileAccess.READ)
	var persisted := f.get_as_text().strip_edges() if f else "<missing>"
	_report("relay_ready_and_cursor", ready_ok and persisted == str(seq),
		"ready=%s cursor_file=%s expected=%d" % [ready_ok, persisted, seq])


func _gravity() -> float:
	var space: RID = RS.physic_scene.bodies.get_world_2d().space
	return PhysicsServer2D.area_get_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY)


func _test_zero_g_start() -> bool:
	_begin()
	# The menu button uses the 30 s default; !zeroG 1 keeps the test short.
	RS.custom.zero_g("", null, PackedStringArray(["1"]))
	await _physics_frames(2)
	var g := _gravity()
	_report("cmd_zero_g", is_zero_approx(g), "gravity=%.1f right after !zeroG 1 (default %.1f)" % [g, RS.physic_scene.default_gravity])
	return is_zero_approx(g)


func _test_zero_g_restored() -> void:
	_begin()
	var target: float = RS.physic_scene.default_gravity
	var ok: bool = await _until(func(): return is_equal_approx(_gravity(), target), 8.0)
	_report("cmd_zero_g_restore", ok, "gravity=%.1f target=%.1f" % [_gravity(), target])


func _test_shake() -> void:
	_begin()
	var n := get_tree().get_nodes_in_group("editor_bodies").size()
	RS.custom.shake_bodies() # 10 impulses, 0.05 s apart
	await _wait(0.6)
	_report("cmd_shake", n > 0, "shook %d bodies" % n)


func _test_menu_laser() -> void:
	_begin()
	RS.btn_floating_menu._on_btn_laser_pressed()
	await _physics_frames(60)
	var ls = RS.physic_scene.laser_scene
	var valid: bool = is_instance_valid(ls)
	var sweeping: bool = valid and ls.is_physics_processing() and not is_zero_approx(ls.rotation)
	RS.custom.laser() # re-trigger mid-sweep must reuse the same emitter
	await _physics_frames(5)
	var same: bool = valid and RS.physic_scene.laser_scene == ls
	_report("menu_laser", valid and sweeping and same, "emitter=%s sweeping=%s rotation=%.2f retrigger_reuses=%s destroyed=%d" % [
		valid, sweeping, ls.rotation if valid else 0.0, same, ls.obj_destroyed_counter if valid else -1])


func _test_reward_grenade() -> void:
	_begin()
	var before: int = RS.physic_scene.current_granades.size()
	_eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("Granades!"))
	var ok: bool = await _until(func(): return RS.physic_scene.current_granades.size() > before, 2.0)
	_report("reward_grenade", ok, "grenades %d -> %d" % [before, RS.physic_scene.current_granades.size()])


func _test_menu_grenade() -> void:
	_begin()
	RS.btn_floating_menu._on_btn_granade_pressed()
	await get_tree().process_frame
	var spawned: bool = not RS.physic_scene.current_granades.is_empty()
	var g: RigidBody2D = RS.physic_scene.current_granades.back() if spawned else null
	# 4 s fuse, then boom sfx (~2 s), then freed.
	var detonated: bool = spawned and await _until(func(): return not is_instance_valid(g) or g.is_detonated, 6.0)
	var cleared: bool = await _until(func(): return RS.physic_scene.current_granades.is_empty(), 6.0)
	_report("menu_grenade", spawned and detonated and cleared, "spawned=%s detonated=%s all_freed=%s left=%d" % [
		spawned, detonated, cleared, RS.physic_scene.current_granades.size()])


func _jumpscare_visible() -> bool:
	return RS.custom.jumpscare_image.get_parent().visible


func _test_jumpscare(feature: String, kind: String, data: Dictionary) -> void:
	_begin()
	_relay_frame(kind, data)
	var shown: bool = await _until(_jumpscare_visible, 1.0)
	var has_tex: bool = RS.custom.jumpscare_image.texture != null and RS.custom.jumpscare_sfx.stream != null
	var hidden: bool = await _until(func(): return not _jumpscare_visible(), 2.5)
	var sfx_stopped: bool = not RS.custom.jumpscare_sfx.playing
	_report(feature, shown and has_tex and hidden and sfx_stopped, "shown=%s assets=%s hidden_after=%s sfx_stopped=%s" % [shown, has_tex, hidden, sfx_stopped])


func _test_jumpscare_power_up() -> void:
	await _test_jumpscare("relay_power_up_jumpscare", "power_up", {"power_up_id": "smoke", "power_up_title": "jumpscare", "bits": 1, "user_login": SMOKE_USER})


func _test_jumpscare_extension() -> void:
	await _test_jumpscare("relay_extension_jumpscare_woman", "extension", {"product_sku": "jumpscare_woman", "bits": 1, "user_login": SMOKE_USER})


func _test_sfx_commands() -> void:
	# Only commands whose sound ships in res://local_res. !yippee, !beginning,
	# !twist_it and !c_source load from the user's data-dir sfx folder and would
	# fail on a clean data dir; !discord/!mika/!scawy/!irad also send chat.
	_begin()
	var custom_sfx: AudioStreamPlayer = RS.custom.get_node("sfx_custom")
	var results: PackedStringArray = []
	var ok := true
	var cases := [
		["knock", func(): RS.custom.knock(), custom_sfx],
		["fart", func(): RS.custom.play_fart(), custom_sfx],
		["reward_fart", func(): _eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("fart")), custom_sfx],
		["reward_smoke_chirp", func(): _eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("smoke chirp")), custom_sfx],
		["d", func(): RS.custom.play_discord_notification(), RS.get_node("sfx/discord")],
		["quack", func(): RS.play_sfx("", null, PackedStringArray(), "quack"), RS.get_node("sfx/quack")],
	]
	for c in cases:
		var player: AudioStreamPlayer = c[2]
		player.stop()
		c[1].call()
		var playing: bool = await _until(func(): return player.playing and player.stream != null, 1.0)
		ok = ok and playing
		results.append("%s=%s" % [c[0], playing])
		player.stop()
	if not RS.get_node("sfx/discord").stream:
		results.append("(sfx/discord has no stream)")
	elif results.has("d=false"):
		results.append("(!d calls RS.play_sfx(\"discord\"), which lands in _from_username, so `which` is empty)")
	_report("sfx_commands", ok, " ".join(results))


func _test_beer_nye() -> void:
	_begin()
	var vp: VideoStreamPlayer = RS.custom.video_player
	_eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("Beer Nye!"))
	var ok: bool = await _until(func(): return is_instance_valid(vp) and vp.visible and vp.is_playing(), 2.0)
	var detail := "video visible+playing=%s stream=%s" % [ok, vp.stream.resource_path if is_instance_valid(vp) and vp.stream else "<none>"]
	if is_instance_valid(vp):
		vp.stop()
		RS.custom._on_beer_nye_finished()
	_report("reward_beer_nye", ok, detail)


func _test_chat_notification(user: RSUser) -> void:
	_begin()
	var before := RS.get_child_count()
	RS.settings.chat_notifications_enabled = false
	RS.custom.add_notification_scene(user)
	var suppressed: bool = RS.get_child_count() == before
	RS.settings.chat_notifications_enabled = true
	RS.custom.add_notification_scene(user)
	var added: bool = RS.get_child_count() == before + 1
	var freed: bool = await _until(func(): return RS.get_child_count() == before, 3.0)
	_report("chat_notification", suppressed and added and freed, "disabled_suppresses=%s spawned=%s freed_after_1.5s=%s" % [suppressed, added, freed])


func _test_names_toggle_off() -> void:
	# The names effect itself renders text through a SubViewport, which the
	# headless dummy renderer cannot read back, so only the toggle is checked.
	await _settle()
	_begin()
	RS.settings.names_on_screen_enabled = false
	var before := _bodies()
	RS.btn_floating_menu._on_btn_names_pressed()
	await _physics_frames(10)
	var ok: bool = _bodies() == before
	_report("names_disabled_by_config", ok, "bodies %d -> %d with names_on_screen_enabled=false" % [before, _bodies()])


func _test_eventsub_events_dispatch() -> void:
	# follow/raid/cheer end in the names effect (not renderable headless), so they
	# run with names disabled: this checks parsing + dispatch + summary bookkeeping.
	_begin()
	RS.settings.names_on_screen_enabled = false
	var base := {"user_id": str(SMOKE_USER_ID), "user_login": SMOKE_USER, "user_name": "RsoSmokeUser"}
	_eventsub("channel.follow", base.merged({"followed_at": "2026-01-01T00:00:00Z"}))
	_eventsub("channel.raid", {"from_broadcaster_user_id": str(SMOKE_USER_ID), "from_broadcaster_user_login": SMOKE_USER, "from_broadcaster_user_name": "RsoSmokeUser", "viewers": 3})
	_eventsub("channel.cheer", base.merged({"is_anonymous": false, "message": "smoke", "bits": 300}))
	_eventsub("channel.subscribe", base.merged({"tier": "1000", "is_gift": false}))
	await _physics_frames(10)
	RS.settings.names_on_screen_enabled = true
	var tracked: bool = RS.summary_mng.has_current_user(SMOKE_USER_ID)
	_report("eventsub_follow_raid_cheer_sub", tracked, "dispatched without errors; summary tracks user=%s" % tracked)


func _test_alert_stop_streaming() -> void:
	_begin()
	var vb: VBoxContainer = RS.alert_scene.vb_cnt
	var before := vb.get_child_count()
	_eventsub("channel.channel_points_custom_reward_redemption.add", _reward_body("Shut down stream", "smoke test"))
	var shown: bool = await _until(func(): return vb.get_child_count() > before and RS.alert_scene.visible, 2.0)
	# Cancel before the 10 s countdown would call OBS stop_stream.
	for child in vb.get_children():
		if child is RSAlertBar:
			child.cancel()
	await _physics_frames(3)
	_report("reward_shut_down_stream_alert", shown, "alert bar shown=%s (cancelled before OBS call)" % shown)


func _test_summary_start() -> void:
	_begin()
	RS.btn_floating_menu._on_btn_summary_start_pressed()
	await get_tree().process_frame
	var s = RS.summary_mng.summary
	var ok: bool = s != null and s.stream_start > 0
	_report("menu_summary_start", ok, "new summary stream_start=%s" % (s.stream_start if s else "<null>"))


func _test_menu_nuke() -> void:
	_begin()
	RS.btn_floating_menu._on_btn_beans_pressed()
	await _until(func(): return _bodies() > 0, 2.0)
	var before := _bodies()
	RS.btn_floating_menu._on_btn_nuke_pressed()
	await get_tree().process_frame
	var nuking: bool = RS.physic_scene.is_nuking
	# alert sfx (~1.3 s), then boom + bodies freed.
	var cleared: bool = await _until(func(): return RS.physic_scene.bodies.get_child_count() == 0, 6.0)
	var fire: bool = RS.physic_scene.get_node("%fire").visible
	var laser_gone: bool = not is_instance_valid(RS.physic_scene.laser_scene) or RS.physic_scene.laser_scene.is_queued_for_deletion()
	_report("menu_nuke", nuking and cleared and laser_gone, "is_nuking=%s bodies %d -> %d fire_shown=%s laser_freed=%s" % [
		nuking, before, RS.physic_scene.bodies.get_child_count(), fire, laser_gone])
