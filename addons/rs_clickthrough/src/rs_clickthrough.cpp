#include "rs_clickthrough.h"

#include <godot_cpp/core/class_db.hpp>

#ifdef _WIN32
#include <windows.h>
#endif

using namespace godot;

void RSClickThrough::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_click_through", "window_handle", "enabled"), &RSClickThrough::set_click_through);
	ClassDB::bind_method(D_METHOD("is_supported"), &RSClickThrough::is_supported);
}

void RSClickThrough::set_click_through(int64_t window_handle, bool enabled) {
#ifdef _WIN32
	HWND hwnd = reinterpret_cast<HWND>(static_cast<intptr_t>(window_handle));
	if (hwnd == nullptr) {
		return;
	}
	LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
	if (enabled) {
		// WS_EX_TRANSPARENT makes the window invisible to hit-testing (clicks fall
		// through). WS_EX_LAYERED is required for it and is already set for the
		// per-pixel-transparent overlay; OR it in defensively.
		ex |= (WS_EX_LAYERED | WS_EX_TRANSPARENT);
	} else {
		// Clear only TRANSPARENT so the window is interactive again. Never clear
		// LAYERED -- the overlay's transparency depends on it.
		ex &= ~static_cast<LONG_PTR>(WS_EX_TRANSPARENT);
	}
	SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex);
#else
	(void)window_handle;
	(void)enabled;
#endif
}

bool RSClickThrough::is_supported() const {
#ifdef _WIN32
	return true;
#else
	return false;
#endif
}
