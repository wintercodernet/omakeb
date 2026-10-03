# omakeb — fuzzel configuration, rendered from the active theme.
# Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
#
# fuzzel colours are RRGGBBAA with NO leading hash, unlike every other file the
# theme system writes. That is why the palette stores plain colours and the
# templates decide the encoding.
#
# `selection` uses omakeb_surface rather than lighter_background on purpose:
# lighter_background falls back through color0 to background, so a theme that
# does not declare it would give a selection bar the same colour as the
# backdrop — an invisible highlight and no error. lib/theme.py derives a
# surface instead whenever the two would be equal.
[main]
font=JetBrains Mono:size=12
dpi-aware=no
prompt=>
icon-theme={{ omakeb_icon_theme }}
terminal=kitty -e
layer=overlay
lines=12
width=48
horizontal-pad=20
vertical-pad=16
inner-pad=8
tabs=4

[colors]
background={{ background_strip }}f2
text={{ omakeb_dim_strip }}ff
prompt={{ omakeb_placeholder_strip }}ff
input={{ foreground_strip }}ff
match={{ accent_strip }}ff
selection={{ omakeb_surface_strip }}ff
selection-text={{ bright_foreground_strip }}ff
selection-match={{ accent_strip }}ff
border={{ accent_strip }}ff

[border]
width=2
radius=12

[dmenu]
exit-immediately-if-empty=yes
