# omakeb — mako configuration, rendered from the active theme.
# Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
#
# mako wants #rrggbbaa, so the alpha is appended to the stripped hex.
#
# The [mode=do-not-disturb] section at the bottom is what makes SUPER+CTRL+,
# actually silence anything: omakeb-toggle-dnd flips mako into that mode with
# `makoctl mode -t`, and without a section defining invisible=1 the mode exists
# but does nothing. This is the single reason we never adopt a theme-shipped
# mako.ini — the v1-era files carry layout and behavioural sections and would
# silently drop this one (D11, C3).
font=JetBrains Mono 10
background-color=#{{ background_strip }}eb
text-color=#{{ foreground_strip }}ff
border-color=#{{ accent_strip }}ff
progress-color=over #{{ omakeb_surface_strip }}ff

border-size=2
border-radius=10
padding=12
margin=10
max-icon-size=48
icon-location=left

anchor=top-right
layer=overlay
default-timeout=5000
ignore-timeout=0
max-visible=5
group-by=app-name

[urgency=low]
border-color=#{{ omakeb_muted_strip }}ff
text-color=#{{ omakeb_dim_strip }}ff
default-timeout=3000

[urgency=critical]
border-color=#{{ omakeb_urgent_strip }}ff
default-timeout=0

[mode=do-not-disturb]
invisible=1
