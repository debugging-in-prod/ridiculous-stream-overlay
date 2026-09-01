extends Node
class_name RSMousePass

## Cross-platform replacement for the original Windows-only RSMousePass.cs,
## which P/Invoked user32.dll (SetWindowLong / WS_EX_TRANSPARENT).
##
## Two different models are needed, because the original one cannot work on
## Wayland at all:
##
## - Windows/macOS/X11 toggle whole-window click-through with
##   Window.FLAG_MOUSE_PASSTHROUGH, and RSMouseTracker decides when by polling
##   the cursor. That relies on asking the OS where the pointer is regardless of
##   which window it is over.
##
## - Wayland has no such query by design: a surface that passes clicks through
##   receives no pointer events, so the app can never learn the cursor has
##   reached its menu and can never switch input back on. The toggle is one-way
##   and the overlay becomes permanently unclickable. Instead we declare the
##   interactive rectangles up front as the surface's input region; the
##   compositor routes clicks to the UI and passes everything else through, and
##   pointer events over the UI arrive normally.

static var _log: TwitchLogger = TwitchLogger.new(&"RSMousePass")

var supported := false

## True where input regions are declared rather than toggled.
var _use_input_regions := false
var _click_through := true
var _last_regions: Array[Rect2i] = []

## EXPERIMENT (branch experiment/input-region-churn) -- revert before merging.
##
## Pins the input region to the whole window instead of tracking the UI rects,
## so the compositor sees a single wl_surface_set_input_region instead of one
## per frame. Clicks stop passing through to the desktop while this is on.
##
## It exists to tell two candidate causes of unfocusable text boxes apart:
##   typing works -> the per-frame region rebuild was breaking keyboard focus
##   typing fails -> the layer surface never gets keyboard focus at all, since
##                   nothing calls zwlr_layer_surface_v1.set_keyboard_interactivity
##
## Left off so click-through works normally. Flip to true only to re-run the
## comparison; a pinned run logged 0 pushes per 300 frames once the window
## settled, against whatever the normal path reports.
const PIN_INPUT_REGION_TO_WINDOW := false

## Pushes are counted and logged so the churn can be compared between modes.
const _APPLY_LOG_INTERVAL_FRAMES := 300
var _applies_since_log := 0
var _frames_since_log := 0


func _ready() -> void:
	supported = RSDisplay.supports_desktop_overlay()
	_use_input_regions = supported and DisplayServer.get_name() == "Wayland"

	if not supported:
		_log.i("click-through is not available on the %s display server; running as an ordinary window" % DisplayServer.get_name())
	elif _use_input_regions:
		_log.i("using Wayland input regions for click-through")
		if PIN_INPUT_REGION_TO_WINDOW:
			_log.w("EXPERIMENT: input region pinned to the whole window, clicks will not pass through")
	set_process(_use_input_regions)


## Named in PascalCase to stay signal-compatible with the C# original, which
## RSMouseTracker.mouse_track_updated connects to directly.
func SetClickThrough(clickthrough: bool) -> void:
	_click_through = clickthrough
	if not supported:
		return
	if _use_input_regions:
		_apply_input_regions()
	else:
		get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, clickthrough)


func _process(_delta: float) -> void:
	_apply_input_regions()

	_frames_since_log += 1
	if _frames_since_log >= _APPLY_LOG_INTERVAL_FRAMES:
		_log.i("input region pushed %d times in the last %d frames" % [_applies_since_log, _frames_since_log])
		_applies_since_log = 0
		_frames_since_log = 0


func _apply_input_regions() -> void:
	var regions: Array[Rect2i] = []
	if PIN_INPUT_REGION_TO_WINDOW:
		regions.append(Rect2i(Vector2i.ZERO, get_window().size))
	elif _click_through:
		regions = _collect_ui_rects()
	else:
		# Tracker asked for the whole window to be interactive.
		regions.append(Rect2i(Vector2i.ZERO, get_window().size))

	if regions == _last_regions:
		return
	_last_regions = regions
	_applies_since_log += 1
	DisplayServer.window_set_mouse_passthrough_regions(regions)


## Rects of every visible UI control, in window pixels. get_screen_transform()
## folds in the stretch scale and content scale factor, which global rects alone
## do not account for.
func _collect_ui_rects() -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var xform := get_viewport().get_screen_transform()

	for node in get_tree().get_nodes_in_group("UI"):
		var ctr := node as Control
		if ctr == null or not ctr.is_visible_in_tree():
			continue

		var rect := ctr.get_global_rect()

		# RSMain deliberately puts %split_chat in the UI group even though it is a
		# full-screen container, because only its drag grabber is interactive.
		# Taking its whole rect would claim the entire screen as input region and
		# nothing would pass through. Mirrors RSMouseTracker.is_m_pos_in_control_nodes.
		if ctr is HSplitContainer:
			if ctr.get_child_count() != 2:
				continue
			var ctr_left := ctr.get_child(0) as Control
			var ctr_right := ctr.get_child(1) as Control
			if ctr_left == null or ctr_right == null or not ctr_left.visible or not ctr_right.visible:
				continue
			rect.position.x = ctr_left.size.x
			rect.size.x -= ctr_left.size.x + ctr_right.size.x

		rect = xform * rect
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		rects.append(Rect2i(rect.abs()))

	for node in get_tree().get_nodes_in_group("UIWindows"):
		var win := node as Window
		if win == null or not win.visible:
			continue
		rects.append(Rect2i(win.get_position_with_decorations(), win.get_size_with_decorations()))

	return rects
