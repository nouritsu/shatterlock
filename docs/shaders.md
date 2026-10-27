# Custom shaders

The rift is drawn in three effect slots, each of which can be a built-in effect or your own
fragment shader:

| Slot | Drawn | Built-ins |
|---|---|---|
| `background` | under the halves; only the rift shows it | `void`, `image`, `surface` |
| `edge` | over the halves, around the broken edges | `glow`, `arcs`, `molten`, `glitch`, `elevation` |
| `opening` | only while the crack spreads and the halves part; post-processes the whole rift | `none`, `shards`, `glitch`, `molten` |

## Using one

Put the file in `~/.config/shatterlock/shaders/` and name it in `config.json` (or give an absolute
path):

```json
"fx": { "background": "aurora.frag", "edge": "glow", "opening": "none" }
```

or for one open only: `shatterlock open --background aurora.frag`.

The daemon compiles it on first use and **recompiles whenever the file changes**, so you can edit
with the rift open and watch. If it fails to compile, the slot falls back to its default, the
compiler errors go to the log (`quickshell log -p …`), and a thin red line runs down the middle of
the rift until it's fixed. `shatterlock compile file.frag` runs the same compiler and prints the
errors with line numbers from your file.

`"random"` picks a different entry from `fx.pool.<slot>` on every open; pools can mix built-ins
and your files. Expensive shaders can draw at reduced resolution with
`"fx": { "renderScale": { "background": 0.5 } }`.

## Writing one

A shader defines a single function and gets everything else from a prelude
(`src/shaders/prelude.glsl`, contract version 1):

```glsl
vec4 shade(vec2 uv)   // uv: 0..1 over the output; return premultiplied RGBA
```

Return alpha 0 with a non-zero colour to *add* light (good for edges); otherwise the result is
blended over what's below.

### Uniforms

| Name | Type | Meaning |
|---|---|---|
| `iTime` | float | seconds since the rift started opening |
| `iResolution` | vec2 | output size in logical pixels |
| `uProgress` | float | 0 closed … 1 open (overshoots past 1 briefly) |
| `uSpread` | float | 0 … 1, how far the hairline crack has run before the halves part |
| `uLine` | float | visibility of the hairline crack |
| `uPhase` | float | 0 idle, 1 spreading, 2 opening, 3 open, 4 closing, 5 running an action |
| `uGap` | float | current gap between the halves, px |
| `uOffA`, `uOffB` | vec2 | how far each half has moved, px |
| `uMouse` | vec2 | cursor position, px |
| `uHover` | float | highlighted action index, −1 for none |
| `uAccent`, `uVoid` | vec4 | theme colours (premultiplied); prefer `accent()`, which also turns red with wrong-password waves |
| `uSnapshot` | sampler2D | the screen: frozen, or live with `"live": true` |
| `uSdf` | sampler2D | the crack field (use the helpers below) |
| `uSource` | sampler2D | opening slot: the rift as composited so far |
| `uAlert`, `uAlertOn` | sampler2D, float | wrong-password waves on the lock screen, in screen space (r how red, g the wavefronts), and 1 while they are up |
| `uSeam` | float | how the crack is drawn: 0 a dark hairline (`"rift": {"seam": "crack"}`), 1 a sweeping accent-coloured line with clean edges (`"sweep"`) |
| `uAlertColor` | vec4 | what a wrong password turns things: red, or the theme's error colour with the Material lock screen (`accent()` already uses it) |

### Helpers

| Function | Returns |
|---|---|
| `riftDist(uv)` | signed distance to the nearest broken edge: > 0 inside the rift, < 0 on the halves |
| `riftUV(uv)` | rift coordinates: x along the crack 0 … 1, y across it −1 (one edge) … 1 (the other) |
| `snapshot(uv)` | the screen as displayed (each half moved; nearest edge inside the rift) |
| `crackAt(px)` | raw crack field of the closed screen (r distance, g along) |
| `toPx(uv)`, `toUv(px)` | convert between uv and pixels |
| `accent()` | accent colour at the pixel being shaded (red where a wrong-password wave has reached) |
| `hash12(p)`, `noise2(p)` | hash and value noise |

## Examples

`examples/shaders/` has one per slot: `aurora.frag` (background), `neon.frag` (edge) and
`ripple.frag` (opening). The built-ins in `src/shaders/builtin/` use the same contract.
