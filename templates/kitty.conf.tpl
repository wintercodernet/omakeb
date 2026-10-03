# omakeb — kitty configuration, rendered from the active theme.
# Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
#
# We generate this rather than accept a theme-shipped kitty.conf, and upstream
# refuses one for the same reason: a kitty config can set `shell` and `launch`,
# so a "theme" would be arbitrary code running in every terminal.
#
# No symbol_map for the Nerd Font ranges: kitty falls back through fontconfig,
# and install/50-fonts.sh drops in the snippet that makes the symbol face the
# global fallback.
font_family      JetBrains Mono
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        11.0

window_padding_width 8
hide_window_decorations yes
confirm_os_window_close 0

enable_audio_bell no
scrollback_lines 10000
cursor_shape beam
cursor_blink_interval 0

tab_bar_edge bottom
tab_bar_style powerline
tab_powerline_style slanted

background            {{ background }}
foreground            {{ foreground }}
selection_background  {{ selection_background }}
selection_foreground  {{ selection_foreground }}
cursor                {{ cursor }}
cursor_text_color     {{ background }}
url_color             {{ accent }}
active_border_color   {{ accent }}
inactive_border_color {{ omakeb_surface }}

active_tab_background   {{ accent }}
active_tab_foreground   {{ background }}
inactive_tab_background {{ omakeb_surface }}
inactive_tab_foreground {{ omakeb_muted }}

color0  {{ color0 }}
color8  {{ color8 }}
color1  {{ color1 }}
color9  {{ color9 }}
color2  {{ color2 }}
color10 {{ color10 }}
color3  {{ color3 }}
color11 {{ color11 }}
color4  {{ color4 }}
color12 {{ color12 }}
color5  {{ color5 }}
color13 {{ color13 }}
color6  {{ color6 }}
color14 {{ color14 }}
color7  {{ color7 }}
color15 {{ color15 }}
