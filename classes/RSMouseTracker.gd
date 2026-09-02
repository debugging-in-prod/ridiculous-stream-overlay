extends Node
class_name RSMouseTracker


var m_pos: Vector2
var is_active := true:
	set(val):
		is_active = val
		set_process(is_active)
		RS.mouse_pass.SetClickThrough(false)

var is_gui_active := false
var is_on_a_control_node := false
var hovered_control_node: Control
var is_on_a_window := false
var is_on_title_bar := false
var is_on_window_decoration := false

signal mouse_track_updated(is_passthrough)

func _ready() -> void:
	set_process(false)

func start():
	set_process(true)


func _process(_d) -> void:
	m_pos = _cursor_in_canvas()
	is_on_title_bar = is_m_pos_in_title(m_pos)
	is_on_window_decoration = is_m_pos_on_window_decoration(m_pos)
	is_on_a_window = is_m_pos_in_window(m_pos)
	
	if is_on_title_bar or is_on_window_decoration: is_on_a_control_node = false
	else: is_on_a_control_node = is_m_pos_in_control_nodes(m_pos)
	
	var checks = (is_on_a_control_node or is_on_title_bar or is_on_window_decoration or is_on_a_window)
	if is_gui_active != checks:
		is_gui_active = checks
		mouse_track_updated.emit(!is_gui_active)


# The cursor position the hit-tests run against, in global canvas coordinates --
# the space RS.get_global_mouse_position() and Control.get_global_rect() share.
#
# On the passthrough-toggle platforms (Windows/macOS/X11) the window stops
# receiving mouse-motion events while it is click-through, so the viewport's
# last-seen mouse -- what RS.get_global_mouse_position() returns -- freezes at
# wherever the cursor was when passthrough turned on. The cursor then never
# "arrives" at the menu, is_gui_active never flips true, and the window is never
# switched back to interactive: the menu renders but no click lands. Poll the OS
# cursor instead (live regardless of passthrough) and map its screen pixels back
# into canvas space with the inverse of the same screen transform RSMousePass
# applies the forward way when it builds passthrough regions.
#
# On Wayland click-through is done with input regions, not this toggle, and that
# path was validated against get_global_mouse_position(); leave it untouched.
func _cursor_in_canvas() -> Vector2:
	if DisplayServer.get_name() == "Wayland":
		return RS.get_global_mouse_position()
	var window := get_window()
	var window_local := Vector2(DisplayServer.mouse_get_position()) - Vector2(window.position)
	return get_viewport().get_screen_transform().affine_inverse() * window_local


func is_pixel_transparent(pos: Vector2) -> bool:
	if !RS.get_rect().has_point(pos):
		return true
	return !get_window().get_texture().get_image().get_pixelv(pos).a > 0


func is_m_pos_in_control_nodes(pos: Vector2) -> bool:
	if !RS.get_rect().has_point(pos):
		return false
	for ctr: Control in get_tree().get_nodes_in_group("UI"):
		if !ctr.is_visible_in_tree(): continue
		var pos_rotated = pos
		var ctr_angle = ctr.get_global_transform().get_rotation()
		if ctr_angle != 0:
			pos_rotated = (pos - ctr.global_position).rotated(-ctr_angle) + ctr.global_position
		
		if ctr is HSplitContainer:
			if ctr.get_child_count() != 2: continue
			var ctr_left: Control = ctr.get_child(0)
			var ctr_right: Control = ctr.get_child(1)
			if !ctr_left.visible or !ctr_right.visible:
				continue
			var grabber_rect := ctr.get_global_rect()
			grabber_rect.position.x = ctr_left.size.x
			grabber_rect.size.x -= ctr_left.size.x + ctr_right.size.x
			if grabber_rect.has_point(pos_rotated):
				hovered_control_node = ctr
				return true
			continue
		
		if ctr.get_global_rect().has_point(pos_rotated):
			hovered_control_node = ctr
			return true
	return false


func is_m_pos_in_window(pos: Vector2) -> bool:
	if !RS.get_rect().has_point(pos):
		return false
	for window: Window in get_tree().get_nodes_in_group("UIWindows"):
		if not window.visible: continue
		var win_rect := Rect2i(window.get_position_with_decorations(), window.get_size_with_decorations())
		if win_rect.has_point(pos):
			return true
	return false


func is_m_pos_in_title(pos: Vector2) -> bool:
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		return false
	var title_size: Vector2i = DisplayServer.window_get_title_size("App")
	@warning_ignore("narrowing_conversion")
	title_size = Vector2i(RS.get_rect().size.x, 30)
	var title_rect := Rect2i(Vector2i(0, -title_size.y), title_size)
	
	return title_rect.has_point(Vector2i(pos))

func is_m_pos_on_window_decoration(pos: Vector2) -> bool:
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		return false
	var window_rect := Rect2i(RS.get_rect())
	var title_size: Vector2i = DisplayServer.window_get_title_size("App")
	var decorations_offset := Vector2i.ONE * 8
	
	var decorations_size := window_rect.size
	decorations_size.y += title_size.y
	decorations_size += decorations_offset * 2
	
	var decorations_pos := -decorations_offset
	decorations_pos.y -= title_size.y
	
	var window_rect_decorations := Rect2i(decorations_pos, decorations_size)
	
	return window_rect_decorations.has_point(pos) and not window_rect.has_point(pos)
