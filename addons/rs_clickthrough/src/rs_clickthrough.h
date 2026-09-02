#pragma once

#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

// Native OS-level click-through for the desktop-overlay window.
//
// Godot 4.6's built-in mouse passthrough can't do what an overlay needs on
// Windows: FLAG_MOUSE_PASSTHROUGH does not pass clicks through, and the
// passthrough polygon uses SetWindowRgn which clips *rendering*. So we toggle
// WS_EX_TRANSPARENT directly (hit-test only, no render clip) -- exactly what the
// original RSMousePass.cs did. On every other platform this is a no-op; they use
// their own path (Wayland input regions / X11 / macOS).
class RSClickThrough : public RefCounted {
	GDCLASS(RSClickThrough, RefCounted)

protected:
	static void _bind_methods();

public:
	// Toggle click-through on the given native window handle
	// (DisplayServer.window_get_native_handle(WINDOW_HANDLE, id)). When enabled,
	// mouse events pass to whatever is beneath the window; the window keeps
	// rendering normally. Disabling makes the whole window interactive again.
	void set_click_through(int64_t window_handle, bool enabled);

	// True only where this extension actually does something (Windows).
	bool is_supported() const;
};

} // namespace godot
