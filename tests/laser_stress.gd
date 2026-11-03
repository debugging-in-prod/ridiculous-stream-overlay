# Laser/physics stress test (regression test for the beans + laser hang).
#
# Spawns beans several times through the real RS autoload, fires the laser
# (twice, to also cover a re-trigger mid-sweep) and lets it run for many
# physics frames while it destroys cans and shards. Prints STRESS_OK and quits
# with exit code 0 when done. If the overlay hangs, nothing is printed after the
# last "STRESS:" progress line, so run it under an external timeout.
#
# Run headless (use an isolated user data dir so your real settings/tokens are
# not loaded):
#   XDG_DATA_HOME=$(mktemp -d) <godot> --headless --path <repo> res://tests/laser_stress.tscn
# Windows (PowerShell):
#   $env:APPDATA = "$env:TEMP\rso-stress"; godot_console.exe --headless --path <repo> res://tests/laser_stress.tscn
extends Node

const BEAN_ROUNDS := 12
const FRAMES_BETWEEN_BEANS := 20
const LASER_FRAMES := 1500


func _ready() -> void:
	print("STRESS: start, physics thread=", ProjectSettings.get_setting("physics/2d/run_on_separate_thread"))
	await RS.all_started
	print("STRESS: RS started")
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


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _destroyed(ps: RSPhysicsScene) -> int:
	if is_instance_valid(ps.laser_scene):
		return ps.laser_scene.obj_destroyed_counter
	return -1 # laser finished its sweep and freed itself
