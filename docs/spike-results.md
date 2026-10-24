# Phase 1 spike results (2026-10-24)

Machine: niri 26.04, Quickshell 0.3.2 (Qt 6.11.2), DP-3 2560×1440 @ 165 Hz, VRR off,
RTX 2070 SUPER (driver 595.104.02, OpenGL ES 3.2 via Qt RHI).

## Snapshot → overlay

- The overlay can't be captured while unmapped until its window has been shown once:
  ScreencopyView's buffer manager needs the window's graphics context. Fix: map for 3
  transparent, click-through frames at startup ("warming"), then hide.
- Setting `captureSource` (null → screen) creates a fresh context that grabs one frame and
  flips `hasContent`; no explicit `captureFrame()` is needed (calling it right away fails with
  "no recording context is ready").
- The halves start at progress 0 on the first frame that is actually drawn, so the opening has
  no jump. Earlier the animation clock started at capture time and the first visible frame was
  already ~35% open.

## Render loop

| Render loop | Frames during 330 ms open | Worst frame |
|---|---|---|
| basic (Qt's default here) | 20 (60 fps) | 16.7 ms |
| threaded (`QSG_RENDER_LOOP=threaded`) | 55–56 (~166 fps) | 7–10 ms |

Qt picks the basic loop on this NVIDIA/Wayland setup. The daemon defaults to `threaded`
(it can still be overridden through the environment).

## Latency, keypress → first visible motion

| Command transport | Daemon reached after |
|---|---|
| `quickshell ipc call` | 44–55 ms (client startup) |
| `nc -NU $XDG_RUNTIME_DIR/shatterlock.sock` (Quickshell `SocketServer`) | 4–6 ms |

| Idle strategy | Capture | Map | Motion after keypress (socket) |
|---|---|---|---|
| Unmapped while idle, remap on open | 68–80 ms (waits for our first frame) | 53–61 ms | 72–86 ms |
| Stay mapped (transparent, click-through, no keyboard) | 19–28 ms | 0 | 23–33 ms |

## Shaders

- `ShaderEffect.fragmentShader` can be swapped at runtime.
- Qt caches by URL: recompiling into the same `.qsb` path keeps showing the old shader; a new
  path loads the new one. User shaders must compile to content-addressed filenames.
- `ShaderEffectSource.format` supports `RGBA16F` / `RGBA32F` in Qt 6.11. The crack field
  (signed distance, along-crack coordinate, branch distance) will be baked on the GPU once per
  crack into a float texture and sampled by all slot shaders.
- qsb errors map back to the user's own line numbers through the `#line` directives added by
  `scripts/wrap-shader`.

## Checked by eye

- Seamless: no flash or shift when the overlay replaces the live screen.
- niri binds still fire while the overlay holds exclusive keyboard focus (Mod+Escape opened
  DMS's power menu on top of the open rift), so a `toggle` bind works.

## Not yet verified

- Output scale ≠ 1 (to test in nested niri).

## Decisions taken from these results

- `"idle": "unmapped" | "mapped"` config option, default `unmapped` (no surface on screen between
  uses; `mapped` trades that for ~25 ms opens).
- `shatterlock toggle|open|close` write to `$XDG_RUNTIME_DIR/shatterlock.sock` with OpenBSD
  netcat (`nc -NU`), falling back to `quickshell ipc call` when the socket is missing.
- The daemon defaults to `QSG_RENDER_LOOP=threaded`.
- Default crack direction `bl-tr` (halves top-left and bottom-right).

## Live halves (patched niri)

Patched niri (`nix/niri/`), nested in a winit window, with the `hide-from-own-capture` rule and
`"live": true`:

- Quickshell's `ScreencopyView` captures over ext-image-copy-capture. With the rule, its own
  capture leaves the rift out: the halves show the screen beneath (a moving marker keeps moving in
  them), with no rift inside them. grim, a different client, still sees the rift.
- Frame pacing while opening is the same with live on and off (the nested window runs at ~110
  fps, so its 12 ms frames say nothing about 165 Hz).
- The first frame of a live open took ~20 ms nested, against < 9 ms for a snapshot open,
  probably the second capture buffer arriving. To measure on DP-3.
- The capture is off from the Lock press until unlock (checked through `stats.capturing`), and back on
  while the fog clears.

Not yet measured: the extra GPU time niri spends rendering the capture each frame, and the lag
of the halves behind the screen, on DP-3 at 165 Hz.
