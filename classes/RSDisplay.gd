extends Node
class_name RSDisplay

static var _log: TwitchLogger = TwitchLogger.new(&"RSDisplay")

var is_maximized := false


## Whether this platform can present the app as a click-through, always-on-top
## desktop overlay.
##
## Godot's Wayland backend implements none of the three primitives that mode
## needs: window_set_mouse_passthrough is a TODO stub, window_set_position is
## documented "Unsupported with toplevels", and WINDOW_FLAG_ALWAYS_ON_TOP is
## absent from window_set_flag's switch. Worse, get_flag()/position read back
## the values you set regardless, so the failure is completely silent.
##
## Where this returns false the app runs as an ordinary window instead, sized
## to the design resolution so an OBS window capture gets a predictable source.
static func supports_desktop_overlay() -> bool:
	if DisplayServer.get_name() != "Wayland":
		return true

	# Stock Godot 4.6 stubs mouse passthrough, window positioning and
	# always-on-top on Wayland, so the overlay presentation is impossible there.
	# An engine built with the wlr-layer-shell patch (PR #109875) implements all
	# three, and advertises itself with this feature constant -- which does not
	# exist on a stock build, hence the ClassDB probe rather than a direct
	# reference.
	if not ClassDB.class_has_integer_constant(&"DisplayServer", &"FEATURE_WAYLAND_LAYER_SHELL"):
		return false
	var feature := ClassDB.class_get_integer_constant(&"DisplayServer", &"FEATURE_WAYLAND_LAYER_SHELL")
	return DisplayServer.has_feature(feature)


## Screen the overlay is bound to. Matches display/window/wayland/layer_screen:
## -1 (default) is the largest output, otherwise an output index. On Wayland,
## Window.current_screen is hardcoded to 0, which is not necessarily that output.
static func overlay_screen_index() -> int:
	var layer_screen := int(ProjectSettings.get_setting("display/window/wayland/layer_screen", -1))
	var count := DisplayServer.get_screen_count()
	if layer_screen >= 0 and layer_screen < count:
		return layer_screen
	var best := 0
	var best_area := -1
	for i in count:
		var size := DisplayServer.screen_get_size(i)
		var area := size.x * size.y
		if area > best_area:
			best_area = area
			best = i
	return best


func start() -> void:
	get_window().mode = Window.MODE_WINDOWED
	if supports_desktop_overlay():
		set_borderless_maximized(true)
	else:
		set_capture_window()
	set_app_scale(RS.settings.app_scale)

	var w := get_window()
	_log.i("[RSDisplay] transparency: window FLAG_TRANSPARENT=%s  root.transparent_bg=%s  project.allowed=%s  project.transparent=%s  renderer=%s" % [
		w.get_flag(Window.FLAG_TRANSPARENT),
		get_tree().root.transparent_bg,
		ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed"),
		ProjectSettings.get_setting("display/window/size/transparent"),
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
	])


## Capture-mode presentation: a normal, decorated window at the project's
## design resolution, for OBS to window-capture and composite over the game.
func set_capture_window() -> void:
	var current_window := get_window()
	var design_size := Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	)
	is_maximized = false
	current_window.borderless = false
	current_window.size = design_size

	_log.i("[RSDisplay] %s cannot host a desktop overlay; running as a %s capture window" % [
		DisplayServer.get_name(),
		design_size,
	])


func set_borderless_maximized(value: bool):
	var current_window := get_window()
	is_maximized = value

	current_window.borderless = value
	if is_maximized:
		current_window.mode = Window.MODE_WINDOWED
		# thanks to Foolbox <3 and Giganzo
		# Window.current_screen is always 0 on Wayland. Use the same output the
		# layer surface is bound to (largest, or layer_screen) so size/position
		# match the monitor the overlay actually lives on.
		var screen := overlay_screen_index()
		var screen_size := DisplayServer.screen_get_size(screen)

		# Layer-shell anchors are output-relative. (0, 0) is this output's
		# top-left. screen_get_position() is compositor-global — 2560,0 for the
		# ultrawide sitting to the right of another monitor — and the compositor
		# would treat that as a 2560px offset from the ultrawide's own left edge.
		_log.i("[RSDisplay] Moving window %d to output-local (0, 0) on screen %d and resizing it to %s" % [
			current_window.get_window_id(),
			screen,
			screen_size,
		])

		current_window.size = screen_size
		current_window.position = Vector2i.ZERO

		_log.i("[RSDisplay] Moved window %d to %s and resized it to %s" % [
			current_window.get_window_id(),
			current_window.position,
			current_window.size,
		])


func set_app_scale(_scale: float) -> void:
	get_tree().root.content_scale_factor = _scale
