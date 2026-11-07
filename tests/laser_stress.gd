# Laser/physics stress test (regression test for the beans + laser hang).
#
# Spawns beans several times through the real RS autoload, fires the laser
# (twice, to also cover a re-trigger mid-sweep) and lets it run for many
# physics frames while it destroys cans and shards. Prints STRESS_OK and quits
# with exit code 0 when done. If the overlay hangs, nothing is printed after the
# last "STRESS:" progress line, so run it under an external timeout.
#
# Network: before RS starts anything, the nivek relay and Twitch are stubbed
# out the same way as smoke_all.gd (tests/test_isolation.gd): relay env vars
# unset, credentials blanked in memory, res://nivek_relay.env ignored. After
# boot the test fails with STRESS_FAIL if the relay or Twitch came up anyway.
# It also refuses to run outside the throwaway user data dir (RSO_SMOKE_DATA_DIR),
# because Twitcher add-on nodes read tokens from it before this script runs.
#
# Run it through the wrapper (see docs/TESTING.md):
#   SMOKE_SCENE=res://tests/laser_stress.tscn SMOKE_MARKER=STRESS_OK tests/run_smoke.sh <godot>
# Manual run (Linux, native Godot):
#   D=$(mktemp -d); RSO_SMOKE_DATA_DIR=$D XDG_DATA_HOME=$D <godot> --headless --path <repo> res://tests/laser_stress.tscn
extends Node

const Isolation := preload("res://tests/test_isolation.gd")

const BEAN_ROUNDS := 12
const FRAMES_BETWEEN_BEANS := 20
const LASER_FRAMES := 1500


func _ready() -> void:
	# Must run before the first await: RS starts the relay one frame from now.
	var stub_err := Isolation.stub_network(RS)
	if not stub_err.is_empty():
		_fail("network stubs not applied: " + stub_err)
		return
	if not Isolation.is_isolated():
		_fail("user data dir '%s' is not inside RSO_SMOKE_DATA_DIR='%s'; run tests/run_smoke.sh or tests/run_smoke.ps1" % [OS.get_user_data_dir(), OS.get_environment("RSO_SMOKE_DATA_DIR")])
		return
	print("STRESS: start, physics thread=", ProjectSettings.get_setting("physics/2d/run_on_separate_thread"))
	await RS.all_started
	print("STRESS: RS started")
	var net_err := Isolation.check_network_inert(RS)
	if not net_err.is_empty():
		_fail("network not isolated: " + net_err)
		return
	print("STRESS: relay and Twitch inert")
	var ps: RSPhysicsScene = RS.physic_scene
	
	for i in BEAN_ROUNDS:
		RS.custom.beans("")
		await _physics_frames(FRAMES_BETWEEN_BEANS)
	print("STRESS: beans spawned, bodies=", ps.obj_count)
	
	RS.custom.laser()
	await _physics_frames(5)
	RS.custom.laser() # re-trigger while the first sweep is running
	
	for f in LASER_FRAMES:
		if f % 100 == 0:
			print("STRESS: laser frame ", f, " bodies=", ps.obj_count, " destroyed=", _destroyed(ps))
		if f % 300 == 150:
			RS.custom.beans("") # more beans while the laser is firing
		await get_tree().physics_frame
	
	print("STRESS: done, bodies=", ps.obj_count, " destroyed=", _destroyed(ps))
	print("STRESS_OK")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("STRESS_FAIL ", reason)
	get_tree().quit(1)


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _destroyed(ps: RSPhysicsScene) -> int:
	if is_instance_valid(ps.laser_scene):
		return ps.laser_scene.obj_destroyed_counter
	return -1 # laser finished its sweep and freed itself
