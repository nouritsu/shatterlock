# shatterlock

A session menu for [niri](https://github.com/YaLTeR/niri) that tears your screen open. A jagged
crack races across it, the two halves part, and Lock, Suspend, Log Out, Reboot, Power Off,
Hibernate and Reboot-to-firmware sit in the rift. Esc, a click on either half, or your bind again
slams it shut and you're back.

Built on [Quickshell](https://quickshell.org) (QML + GLSL), run as a small resident daemon.

- Crack from a seed (stable layout) or `random`; bottom-left→top-right or top-left→bottom-right
- Two looks: the torn rift, or `"style": "material"` (Material Design: a smooth wave, sheets that
  lift with shadows, tonal icon buttons with a focus ring and a progress ring, M3 motion and DMS's
  Material colour roles)
- Three effect slots — **background** (`void`, `image`, `surface`), **edge** (`glow`, `arcs`,
  `molten`, `glitch`, `elevation`), **opening** (`none`, `shards`, `glitch`, `molten`) — each a
  built-in, your own GLSL, or `random` from a pool
- Custom shaders are compiled by the daemon and hot-reloaded when you save them
  ([docs/shaders.md](docs/shaders.md))
- Keyboard (arrows / Tab, Enter, and the letter keys of DankMaterialShell's power menu), mouse,
  and hold-to-confirm for the destructive actions; the compositor's key binds are suspended while
  the rift is up
- Follows DankMaterialShell's accent colour and font when it's there
- ~165 fps on a 1440p/165 Hz NVIDIA setup; ~80 ms from keypress to first motion

## Quick start

```sh
nix build                       # or add the flake to your config, see docs/niri.md
./result/bin/shatterlock daemon
./result/bin/shatterlock toggle
```

Bind `shatterlock toggle` in niri — [docs/niri.md](docs/niri.md).

## Commands

```
shatterlock daemon [--foreground]
shatterlock open|toggle [--style rift|material] [--actions a,b,c] [--seed N|random]
                        [--corners bl-tr|tl-br] [--width PX] [--background X] [--edge X]
                        [--opening X] [--dry-run]
shatterlock lock [--preview|--now]
shatterlock close | reload | status | stats | config [opts]
shatterlock compile <file.frag>
```

Flags apply to that one open. `--dry-run` logs commands instead of running them.

## Configuration

`~/.config/shatterlock/config.json`, merged over [config/default.json](config/default.json) and
re-read whenever it changes. Unknown keys and wrong types are logged and fall back to the default.

| Key | Default | |
|---|---|---|
| `style` | `rift` | `material` turns on the Material Design look: the settings in [config/presets/material.json](config/presets/material.json), under your own |
| `actions` | all seven | which actions to show, in order |
| `actionDefs.<id>` | | `label`, `icon` (Material Symbols name), `key`, `confirm` (`instant`/`hold`), `color` (Material buttons, while pressed; empty: the accent), `command` (argv), `after` (`vanish`: close then run; `stay`: show `status` while it runs), `requires` (logind `Can…` check). Add your own ids for custom actions. |
| `rift.corners` | `bl-tr` | crack direction |
| `rift.seed` | `1701` | number, or `random` for a new crack every time |
| `rift.width` | `170` | gap between the halves, px |
| `rift.jaggedness` | `0.6` | 0 … 1 |
| `rift.shape` | `jagged` | `wave`: a smooth wave (`rift.waveLength`, `rift.waveHeight` px), calm in the middle |
| `rift.seam` | `crack` | `sweep`: a line in the accent colour runs along it before the halves part, and their edges stay clean |
| `menu.buttons` | `glow` | `material`: icon buttons in tonal circles, no labels; pressed, one takes its action's `color`, and a held one counts down in place of its icon |
| `animation.*` | | `crackSpread`, `spreadMs`, `openMs`, `overshoot`, `closeMs`, `holdMs`, `easing` (`rift`, or `material`: Material Design's emphasized curves, no settle) |
| `fx.background` / `edge` / `opening` | `void` / `glow` / `none` | built-in, `file.frag`, or `random` |
| `fx.pool.<slot>` | | candidates for `random` |
| `fx.renderScale.<slot>` | `1` | draw a slot at reduced resolution |
| `fx.image` | | `path`, `fit` (`cover`/`contain`/`tile`/`parallax`), `blur` 0 … 1, `darken` 0 … 1 |
| `theme.accent` | `auto` | `auto` follows DankMaterialShell (its Material colour roles too), else a colour |
| `theme.voidColor`, `theme.font`, `theme.iconFont` | | |
| `lock.enabled` | `true` | Lock uses shatterlock's own lock screen (else the Lock action's `command`) |
| `lock.pamService` | `shatterlock` | PAM service; shatterlock won't lock unless `/etc/pam.d/<it>` exists |
| `lock.fingerprintService` | `shatterlock-fingerprint` | optional second PAM service run alongside, for fingerprint readers |
| `lock.blur` | `void` | how the screen is hidden while locked: `void` (dark fog), `frosted`, `glass` |
| `lock.waveMs`, `lock.width` | `900`, `250` | the blur wave's duration; the rift's width while locked |
| `lock.idle.ac` / `lock.idle.battery` | `0` | lock after this many idle seconds (0: never) |
| `lock.beforeSleep` | `true` | lock before suspend/hibernate (holds a logind delay inhibitor) |
| `lock.timeFormat`, `lock.dateFormat`, `lock.showUser`, `lock.showStatus`, `lock.showMedia` | | what the lock screen shows |
| `idle` | `unmapped` | `mapped` for faster opens (see docs/niri.md) |
| `live` | `false` | halves follow the live screen; needs the niri patch (see docs/niri.md) |
| `motion` | `full` | `reduced`: no overshoot, shake, spreading crack or opening effects |
| `dryRun` | `false` | log commands instead of running them |

## Development

```sh
nix develop                     # quickshell, qsb, qmllint, Material Symbols, the plugin's toolchain
./scripts/build-shaders
nix run .#dev                   # run the working tree in the foreground
nix flake check                 # builds the package, compiles every shader, applies the niri patch
```

The lock screen reads Caps Lock from the compositor through a small C++ QML module
(`plugin/`, `Shatterlock.Keyboard`): QML can't see the keyboard's lock state. The package, the dev
shell and `nix run .#dev` build it and put it on `QML_IMPORT_PATH`; without it shatterlock still
runs, just without the Caps Lock indicator.

`docs/spike-results.md` has the measurements behind the design (latency, frame pacing, why the
halves are a snapshot on stock niri).

## Status

Working: the rift, menu, actions, effects and custom shaders, packaging, the lock screen
(ext-session-lock + PAM, blur wave, idle and before-sleep locking), and live halves on a niri
with the `hide-from-own-capture` patch (`nix/niri/`).

MIT licence.
