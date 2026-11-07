# Regression check for tests/test_isolation.gd, the network stubs used by
# tests/laser_stress.gd. Boots the real RS autoload and needs no credentials and
# no network beyond 127.0.0.1.
#
# Before applying the stubs it plants dummy relay config that points at a local
# TCP listener: NIVEK_DEVICE_TOKEN / NIVEK_RELAY_URL env vars and the in-memory
# relay settings. If the stubs failed, or were applied too late, RS's relay would
# connect to that listener, and the check fails. It also checks that the relay's
# nivek_relay.env cache was pinned empty and that Twitch did not start.
#
# A positive control then starts a separate RSNivekRelay whose env-file cache
# holds the same dummy values, and requires that the listener sees its
# connection. That proves the dummy config would enable a relay and that the
# listener detects connections.
#
# Prints one "ISOLATION <name> OK|FAIL <detail>" line per check, then
# ISOLATION_OK (exit 0) or ISOLATION_FAIL (exit 1). Run it through the wrapper
# from a checkout without nivek_relay.env (see docs/TESTING.md):
#   SMOKE_SCENE=res://tests/isolation_check.tscn SMOKE_MARKER=ISOLATION_OK tests/run_smoke.sh <godot>
extends Node

const Isolation := preload("res://tests/test_isolation.gd")
const DUMMY_TOKEN := "rso-isolation-check-dummy-token"
const QUIET_FRAMES := 120 # frames after boot during which RS's relay must not connect
const CONTROL_FRAMES := 300 # frames to wait for the control relay's connection

var _server := TCPServer.new()
var _failures := 0


func _ready() -> void:
	# Everything up to stub_network() must run before the first await: RS
	# starts the relay one frame from now.
	if _server.listen(0, "127.0.0.1") != OK:
		_report("listener", false, "could not listen on 127.0.0.1")
		_finish()
		return
	var url := "ws://127.0.0.1:%d" % _server.get_local_port()

	OS.set_environment("NIVEK_DEVICE_TOKEN", DUMMY_TOKEN)
	OS.set_environment("NIVEK_RELAY_URL", url)
	RS.settings.nivek_device_token = DUMMY_TOKEN
	RS.settings.nivek_relay_url = url

	var stub_err := Isolation.stub_network(RS)
	_report("stubs_in_time", stub_err.is_empty(), stub_err)
	_report("data_dir", Isolation.is_isolated(), OS.get_user_data_dir())
	# Existence check only; the file is never opened. With the file present a
	# broken pin could reach production, so treat it as a failed precondition.
	_report("clean_checkout", not FileAccess.file_exists("res://nivek_relay.env"),
			"res://nivek_relay.env exists; run from a checkout without it")
	if _failures > 0:
		_finish()
		return

	await RS.all_started
	for i in QUIET_FRAMES:
		await get_tree().process_frame
	_report("relay_no_connection", not _server.is_connection_available(),
			"RS's relay connected to the dummy endpoint")
	var net_err := Isolation.check_network_inert(RS)
	_report("network_inert", net_err.is_empty(), net_err)

	await _positive_control(url)
	_finish()


func _positive_control(url: String) -> void:
	var control := RSNivekRelay.new()
	control.name = &"IsolationControlRelay"
	control._env_cache = {"NIVEK_DEVICE_TOKEN": DUMMY_TOKEN, "NIVEK_RELAY_URL": url}
	control._env_loaded = true
	add_child(control) # not a child of RS, so the stub's pin does not apply
	if not control.is_enabled():
		_report("control_enabled", false, "dummy env-file values did not enable a relay")
		control.queue_free()
		return
	control.start()
	var seen := false
	for i in CONTROL_FRAMES:
		await get_tree().process_frame
		if _server.is_connection_available():
			seen = true
			break
	_report("control_connects", seen, "listener saw no connection from the control relay")
	if control._ws != null:
		control._ws.close()
	if seen:
		_server.take_connection().disconnect_from_host()
	control.queue_free()


func _report(check: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failures += 1
	print("ISOLATION %s %s %s" % [check, "OK" if ok else "FAIL", "" if ok else detail])


func _finish() -> void:
	_server.stop()
	if _failures == 0:
		print("ISOLATION_OK")
		get_tree().quit(0)
	else:
		print("ISOLATION_FAIL %d check(s) failed" % _failures)
		get_tree().quit(1)
