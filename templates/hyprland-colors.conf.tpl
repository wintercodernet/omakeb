# omakeb — Hyprland colours, rendered from the active theme.
# Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
#
# Sourced by the generated hyprland.conf AFTER default/hypr/looknfeel.conf, so
# it overrides that file's colours and leaves its geometry alone. It is sourced
# BEFORE the user's own hyprland.conf, so a hand-written border colour wins.
#
# HYPRLANG TRUNCATES EVERY LINE AT AN UNESCAPED HASH.
# A hex colour written the CSS way does not error here — the line is silently
# cut short and Hyprland keeps whatever it had before, which is the worst
# possible failure mode for a theme switch. So not one colour below is written
# as hex: they are all rgb() and rgba(), and test/lint-theme.py fails the build
# if a hash ever appears in the rendered output anywhere but at the start of a
# comment line.
# (hyprlang config.cpp:688-716; a doubled hash is the escape for a literal one.)

general {
    col.active_border = {{ omakeb_border_active }}
    col.inactive_border = {{ omakeb_border_inactive }}
}

decoration {
    shadow {
        color = rgba({{ darker_background_strip }}88)
    }
}

group {
    col.border_active = rgb({{ green_strip }})
    col.border_inactive = {{ omakeb_border_inactive }}

    groupbar {
        text_color = rgb({{ bright_foreground_strip }})
        col.active = rgba({{ accent_strip }}cc)
        col.inactive = rgba({{ omakeb_surface_strip }}cc)
    }
}

misc {
    # Painted before hyprpaper has a wallpaper up, and wherever nothing else
    # has drawn yet. Matching the theme background is what stops a theme switch
    # from flashing the previous theme's colour on every reload.
    background_color = rgb({{ background_strip }})
}
