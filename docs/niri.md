# Setting shatterlock up with niri

## Install

shatterlock is a plain package; settings can be baked into it with `.override`:

```nix
# flake.nix
inputs.shatterlock = {
  url = "path:/home/you/Projects/shatterlock"; # or a git URL
  inputs.nixpkgs.follows = "nixpkgs";
};

# wherever you define packages (here: flake-parts perSystem)
packages.shatterlock = inputs'.shatterlock.packages.default.override {
  settings = {
    # DankMaterialShell: lock through DMS (its logind integration is off by default)
    actionDefs.lock.command = [ "dms" "ipc" "call" "lock" "lock" ];
    fx.background = "${./shaders/aurora.frag}"; # custom shaders as store paths
  };
};
```

Baked settings sit between the built-in defaults and `~/.config/shatterlock/config.json`, which
still layers on top (and is re-read live) for quick experiments.

## The lock screen

shatterlock authenticates through its own PAM service and won't lock without it (it runs the Lock
action's `command` instead), so add it to your NixOS config:

```nix
security.pam.services.shatterlock = {};
```

For a fingerprint reader, also add a fingerprint-only service; shatterlock runs it alongside the
password:

```nix
security.pam.services.shatterlock-fingerprint = { unixAuth = false; fprintAuth = true; };
```

Locking happens from the rift's Lock button, `shatterlock lock`, logind (`loginctl lock-session`),
before suspend (`lock.beforeSleep`), and after `lock.idle.ac` / `lock.idle.battery` idle seconds.
Turn the same things off in whatever locked before (for DankMaterialShell: `acLockTimeout` and
`batteryLockTimeout` 0, `lockBeforeSuspend` false), or two lockers will race.

`shatterlock lock --preview` shows the lock screen and checks a password without locking anything.

## Start the daemon

In niri:

```kdl
spawn-at-startup "shatterlock" "daemon"
```

(`shatterlock daemon --foreground` suits a systemd user service.)

If it isn't running, the first `shatterlock open` or `toggle` starts it (that open takes about a
second longer).

## Bind it

```kdl
binds {
    // replaces DMS's power menu
    Mod+Escape { spawn "shatterlock" "toggle"; }

    // lock; allowed while locked, so if the locker ever dies this brings it back
    Mod+Shift+Escape allow-when-locked=true { spawn "shatterlock" "lock"; }

    // another bind can open a different rift for that press only
    Mod+Ctrl+Escape { spawn "shatterlock" "open" "--actions" "suspend,shutdown" "--edge" "arcs"; }
}
```

niri binds keep working while the rift holds the keyboard, so the same bind closes it again.

With niri-flake's `programs.niri.settings`:

```nix
programs.niri.settings = {
  spawn-at-startup = [ { command = [ "shatterlock" "daemon" ]; } ];
  binds."Mod+Escape".action.spawn = [ "shatterlock" "toggle" ];
};
```

## Live halves (niri patch)

On stock niri the halves are a snapshot taken the frame before the rift opens: a client can't
capture the screen beneath its own overlay without capturing the overlay too. `nix/niri/` holds a
niri patch adding a layer rule, `hide-from-own-capture`, that leaves a surface out of the captures
its own client makes (everyone else's screenshots and recordings still show it). With it,
shatterlock keeps capturing while the rift is up, and video keeps playing in both halves.

1. Patch niri. The flake's `overlays.niri` adds the patch to whatever `niri` your package set has,
   so put it after niri's own overlay:

   ```nix
   inputs.shatterlock.inputs.niri.follows = "niri"; # `nix flake check` there tests your niri

   nixpkgs.overlays = [
     inputs.niri.overlays.default
     inputs.shatterlock.overlays.niri
   ];
   ```

   (`packages.niri` is a patched niri from shatterlock's own pin, for trying it nested.)

2. Add the rule to your niri config:

   ```kdl
   layer-rule {
       match namespace="^shatterlock 
       hide-from-own-capture true
   }
   ```

3. Turn live mode on: `"live": true` in config.json, or `settings.live = true;` in the package
   override. Then restart niri (log out and back in) so the patched build runs.

Without the patch or the rule, live mode shows the rift inside its own halves; turn it off again.

The lock screen stays a snapshot: the halves freeze at the Lock press and come back to life once
you've unlocked. While the rift is open niri draws the screen a second time for every frame
shatterlock captures, and the halves trail the real screen by about a frame.

The patch is written against niri main (26.04, `f51d761`). When niri moves on and it no longer
applies, the niri build fails at its patch phase; `0002` is the matching wiki page, for upstream.

## Notes

- **Opening speed.** By default nothing of shatterlock is on screen between uses and an open takes
  ~80 ms to the first motion. `"idle": "mapped"` keeps an invisible, click-through surface mapped
  for ~25 ms opens, at the cost of niri not being able to scan fullscreen games out directly.
- **NVIDIA.** Qt chooses its basic render loop there, which caps animations at 60 fps; the daemon
  switches to the threaded loop. Set `QSG_RENDER_LOOP=basic` before `shatterlock daemon` if that
  ever misbehaves.
