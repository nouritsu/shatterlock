pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colours and fonts for the rift. With theme.accent "auto" the accent follows DankMaterialShell's current
// primary colour (dms-colors.json, watched for changes); otherwise it's the configured colour.
//
// `roles` holds the Material 3 colour roles the material style draws with (primary,
// secondary_container, surface_container_lowest, …): DankMaterialShell's own for its current mode,
// or, with a fixed accent or without DMS, mixed from the accent and the void colour.
Singleton {
    id: root

    readonly property string dmsColorsPath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/DankMaterialShell/dms-colors.json"
    readonly property color fallbackAccent: "#cba6f7"

    property color dmsAccent: fallbackAccent
    property var dmsRoles: null

    readonly property string configured: Config.current.theme?.accent ?? "auto"
    readonly property color accent: configured === "auto" ? dmsAccent : configured
    readonly property color voidColor: Config.current.theme?.voidColor ?? "#05040a"

    readonly property var roles: configured === "auto" && dmsRoles ? Object.assign({}, derivedRoles, dmsRoles) : derivedRoles
    readonly property var derivedRoles: derive(accent, voidColor)

    function role(name) {
        return roles[name] ?? accent;
    }

    // Roles mixed from a single accent over a dark surface, for when DMS's aren't available.
    function derive(primary, base) {
        const mix = (a, b, t) => Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
        const white = Qt.rgba(1, 1, 1, 1);
        const surface = mix(base, primary, 0.06);
        return {
            primary: primary,
            on_primary: base,
            primary_container: mix(base, primary, 0.38),
            on_primary_container: mix(primary, white, 0.85),
            secondary: mix(primary, white, 0.3),
            secondary_container: mix(surface, white, 0.12),
            on_secondary_container: mix(primary, white, 0.8),
            surface: surface,
            surface_container_lowest: mix(base, primary, 0.03),
            on_surface: mix(primary, white, 0.85),
            on_surface_variant: mix(primary, white, 0.6),
            inverse_surface: mix(primary, white, 0.88),
            inverse_on_surface: mix(base, primary, 0.25),
            error: "#f2b8b5"
        };
    }

    // Material Symbols, loaded from the path the flake provides, else by family name if installed.
    readonly property string iconFamily: iconFont.status === FontLoader.Ready ? iconFont.name : (Config.current.theme?.iconFont ?? "Material Symbols Rounded")
    readonly property string labelFamily: (Config.current.theme?.font ?? "") || dmsFont || "sans-serif"
    property string dmsFont: ""

    FontLoader {
        id: iconFont
        source: Quickshell.env("SHATTERLOCK_ICON_FONT") ? "file://" + Quickshell.env("SHATTERLOCK_ICON_FONT") : ""
    }

    function readDms() {
        try {
            const data = JSON.parse(dmsFile.text());
            const scheme = data.colors?.[data.mode ?? "dark"];
            if (scheme?.primary)
                dmsAccent = scheme.primary;
            if (scheme && typeof scheme === "object") {
                const roles = {};
                for (const key of Object.keys(scheme)) {
                    if (typeof scheme[key] === "string")
                        roles[key] = scheme[key];
                }
                dmsRoles = roles;
            }
        } catch (e) {}
    }

    function readDmsSettings() {
        try {
            dmsFont = JSON.parse(dmsSettings.text()).fontFamily ?? "";
        } catch (e) {}
    }

    FileView {
        id: dmsSettings
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/DankMaterialShell/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readDmsSettings()
    }

    FileView {
        id: dmsFile
        path: root.dmsColorsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readDms()
    }
}
