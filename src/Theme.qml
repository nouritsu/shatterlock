pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colours and fonts for the rift. With theme.accent "auto" the accent follows DankMaterialShell's current
// primary colour (dms-colors.json, watched for changes); otherwise it's the configured colour.
Singleton {
    id: root

    readonly property string dmsColorsPath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/DankMaterialShell/dms-colors.json"
    readonly property color fallbackAccent: "#cba6f7"

    property color dmsAccent: fallbackAccent

    readonly property string configured: Config.current.theme?.accent ?? "auto"
    readonly property color accent: configured === "auto" ? dmsAccent : configured
    readonly property color voidColor: Config.current.theme?.voidColor ?? "#05040a"

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
            const primary = data.colors?.[data.mode ?? "dark"]?.primary;
            if (primary)
                dmsAccent = primary;
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
