extends Node
class_name RSMousePass

## Cross-platform replacement for the original Windows-only RSMousePass.cs,
## which P/Invoked user32.dll (SetWindowLong / WS_EX_TRANSPARENT) and returned
## early on every non-Windows platform.
##
## Godot exposes whole-window click-through natively as
## Window.FLAG_MOUSE_PASSTHROUGH. It is implemented on Windows, macOS and X11.
## The Wayland backend still stubs window_set_mouse_passthrough and ignores the
## flag entirely as of Godot 4.6 (platform/linuxbsd/wayland/
## display_server_wayland.cpp), so on a Wayland session this degrades to a
## no-op and the overlay behaves as an ordinary window.

static var _log: TwitchLogger = TwitchLogger.new(&"RSMousePass")

var supported := false


func _ready() -> void:
	supported = DisplayServer.get_name() != "Wayland"
	if not supported:
		_log.i("[RSMousePass] click-through is not implemented on the %s display server; running as an ordinary window" % DisplayServer.get_name())


## Named in PascalCase to stay signal-compatible with the C# original, which
## RSMouseTracker.mouse_track_updated connects to directly.
func SetClickThrough(clickthrough: bool) -> void:
	if not supported:
		return
	get_window().set_flag(Window.FLAG_MOUSE_PASSTHROUGH, clickthrough)
