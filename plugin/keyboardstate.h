#pragma once

#include <QObject>
#include <cstdint>
#include <QtQml/qqmlregistration.h>

struct wl_keyboard;
struct wl_keyboard_listener;

// The compositor's keyboard lock state, for the lock screen: QML has no way to read Caps Lock.
// It listens on a wl_keyboard of its own on Qt's seat; the compositor keeps that up to date (its
// modifiers) whenever one of the process's surfaces has keyboard focus, as the lock screen
// does. No LEDs and no input devices, so it works on any compositor and keyboard.
class KeyboardState : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool capsLock READ capsLock NOTIFY capsLockChanged)
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit KeyboardState(QObject *parent = nullptr);
    ~KeyboardState() override;

    bool capsLock() const { return m_capsLock; }
    // Whether it is listening at all (a Wayland session with a keyboard).
    bool available() const { return m_keyboard != nullptr; }

signals:
    void capsLockChanged();

private:
    static const wl_keyboard_listener s_listener;

    void keymap(uint32_t format, int32_t fd, uint32_t size);
    void modifiers(uint32_t effective);
    void update();

    wl_keyboard *m_keyboard = nullptr;
    uint32_t m_capsMask = 1u << 1; // xkb's Lock modifier, until the keymap says otherwise
    uint32_t m_mods = 0;
    bool m_capsLock = false;
};
