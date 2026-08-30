# Running Ridiculous Stream on Linux

This fork runs Ridiculous Stream on Linux. Getting the overlay to behave as an
overlay — rather than as an ordinary application window — takes more than a
build fix, so this document explains what the app needs from the window system,
what each display server actually provides, and why a patched Godot engine is
currently unavoidable on some desktops.

Everything below was established by testing on a COSMIC (Wayland) desktop with
Godot 4.6.1. Where behaviour is compositor-specific rather than universal, it is
called out.

---

## 1. The build fix: the app could not start at all

`classes/RSMousePass.cs` implemented click-through by P/Invoking `user32.dll`
(`SetWindowLong` with `WS_EX_LAYERED` / `WS_EX_TRANSPARENT`) and returned early
on every non-Windows platform.

That mattered more than it looks. `rs_main.tscn` is the autoload scene and
references that script, so on a **non-.NET Godot build the entire scene fails to
load** and the application does not start — rather than starting with
click-through disabled.

This fork replaces it with GDScript. Godot exposes the same capability natively
as `Window.FLAG_MOUSE_PASSTHROUGH`, implemented on Windows, macOS and X11. Since
it was the only `.cs` file in the project, the C# requirement is dropped
entirely and the project now runs on a stock (non-.NET) Godot build.

---

## 2. What the overlay needs from the window system

Three separate capabilities, all required simultaneously:

| | Purpose |
|---|---|
| **Per-pixel transparency** | the window is mostly empty; you must see through it |
| **Click-through** | clicks in empty areas must reach the game underneath |
| **Always-on-top** | it must render above a fullscreen game |

Missing any one makes it useless. Click-through without always-on-top is a
transparent window sitting *behind* your game. Always-on-top without
transparency is an opaque rectangle covering your screen.

---

## 3. What each display server actually provides

| | X11 / XWayland | Wayland (stock Godot) | Wayland (patched) |
|---|---|---|---|
| Transparency | ❌ on COSMIC¹ | ✅ | ✅ |
| Click-through | ✅ XShape | ❌ stubbed | ✅ input regions |
| Always-on-top | ❌ on COSMIC² | ❌ unimplemented | ✅ layer-shell |

¹ The window gets a depth-32 ARGB visual, but COSMIC's XWayland does not blend
it. Verified with a minimal project — a red circle on a transparent background
renders inside a black box. Note that **a depth-32 visual only proves an ARGB
visual was created, not that the compositor composites it.**

² COSMIC exposes no always-on-top capability to any client by any route: no such
request in its toplevel management protocol, no window rules, no keyboard
shortcut, and it silently drops `_NET_WM_STATE_ABOVE` from XWayland clients
while honouring the maximize states sent in the same `_NET_WM_STATE` message.
Other X11 window managers (GNOME, KDE) do honour `ABOVE`, so on those desktops
plain X11 may be sufficient and none of this is needed.

### Stock Godot's Wayland backend

As of 4.6, three relevant methods are unimplemented
(`platform/linuxbsd/wayland/display_server_wayland.cpp`):

- `window_set_mouse_passthrough()` — a `// TODO` stub
- `window_set_position()` — `// Unsupported with toplevels.`
- `WINDOW_FLAG_ALWAYS_ON_TOP` — absent from `window_set_flag()`'s switch

**These fail silently, and the API lies about it.** `Window.get_flag()` and
`Window.position` read back whatever you set, because the values are cached
before the backend ignores them. Nothing in the engine or the app reports a
problem. Budget for this if you are debugging Wayland window behaviour.

---

## 4. The fix: `zwlr_layer_shell_v1`

The Wayland protocol for surfaces that sit above (or below) normal windows.
It is what desktop panels, docks and on-screen displays use, and a surface on
its `overlay` layer is above everything regardless of workspace. Compositor
support is required — wlroots-based compositors, KDE and COSMIC implement it;
GNOME does not.

Godot has no layer-shell support upstream. [PR #109875][pr] implements it, and
this setup uses that PR **rebased onto 4.6.1 with five additional fixes**, all
found by running it:

1. **Crash on startup.** `window_create()` called
   `zxdg_exporter_v2_export_toplevel()` unconditionally. A layer surface holds a
   different role, so requesting a toplevel handle for one is a protocol
   violation; the compositor disconnects the client, which surfaces as
   "Can't show a GLES3 window" and then a segfault.

2. **Resizing did nothing.** The display server's `WindowData::wayland_layer`
   was only ever set by the script API, never by the project setting. Both
   `window_set_size()` and `window_set_position()` branch on it, so both took
   the xdg-toplevel path and silently no-opped. The window stayed at whatever
   size it was created with and only one configure event ever arrived.

3. **Wrong monitor, wrong geometry.** The layer surface was created with a null
   `wl_output`, letting the compositor pick. Added a `layer_screen` setting, and
   a surface covering the whole output is now anchored to all four edges with a
   zero size so the compositor sizes it, rather than deriving margins from a
   rect that Godot zeroes for toplevels anyway.

4. **Every screen query returned 640x480.** Unrelated to layer-shell and
   arguably the most broadly applicable fix: `wl_output.mode` may be sent once
   per *supported* mode, not just the active one — COSMIC sends 29 for a typical
   monitor, with the current one flagged second and 640x480 last. Godot's
   handler ignored the `flags` argument, so the last mode always won and
   `screen_get_size()` / `screen_get_usable_rect()` were wrong on every
   compositor that advertises full mode lists.

5. **Text boxes looked focused but keys went to the previous app.** Layer
   surfaces default to `keyboard_interactivity=none`, and the original bind
   used protocol v1, which cannot even ask for `on_demand`. Pointer events
   still arrived through the input region, so Godot's GUI drew a focus ring
   on a `LineEdit` while `wl_keyboard` stayed on the last focused toplevel.
   Binding v4 (clamped to what the compositor advertises) and setting
   `on_demand` makes click-to-focus / click-away work like a normal window.
   `exclusive` is not used: on the overlay layer it would steal keys from
   every other client for as long as the overlay is mapped.

[pr]: https://github.com/godotengine/godot/pull/109875

---

## 5. Building the patched engine

Requires roughly 10 GB of disk. A full build takes minutes; incremental
rebuilds take seconds.

```sh
# Debian/Ubuntu build dependencies
sudo apt install -y scons pkg-config libx11-dev libxcursor-dev libxinerama-dev \
    libxi-dev libxrandr-dev libwayland-dev wayland-protocols libudev-dev \
    libgl1-mesa-dev libglu1-mesa-dev libasound2-dev libpulse-dev \
    libdbus-1-dev libspeechd-dev libdecor-0-dev libfontconfig-dev libssl-dev

git clone --filter=blob:none https://github.com/godotengine/godot.git
cd godot
git checkout 4.6.1-stable
git fetch origin pull/109875/head:pr109875

# Apply the PR, then the four fixes above. servers/display_server.{cpp,h} moved
# to servers/display/ after the PR's base commit, so those hunks need
# retargeting, and the PR also deletes unrelated code added since — including
# the DEBUG_LOG_WAYLAND macro, which will not compile without it.

scons platform=linuxbsd target=editor arch=x86_64 wayland=yes x11=yes -j"$(nproc)"
```

Run the project with the resulting binary:

```sh
./bin/godot.linuxbsd.editor.x86_64 --path /path/to/ridiculous-stream-overlay
```

> **The user data directory differs between a native build and the Flatpak.**
> Native uses `~/.local/share/godot/app_userdata/Ridiculous Stream/`; the
> Flatpak uses `~/.var/app/org.godotengine.Godot/data/godot/app_userdata/...`.
> Settings configured under one are invisible to the other. Note that
> `settings.tres` holds your OBS WebSocket password — it is created
> world-readable, so `chmod 600` it.

---

## 6. Project settings

```ini
[display]
display_server/driver.linuxbsd="wayland"
window/wayland/layer=4          ; 0 Normal, 1 Background, 2 Bottom, 3 Top, 4 Overlay
window/wayland/layer_screen=-1  ; -1 = largest output, otherwise an output index
```

Layer-shell `Window.position` is **output-relative**: `(0, 0)` is the top-left of
the bound output. `screen_get_position()` is compositor-global, so a monitor to
the right of another reports `(2560, 0)`. Passing that through as the overlay's
position is treated as a 2560px inset from the ultrawide's own left edge, and
the window hangs off the right. `RSDisplay` and
`RSUtl.fit_and_center_window_to_display()` therefore use `(0, 0)` when the
patched engine is hosting the overlay.

`RSDisplay.supports_desktop_overlay()` probes for the patched engine via
`ClassDB.class_has_integer_constant("DisplayServer", "FEATURE_WAYLAND_LAYER_SHELL")`
rather than referencing the constant directly, so **the project still runs on a
stock Godot** — it falls back to an ordinary window meant to be captured by OBS.

---

## 7. Click-through works differently on Wayland

The original design polls the cursor every frame and switches whole-window
passthrough off when it is over UI. That relies on asking the OS where the
pointer is regardless of which window it is over — `GetCursorPos()` on Windows,
the X server on X11.

**Wayland has no such query, by design.** A surface that passes clicks through
receives no pointer events at all, so the app can never learn the cursor has
reached its menu, and can never switch input back on. The toggle is one-way and
the overlay becomes permanently unclickable.

So on Wayland this fork inverts the model: it declares the interactive
rectangles up front as the surface's input region via
`wl_surface.set_input_region`. The compositor routes clicks landing inside them
to the app and passes everything else through, and pointer events over the UI
arrive normally. This needs
`DisplayServer.window_set_mouse_passthrough_regions()`, added in the patched
build — Godot's existing `window_set_mouse_passthrough()` takes a single polygon,
whereas the UI is several disjoint panels.

One subtlety worth knowing if you touch this: `RSMain` deliberately adds
`%split_chat` to the `UI` group even though it is a full-screen
`HSplitContainer`, because only its drag grabber is interactive. Taking its whole
rect claims the entire screen as input region and nothing passes through
anywhere.

---

## 8. Known limitations

- **A strip under the desktop panel is not covered.** Layer surfaces respect
  other surfaces' exclusive zones by default. `set_exclusive_zone(-1)` would
  claim the full output including beneath the panel.
- **`NoOBSWS` and `RSCustom` hardcode source names** from the original author's
  OBS layout — inputs `Mic/Aux` and `Brave`, filter `main_desk`/`Blur`, scene
  `Overlay Stream`/`BRB_text`. Names that do not exist in your scene collection
  now log a warning naming the missing source instead of crashing, but the
  corresponding buttons will not do anything.
- **The engine is a fork you maintain.** Every Godot update means re-basing.
- **GNOME on Wayland does not implement layer-shell**, so this approach will not
  work there. On GNOME or KDE under X11, always-on-top works natively and the
  patched engine may be unnecessary.

---

## 9. Worth sending upstream

Two changes here are independent of this project and fix bugs anyone can hit:

- The **`wl_output.mode` filter** — a one-line fix; without it every screen query
  is wrong on any compositor that advertises full mode lists.
- The **`NoOBSWS` getter crash** — OBS omits `responseData` when a request fails,
  and all six getters dereferenced it unconditionally, so any source name absent
  from the user's scene collection raised a script error from inside the socket
  poll. This is reachable out of the box, since the hardcoded names above do not
  exist in a fresh OBS install.
