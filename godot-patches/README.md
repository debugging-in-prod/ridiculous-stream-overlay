# Godot engine patches

The four commits that make the overlay work on Wayland, exported from
`4.6.1-stable`. Apply them to a clean Godot checkout to rebuild the engine this
project needs. See [`../LINUX.md`](../LINUX.md) for why each one is required and
what breaks without it.

```sh
git clone --filter=blob:none https://github.com/godotengine/godot.git
cd godot
git checkout -b layer-shell-4.6.1 4.6.1-stable
git am /path/to/godot-patches/*.patch
scons platform=linuxbsd target=editor arch=x86_64 wayland=yes x11=yes -j"$(nproc)"
```

| Patch | What it does |
|---|---|
| 0001 | Ports [PR #109875][pr] (wlr-layer-shell) onto 4.6.1; also implements `window_set_mouse_passthrough` via `wl_surface.set_input_region`, previously a stub |
| 0002 | Fixes a startup crash (`zxdg_exporter_v2_export_toplevel` on a layer surface is a protocol violation), adds output selection, and anchors full-output surfaces to all four edges |
| 0003 | Only accept the `wl_output.mode` flagged current — without it every screen query returns 640x480 on any compositor that advertises full mode lists |
| 0004 | Keeps `WindowData::wayland_layer` in step with the thread side, without which resizing and repositioning silently no-op on a layer surface |

Patch 0003 is unrelated to layer-shell and worth sending upstream on its own.

[pr]: https://github.com/godotengine/godot/pull/109875
