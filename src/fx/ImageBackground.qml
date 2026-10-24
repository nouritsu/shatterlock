pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell

// Background slot "image": a picture (static, or animated GIF/WebP) behind the rift, optionally
// blurred and darkened. "parallax" crops like "cover" and drifts a little with the cursor.
Item {
    id: bg

    required property var rift
    property var options: ({}) // config fx.image: { path, fit, blur, darken }

    readonly property string path: {
        const p = options.path ?? "";
        return p.startsWith("~/") ? Quickshell.env("HOME") + p.slice(1) : p;
    }
    readonly property string fit: options.fit ?? "cover"
    readonly property real drift: fit === "parallax" ? 28 : 0
    readonly property bool animated: /\.(gif|webp|apng)$/i.test(path)

    anchors.fill: parent

    Loader {
        id: picture
        width: bg.width + 2 * bg.drift
        height: bg.height + 2 * bg.drift
        x: -bg.drift + (bg.rift.mouse.x >= 0 ? bg.drift * (0.5 - bg.rift.mouse.x / bg.width) * 2 : 0)
        y: -bg.drift + (bg.rift.mouse.y >= 0 ? bg.drift * (0.5 - bg.rift.mouse.y / bg.height) * 2 : 0)
        visible: (bg.options.blur ?? 0) <= 0
        sourceComponent: bg.animated ? animatedPicture : stillPicture
    }

    Component {
        id: stillPicture
        Image {
            source: bg.path ? "file://" + bg.path : ""
            fillMode: bg.fit === "contain" ? Image.PreserveAspectFit : bg.fit === "tile" ? Image.Tile : Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(bg.width, bg.height)
            onStatusChanged: if (status === Image.Error)
                console.warn(`shatterlock: can't load background image ${bg.path}`)
        }
    }

    Component {
        id: animatedPicture
        AnimatedImage {
            source: bg.path ? "file://" + bg.path : ""
            fillMode: bg.fit === "contain" ? Image.PreserveAspectFit : bg.fit === "tile" ? Image.Tile : Image.PreserveAspectCrop
            asynchronous: true
            playing: bg.rift.phase !== "idle"
        }
    }

    MultiEffect {
        anchors.fill: picture
        source: picture.item
        visible: (bg.options.blur ?? 0) > 0
        blurEnabled: true
        blur: Math.min(1, bg.options.blur ?? 0)
        blurMax: 64
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: bg.options.darken ?? 0.4
    }
}
