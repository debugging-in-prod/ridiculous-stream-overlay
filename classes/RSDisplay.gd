extends Node
class_name RSDisplay

static var _log: TwitchLogger = TwitchLogger.new(&"RSDisplay")

var is_maximized := false

# Guards _reassert_overlay against re-entering through the size_changed it fires.
var _reasserting := false


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
		# The transparent, screen-sized, always-on-top overlay window can silently
		# lose its per-pixel alpha: an app taking exclusive fullscreen, a
		# resolution/refresh change, a monitor sleep-wake or hotplug, or a GPU reset
		# makes the compositor (DWM on Windows) stop compositing it, and the
		# viewport's opaque black clear colour then fills the whole screen. These
		# flags are set once at startup and nothing recovers them on its own, so
		# re-assert on the two events that mark such a change: the window resizing
		# (a resolution/monitor change fires size_changed) and the app regaining
		# focus (fires when a fullscreen app releases). See _reassert_overlay.
		get_window().size_changed.connect(_on_window_size_changed)
		# The overlay launches already focused, so the focus-in re-assert never
		# fires at startup -- and Windows/DWM doesn't fully honour the initial
		# per-pixel transparency until the window has been realized and a frame
		# composited, leaving a black bar at the top of the screen until the first
		# focus change clears it (the same lost-alpha failure, present from launch).
		# Re-assert once the first frames are out to clear it at startup.
		_reassert_after_startup()
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


## Startup fixup for the black bar that sits at the top of the screen until the
## first focus change: the initial transparency doesn't fully take until the
## window is realized and composited, and nothing re-asserts at launch because
## the app starts already focused (so no focus-in notification arrives). Wait for
## the first frames to go out, then re-assert -- the same operation the focus-in
## handler performs, which is what a manual focus change relies on to clear it.
func _reassert_after_startup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_reassert_overlay()


func _on_window_size_changed() -> void:
	_reassert_overlay()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_reassert_overlay()


## Re-establishes the desktop-overlay window state (borderless, screen-sized,
## per-pixel transparent) after something external dropped it -- the failure that
## leaves the overlay a solid black rectangle covering the screen. A no-op outside
## overlay mode (capture-window mode has nothing to re-assert), and guarded so the
## resize set_borderless_maximized performs cannot recurse back in through
## size_changed.
func _reassert_overlay() -> void:
	if not is_maximized or _reasserting:
		return
	_reasserting = true

	# Toggling FLAG_TRANSPARENT forces the platform to re-create the layered
	# per-pixel-alpha window attributes the compositor can drop; the root viewport's
	# transparent_bg (from project settings) is unaffected and still shows through.
	# Then restore borderless + geometry on the current output.
	var w := get_window()
	w.set_flag(Window.FLAG_TRANSPARENT, false)
	w.set_flag(Window.FLAG_TRANSPARENT, true)
	set_borderless_maximized(true)

	_reasserting = false
	_log.i("[RSDisplay] re-asserted overlay window (transparency + geometry)")
