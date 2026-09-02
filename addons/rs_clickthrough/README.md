# rs_clickthrough

A tiny GDExtension that gives the overlay window **real click-through on Windows**
by toggling `WS_EX_TRANSPARENT` on the native window handle — the one thing
Godot 4.6's built-in mouse passthrough can't do (the flag doesn't pass clicks;
the polygon clips rendering via `SetWindowRgn`). This is exactly what the old
`RSMousePass.cs` did. It's a **no-op on every non-Windows platform**, so the
Linux/Wayland run is unaffected (it uses input regions).

`RSMousePass` calls it on the non-Wayland path; if the extension isn't built it
logs a warning and falls back to the (ineffective) `FLAG_MOUSE_PASSTHROUGH`.

## One-time toolchain

```sh
sudo apt install scons g++ mingw-w64          # Linux host + Windows cross-compiler
```

## Build

From this directory (`addons/rs_clickthrough/`):

```sh
# 1. Get godot-cpp. There is no 4.6 branch yet, so use the newest release branch
#    (4.5). This extension only uses stable APIs, and a 4.5-built extension loads
#    fine in a 4.6.1 runtime (compatibility_minimum in the .gdextension is 4.3).
git clone -b 4.5 https://github.com/godotengine/godot-cpp

# 2. Windows (the one that matters) — cross-compiled from Linux:
scons platform=windows arch=x86_64 target=template_release use_mingw=yes
scons platform=windows arch=x86_64 target=template_debug   use_mingw=yes

# 3. Linux (no-op stub, so the editor/Linux export loads the extension cleanly):
scons platform=linux arch=x86_64 target=template_release
scons platform=linux arch=x86_64 target=template_debug
```

Outputs land in `bin/` with names that match `rs_clickthrough.gdextension`, e.g.
`librs_clickthrough.windows.template_release.x86_64.dll`.

## Use

1. Build the four libraries above.
2. Open the project in Godot once so it picks up `rs_clickthrough.gdextension`
   (the `RSClickThrough` class appears in the editor).
3. Export for Windows as usual — Godot bundles the `.dll` beside the exe (like the
   Rapier DLL), and `build-windows-zip.sh` already ships everything in `build/`.

The built `bin/*.dll` / `bin/*.so` **must be committed / present** for the export
to include them (same as the Rapier extension). `godot-cpp/` and SCons build
artifacts are gitignored.
