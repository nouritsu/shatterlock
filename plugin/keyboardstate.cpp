#include "keyboardstate.h"

#include <QGuiApplication>
#include <QtGui/qguiapplication_platform.h>

#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>

const wl_keyboard_listener KeyboardState::s_listener = {
    .keymap = [](void *data, wl_keyboard *, uint32_t format, int32_t fd, uint32_t size) {
        static_cast<KeyboardState *>(data)->keymap(format, fd, size);
    },
    .enter = [](void *, wl_keyboard *, uint32_t, wl_surface *, wl_array *) {},
    .leave = [](void *, wl_keyboard *, uint32_t, wl_surface *) {},
    .key = [](void *, wl_keyboard *, uint32_t, uint32_t, uint32_t, uint32_t) {},
    .modifiers = [](void *data, wl_keyboard *, uint32_t, uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t) {
        static_cast<KeyboardState *>(data)->modifiers(depressed | latched | locked);
    },
    .repeat_info = [](void *, wl_keyboard *, int32_t, int32_t) {},
};

KeyboardState::KeyboardState(QObject *parent)
    : QObject(parent) {
    auto *wayland = qGuiApp ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>() : nullptr;
    // Only on a seat with a keyboard: asking one without it is a protocol error.
    if (!wayland || !wayland->seat() || !wayland->keyboard())
        return;
    m_keyboard = wl_seat_get_keyboard(wayland->seat());
    wl_keyboard_add_listener(m_keyboard, &s_listener, this);
    wl_display_flush(wayland->display());
}

KeyboardState::~KeyboardState() {
    if (!m_keyboard)
        return;
    if (wl_keyboard_get_version(m_keyboard) >= WL_KEYBOARD_RELEASE_SINCE_VERSION)
        wl_keyboard_release(m_keyboard);
    else
        wl_keyboard_destroy(m_keyboard);
}

// Which modifier bit is Caps Lock's in this keymap (it is xkb's "Lock", nearly always bit 1).
void KeyboardState::keymap(uint32_t format, int32_t fd, uint32_t size) {
    if (format == WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        void *text = mmap(nullptr, size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (text != MAP_FAILED) {
            xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
            xkb_keymap *keymap = context ? xkb_keymap_new_from_string(context, static_cast<const char *>(text), XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS) : nullptr;
            if (keymap) {
                const xkb_mod_index_t caps = xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_CAPS);
                if (caps != XKB_MOD_INVALID)
                    m_capsMask = 1u << caps;
                xkb_keymap_unref(keymap);
            }
            if (context)
                xkb_context_unref(context);
            munmap(text, size);
        }
    }
    close(fd);
    update();
}

// The modifiers in effect (pressed, latched or locked): Caps Lock is on while Lock is one.
void KeyboardState::modifiers(uint32_t effective) {
    m_mods = effective;
    update();
}

void KeyboardState::update() {
    const bool on = (m_mods & m_capsMask) != 0;
    // Events may be dispatched off the GUI thread; QML reads this on it.
    QMetaObject::invokeMethod(this, [this, on] {
        if (on == m_capsLock)
            return;
        m_capsLock = on;
        emit capsLockChanged();
    });
}
