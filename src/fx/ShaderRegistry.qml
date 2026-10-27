pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Resolves the effect slots (background, edge, opening) to what draws them: a built-in shader, the
// image background, shards, or a custom shader from ~/.config/shatterlock/shaders. Custom shaders
// are compiled when the config mentions them and rebuilt whenever their file changes; one that
// fails to build falls back to the slot's default and raises `failed`.
Scope {
    id: registry

    readonly property string userDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/shatterlock/shaders"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/shatterlock/qsb"

    // Built-ins per slot: name → compiled shader in shaders/qsb, or a non-shader kind.
    readonly property var builtins: ({
            background: {
                void: "void",
                image: "#image",
                surface: "#surface"
            },
            edge: {
                glow: "glow",
                arcs: "arcs",
                molten: "molten",
                glitch: "glitch_edge",
                elevation: "elevation"
            },
            opening: {
                none: "#none",
                shards: "#shards",
                glitch: "glitch_tear",
                molten: "molten_tear"
            }
        })
    readonly property var fallback: ({
            background: "void",
            edge: "glow",
            opening: "none"
        })

    // Built-in shader URLs, for warming their pipelines up at startup.
    readonly property var builtinUrls: Object.values(builtins).reduce((all, slot) => all.concat(Object.values(slot)), []).filter(f => !f.startsWith("#")).map(f => shaderUrl(f))

    // Custom shader path → { url, error, building }
    property var builds: ({})
    // Every custom shader file the config mentions (slots and pools).
    property var watched: []

    function shaderUrl(file) {
        return Qt.resolvedUrl(`../shaders/qsb/${file}.qsb`);
    }

    function isCustom(name) {
        return typeof name === "string" && name.endsWith(".frag");
    }

    function pathFor(name) {
        return name.startsWith("/") ? name : `${userDir}/${name}`;
    }

    function valid(slot, name) {
        return Object.prototype.hasOwnProperty.call(builtins[slot], name) || isCustom(name);
    }

    function track(fx) {
        const names = [fx.background, fx.edge, fx.opening, ...(fx.pool?.background ?? []), ...(fx.pool?.edge ?? []), ...(fx.pool?.opening ?? [])];
        const paths = [...new Set(names.filter(isCustom).map(pathFor))];
        if (JSON.stringify(paths) !== JSON.stringify(watched))
            watched = paths;
    }

    // What a slot shows for one open; "random" draws from the slot's pool.
    function choose(slot, fx) {
        let name = fx[slot];
        if (name === "random") {
            const pool = (fx.pool?.[slot] ?? []).filter(n => valid(slot, n));
            name = pool.length > 0 ? pool[Math.floor(Math.random() * pool.length)] : fallback[slot];
        }
        if (!valid(slot, name)) {
            console.warn(`shatterlock: unknown ${slot} effect "${name}", using "${fallback[slot]}"`);
            name = fallback[slot];
        }
        if (isCustom(name) && !watched.includes(pathFor(name)))
            watched = [...watched, pathFor(name)];
        return name;
    }

    // { kind: "shader" | "image" | "surface" | "shards" | "none", url, failed }. Callers pass
    // `builds` so their bindings re-evaluate when a custom shader finishes (re)building.
    function lookup(slot, name, buildsNow) {
        if (isCustom(name)) {
            const b = buildsNow[pathFor(name)];
            if (b?.url && !b.error)
                return {
                    kind: "shader",
                    url: b.url,
                    failed: false
                };
            const fb = lookup(slot, fallback[slot], buildsNow);
            fb.failed = !!b?.error;
            return fb;
        }
        const file = builtins[slot][name] ?? builtins[slot][fallback[slot]];
        if (file.startsWith("#"))
            return {
                kind: file.slice(1),
                failed: false
            };
        return {
            kind: "shader",
            url: shaderUrl(file),
            failed: false
        };
    }

    function setBuild(path, state) {
        const next = Object.assign({}, builds);
        next[path] = Object.assign({}, next[path] ?? {}, state);
        builds = next;
    }

    Variants {
        model: registry.watched

        Scope {
            id: entry

            required property string modelData

            function build() {
                registry.setBuild(modelData, {
                    building: true
                });
                compiler.running = false;
                compiler.running = true;
            }

            FileView {
                path: entry.modelData
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: entry.build()
                onLoadFailed: {
                    console.warn(`shatterlock: shader ${entry.modelData} not found`);
                    registry.setBuild(entry.modelData, {
                        error: "file not found",
                        building: false
                    });
                }
            }

            Process {
                id: compiler
                command: [Quickshell.shellPath("../scripts/compile-shader"), entry.modelData, registry.cacheDir]
                stdout: StdioCollector {
                    id: built
                }
                stderr: StdioCollector {
                    id: errors
                }
                onExited: code => {
                    if (code === 0) {
                        console.info(`shatterlock: built ${entry.modelData}`);
                        registry.setBuild(entry.modelData, {
                            url: "file://" + built.text.trim(),
                            error: "",
                            building: false
                        });
                    } else {
                        const message = errors.text.trim() || `exited with status ${code}`;
                        console.warn(`shatterlock: ${entry.modelData} failed to build:\n${message}`);
                        registry.setBuild(entry.modelData, {
                            error: message,
                            building: false
                        });
                    }
                }
            }
        }
    }
}
