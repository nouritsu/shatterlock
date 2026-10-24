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

## Notes

- **Opening speed.** By default nothing of shatterlock is on screen between uses and an open takes
  ~80 ms to the first motion. `"idle": "mapped"` keeps an invisible, click-through surface mapped
  for ~25 ms opens, at the cost of niri not being able to scan fullscreen games out directly.
- **NVIDIA.** Qt chooses its basic render loop there, which caps animations at 60 fps; the daemon
  switches to the threaded loop. Set `QSG_RENDER_LOOP=basic` before `shatterlock daemon` if that
  ever misbehaves.
- **Live halves.** On stock niri the halves show a snapshot taken the frame before the rift opens:
  a client can't see the live screen beneath itself. Live halves need a niri patch (planned).
