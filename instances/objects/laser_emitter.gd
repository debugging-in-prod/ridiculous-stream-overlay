
extends Node2D

var duration = 20
var tw : Tween
var tmr: Timer

var query : PhysicsRayQueryParameters2D
var obj_destroyed_counter : int = 0


func _ready():
	set_physics_process(false)
	tmr = Timer.new()
	add_child(tmr)
	tmr.one_shot = true
	tmr.wait_time = 1.5
	tmr.timeout.connect(queue_free)


func play(angle: float):
	await get_tree().physics_frame
	if not query:
		query = PhysicsRayQueryParameters2D.create(Vector2(), Vector2())
		query.collide_with_bodies = true
		query.collision_mask = 0b111111 #1+2+4+8+16+32
	
	var passes = 5
	set_physics_process(true)
	# triggered again while still sweeping: restart instead of stacking a second tween on rotation
	if tw and tw.is_valid():
		tw.kill()
	tw = create_tween().bind_node(self)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_SINE)
	@warning_ignore("integer_division")
	var single_duration = duration/passes
	tw.tween_property(self, "rotation", angle, single_duration)
	tw.tween_property(self, "rotation", -angle, single_duration)
	tw.tween_property(self, "rotation", angle, single_duration)
	tw.tween_property(self, "rotation", -angle, single_duration)
	tw.tween_property(self, "rotation", 0, single_duration)


func replay():
	return
	# tw.tween_property(self, "rotation", TAU, 3.0)
	# await tw.finished
	# queue_free()


# The direct space state is only safe to query during _physics_process
# (physics runs on a separate thread, see project.godot).
func _physics_process(_d):
	if rotation == 0 and tmr.is_stopped():
		tmr.start()
	elif rotation != 0:
		tmr.stop()
	
	var firing = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	query.from = %ray.global_position
	query.to = %ray.global_position + %ray.target_position.rotated(rotation)
	var space := get_world_2d().direct_space_state
	var coll_dic : Dictionary = space.intersect_ray(query)
	var colliding = !coll_dic.is_empty()
	
	%line.visible = firing #and colliding
	%line.points[1] = %ray.target_position
	%impact_particles.emitting = colliding and firing
	
	if colliding and firing:
		var impact_pos = coll_dic.position
		var n = coll_dic.normal
		var n_angle = n.angle()
		var coll = coll_dic.collider
		
		%line.points[1].y = (impact_pos - %line.global_position).length()
		%impact_particles.global_position = impact_pos
		%impact_particles.global_rotation = n_angle + PI/2
		
		if not is_instance_valid(coll) or coll.is_queued_for_deletion():
			return
		if coll.has_method("destroy"):
			coll.destroy.call_deferred()
			obj_destroyed_counter += 1
			%lb_counter.text = str(obj_destroyed_counter)
		elif coll is RigidBody2D and firing:
			coll.apply_impulse((Vector2.RIGHT * 30).rotated(n_angle+PI), impact_pos)
		
