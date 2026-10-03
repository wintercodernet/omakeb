# omakeb — hyprlock configuration, rendered from the active theme.
# Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
#
# Entirely ours. Upstream has had no hyprlock template for a year — its lock
# screen is a Quickshell surface — and the hyprlock.conf files community themes
# still ship are Omarchy v1 leftovers carrying their own layout. We take the
# palette and render the rest (D11).
#
# hyprlang again: every colour is rgba(), never a CSS hex. See the note in
# hyprland-colors.conf.tpl for what a stray hash does to a line.

general {
    hide_cursor = true
    grace = 0
    ignore_empty_input = true
}

background {
    color = rgba({{ darker_background_strip }}ff)
    blur_passes = 0
}

input-field {
    size = 320, 48
    position = 0, -60
    halign = center
    valign = center

    outline_thickness = 2
    dots_size = 0.26
    dots_spacing = 0.3
    dots_center = true

    outer_color = rgba({{ accent_strip }}ff)
    inner_color = rgba({{ dark_background_strip }}ff)
    font_color = rgba({{ foreground_strip }}ff)
    check_color = rgba({{ green_strip }}ff)
    fail_color = rgba({{ omakeb_urgent_strip }}ff)

    placeholder_text = Password
    fade_on_empty = false
}

label {
    text = $TIME
    color = rgba({{ bright_foreground_strip }}ff)
    font_size = 64
    font_family = JetBrains Mono
    position = 0, 120
    halign = center
    valign = center
}

# $DESC is pw_gecos verbatim (hyprlock IWidget.cpp, formatString): GECOS is five
# comma-separated subfields, and the Debian installer fills only the first, so a
# raw $DESC renders as "yourname,,,". Cut at the first comma instead, and fall
# back to the login name when the name subfield is empty. hyprlock runs this
# through /bin/sh -c (MiscFunctions.cpp, spawnSync), so the pipeline is fine.
# Backticks, not $(), and no $vars: hyprlock substitutes $USER and friends
# before it extracts the cmd[] string, so a shell variable here is not ours to
# trust. No hash anywhere, for the usual hyprlang reason.
label {
    text = cmd[] getent passwd "`id -un`" | cut -d: -f5 | cut -d, -f1 | grep . || id -un
    color = rgba({{ omakeb_dim_strip }}ff)
    font_size = 14
    font_family = JetBrains Mono
    position = 0, 60
    halign = center
    valign = center
}
