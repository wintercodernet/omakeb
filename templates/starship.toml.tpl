# omakeb — starship prompt, rendered from the active theme.
# Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
#
# default/bash/init.sh runs `starship init bash` unconditionally; before a theme
# is set starship uses its own built-in preset, and this file replaces it.
#
# Every colour goes through the palette below rather than being written inline,
# so a module's colour is named by role and a theme change is a one-file
# rewrite. Starship accepts "#rrggbb" directly.

format = "$directory$git_branch$git_status$cmd_duration$character"
add_newline = false
palette = "omakeb"

[palettes.omakeb]
accent = "{{ accent }}"
foreground = "{{ foreground }}"
dim = "{{ omakeb_dim }}"
muted = "{{ omakeb_muted }}"
warning = "{{ omakeb_warning }}"
urgent = "{{ omakeb_urgent }}"
ok = "{{ green }}"
info = "{{ cyan }}"

[character]
success_symbol = "[❯](accent)"
error_symbol = "[❯](urgent)"
vimcmd_symbol = "[❮](ok)"

[directory]
style = "bold accent"
truncation_length = 3
truncate_to_repo = true

[git_branch]
style = "info"
symbol = " "

[git_status]
style = "warning"

[cmd_duration]
style = "muted"
min_time = 2000
format = "[ $duration]($style)"
