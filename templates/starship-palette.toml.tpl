# omakeb — the theme's colours as a starship palette, by role.
# Not installed on its own: omakeb-theme-set appends it to the chosen prompt
# layout (see omakeb-prompt-set), unless the layout already defines
# [palettes.omakeb] itself. A layout opts in with `palette = "omakeb"` and then
# names these roles, e.g. style = "bold accent". Starship accepts "#rrggbb".

[palettes.omakeb]
accent = "{{ accent }}"
foreground = "{{ foreground }}"
dim = "{{ omakeb_dim }}"
muted = "{{ omakeb_muted }}"
warning = "{{ omakeb_warning }}"
urgent = "{{ omakeb_urgent }}"
ok = "{{ green }}"
info = "{{ cyan }}"
