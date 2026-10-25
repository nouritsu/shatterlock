import QtQuick
import Shatterlock.Keyboard

// Caps Lock as the compositor has it (plugin/), in a file of its own: LockInfo loads it, so the
// shell still starts without the plugin, just without Caps Lock.
QtObject {
    readonly property bool on: KeyboardState.capsLock
}
