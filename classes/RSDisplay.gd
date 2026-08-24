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
	return DisplayServer.get_name() != "Wayland"


func start() -> void:
	get_window().mode = Window.MODE_WINDOWED
	if supports_desktop_overlay():
		set_borderless_maximized(true)
	else:
		set_capture_window()
	set_app_scale(RS.settings.app_scale)


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
		var current_screen := current_window.current_screen
		# thanks to Foolbox <3 and Giganzo
		var usable_rect := DisplayServer.screen_get_usable_rect(current_screen)
		var screen_position := DisplayServer.screen_get_position(current_screen)

		_log.i("[RSDisplay] Moving window %d to %s and resizing it to %s" % [
			current_window.get_window_id(),
			screen_position,
			usable_rect.size,
		])

		current_window.size = usable_rect.size
		current_window.position = screen_position

		_log.i("[RSDisplay] Moved window %d to %s and resized it to %s" % [
			current_window.get_window_id(),
			current_window.position,
			current_window.size,
		])


func set_app_scale(_scale: float) -> void:
	get_tree().root.content_scale_factor = _scale
