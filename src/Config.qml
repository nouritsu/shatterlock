pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The effective configuration, in layers: config/default.json, then the preset for the chosen "style"
// (config/presets/<style>.json, only the keys it changes), then settings baked into the package
// (SHATTERLOCK_SETTINGS, see nix/package.nix), then the user's config.json, which is watched and
// re-read on change. resolve(overrides) layers one open's CLI flags on top.
//
// Bad input never breaks the shell: unknown keys and wrongly typed values are logged and fall back
// to the default; a config.json that fails to parse keeps the last good configuration.
Singleton {
    id: root

    readonly property string userPath: Quickshell.env("SHATTERLOCK_CONFIG") || ((Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/shatterlock/config.json")
    readonly property string packagedPath: Quickshell.env("SHATTERLOCK_SETTINGS") ?? ""

    property var defaults: ({})
    property var current: ({})
    property bool ready: false

    // The parsed layers the current config was built from, kept so one open can pick another style.
    property var layers: ({})

    // Keys whose values must be one of these.
    readonly property var choices: ({
            "style": ["rift", "material"],
            "rift.corners": ["bl-tr", "tl-br"],
            "rift.shape": ["jagged", "wave"],
            "rift.seam": ["crack", "sweep"],
            "menu.buttons": ["glow", "material"],
            "animation.easing": ["rift", "material"],
            "idle": ["unmapped", "mapped"],
            "lock.blur": ["void", "frosted", "glass", "scrim"],
            "motion": ["full", "reduced"]
        })

    // Objects that may gain new keys (e.g. user-defined actions).
    readonly property var openMaps: ["actionDefs"]

    signal reloaded

    function reload() {
        defaultsFile.reload();
        materialFile.reload();
        packagedFile.reload();
        userFile.reload();
    }

    // Returns a copy of the current config with dotted-path overrides applied,
    // e.g. {"rift.seed": "random", "fx.edge": "arcs", "dryRun": true}. A "style" override rebuilds
    // it from the layers with that style's preset.
    function resolve(overrides) {
        const style = overrides?.style;
        let cfg;
        if (style !== undefined && style !== current.style) {
            if (choices.style.includes(style)) {
                cfg = sanitize(compose(style));
            } else {
                console.warn(`shatterlock: override "style" must be one of ${choices.style.join(", ")}, ignored`);
                cfg = clone(current);
            }
        } else {
            cfg = clone(current);
        }
        for (const key of Object.keys(overrides ?? {})) {
            if (key === "style")
                continue;
            const path = key.split(".");
            let parent = cfg;
            for (let i = 0; i < path.length - 1 && parent; i++)
                parent = isObject(parent[path[i]]) ? parent[path[i]] : null;
            const leaf = path[path.length - 1];
            if (!parent || !(leaf in parent)) {
                console.warn(`shatterlock: unknown override "${key}", ignored`);
                continue;
            }
            if (!compatible(parent[leaf], overrides[key], key)) {
                console.warn(`shatterlock: override "${key}" has the wrong type, ignored`);
                continue;
            }
            parent[leaf] = overrides[key];
        }
        return sanitize(cfg);
    }

    function rebuild() {
        let defs;
        try {
            defs = JSON.parse(defaultsFile.text());
        } catch (e) {
            console.error(`shatterlock: built-in defaults are broken: ${e.message}`);
            return;
        }

        const packaged = parse(packagedFile, packagedPath);
        const user = parse(userFile, userPath);
        if (packaged === null || user === null)
            return;
        let material;
        try {
            material = JSON.parse(materialFile.text());
        } catch (e) {
            console.error(`shatterlock: the material preset is broken: ${e.message}`);
            material = {};
        }

        defaults = defs;
        layers = {
            defs: defs,
            presets: {
                material: material
            },
            packaged: packaged,
            user: user
        };
        current = sanitize(compose(styleOf(user) ?? styleOf(packaged) ?? defs.style));
        ready = true;
        reloaded();
    }

    function styleOf(layer) {
        return isObject(layer) && typeof layer.style === "string" ? layer.style : undefined;
    }

    // The config for a style: defaults, that style's preset, packaged settings, the user's file.
    // (An unknown style is reported by sanitize and falls back to the default's.)
    function compose(style) {
        let cfg = layers.defs;
        const preset = layers.presets?.[style];
        if (preset)
            cfg = merge(cfg, preset, "");
        cfg = merge(merge(cfg, layers.packaged, ""), layers.user, "");
        cfg.style = style;
        return cfg;
    }

    // A layer's JSON: {} when absent or empty, null (keep the previous config) when it doesn't parse.
    function parse(file, path) {
        const raw = path && file.loaded ? file.text() : "";
        if (raw.trim() === "")
            return {};
        try {
            return JSON.parse(raw);
        } catch (e) {
            console.error(`shatterlock: ${path}: ${e.message}; keeping the previous config`);
            return null;
        }
    }

    function merge(base, over, prefix) {
        const out = clone(base);
        if (!isObject(over)) {
            console.warn(`shatterlock: config${prefix ? " key \"" + prefix + "\"" : ""} must be an object, ignored`);
            return out;
        }
        for (const key of Object.keys(over)) {
            const path = prefix ? `${prefix}.${key}` : key;
            if (!(key in base)) {
                if (openMaps.includes(prefix))
                    out[key] = over[key];
                else
                    console.warn(`shatterlock: unknown config key "${path}", ignored`);
                continue;
            }
            if (isObject(base[key]))
                out[key] = merge(base[key], over[key], path);
            else if (compatible(base[key], over[key], path))
                out[key] = over[key];
            else
                console.warn(`shatterlock: config key "${path}" should be ${describe(base[key])}, using the default`);
        }
        return out;
    }

    // Enum checks and cross-references that a plain type check can't express.
    function sanitize(cfg) {
        for (const path of Object.keys(choices)) {
            const keys = path.split(".");
            let parent = cfg;
            for (let i = 0; i < keys.length - 1; i++)
                parent = parent[keys[i]];
            const leaf = keys[keys.length - 1];
            if (!choices[path].includes(parent[leaf])) {
                console.warn(`shatterlock: "${path}" must be one of ${choices[path].join(", ")}; got "${parent[leaf]}"`);
                parent[leaf] = lookup(defaults, path);
            }
        }
        for (const id of Object.keys(cfg.actionDefs)) {
            const def = cfg.actionDefs[id];
            if (!["instant", "hold"].includes(def.confirm)) {
                console.warn(`shatterlock: actionDefs.${id}.confirm must be "instant" or "hold"; using "hold"`);
                def.confirm = "hold";
            }
            if (!["vanish", "stay"].includes(def.after)) {
                if (def.after !== undefined)
                    console.warn(`shatterlock: actionDefs.${id}.after must be "vanish" or "stay"; using "stay"`);
                def.after = "stay";
            }
            if (typeof def.color !== "string") {
                if (def.color !== undefined)
                    console.warn(`shatterlock: actionDefs.${id}.color must be a colour; using the accent`);
                def.color = "";
            }
        }
        cfg.actions = cfg.actions.filter(id => {
            const def = cfg.actionDefs[id];
            if (!def) {
                console.warn(`shatterlock: action "${id}" has no entry in actionDefs, skipped`);
                return false;
            }
            if (!Array.isArray(def.command) || def.command.length === 0 || !def.command.every(a => typeof a === "string")) {
                console.warn(`shatterlock: actionDefs.${id}.command must be a non-empty list of strings, skipped`);
                return false;
            }
            return true;
        });
        return cfg;
    }

    function compatible(base, value, path) {
        if (path === "rift.seed")
            return typeof value === "number" || value === "random";
        if (Array.isArray(base))
            return Array.isArray(value);
        return typeof base === typeof value && !isObject(value) && !Array.isArray(value);
    }

    function describe(value) {
        return Array.isArray(value) ? "a list" : `a ${typeof value}`;
    }

    function lookup(obj, path) {
        return path.split(".").reduce((o, k) => o?.[k], obj);
    }

    function isObject(v) {
        return v !== null && typeof v === "object" && !Array.isArray(v);
    }

    function clone(v) {
        return JSON.parse(JSON.stringify(v));
    }

    FileView {
        id: defaultsFile
        path: Quickshell.shellPath("../config/default.json")
        blockLoading: true
        onLoaded: rebuildSoon.restart()
    }

    FileView {
        id: materialFile
        path: Quickshell.shellPath("../config/presets/material.json")
        blockLoading: true
        onLoaded: rebuildSoon.restart()
    }

    FileView {
        id: packagedFile
        path: root.packagedPath
        printErrors: false
        onLoaded: rebuildSoon.restart()
        onLoadFailed: rebuildSoon.restart()
    }

    FileView {
        id: userFile
        path: root.userPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: rebuildSoon.restart()
        onLoadFailed: rebuildSoon.restart()
    }

    // Both files report in separately (and editors often write twice); rebuild once.
    Timer {
        id: rebuildSoon
        interval: 100
        onTriggered: root.rebuild()
    }
}
