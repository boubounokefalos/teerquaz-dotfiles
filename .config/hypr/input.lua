-- Keyboard, mouse and touchpad. Written by Shell Settings → Keyboard & mouse
-- (edits made here by hand are kept until the next change there).
hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_options = "grp:alt_shift_toggle,terminate:ctrl_alt_bksp",
        repeat_rate = 25,
        repeat_delay = 600,
        numlock_by_default = false,
        follow_mouse = 1,
        sensitivity = 0,
        accel_profile = "adaptive",
        natural_scroll = false,
        scroll_factor = 1,
        left_handed = false,
        touchpad = {
            natural_scroll = false,
            tap_to_click = true,
            disable_while_typing = true,
            scroll_factor = 1,
        },
    },
})
