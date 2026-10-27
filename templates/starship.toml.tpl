# omakeb — starship prompt, rendered from the active theme.
# Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
#
# default/bash/init.sh runs `starship init bash` unconditionally; before a theme
# is set starship uses its own built-in preset, and this file replaces it.
#
# This is the "omakeb" prompt layout, the default of `omakeb-prompt-set`. Every
# colour names a role in the `omakeb` palette rather than being written inline.
# The palette itself is templates/starship-palette.toml.tpl, which
# omakeb-theme-set appends to whichever layout is chosen, so a theme change
# retints this layout and any user layout that also says `palette = "omakeb"`.

format = "$directory$git_branch$git_status$cmd_duration$character"
add_newline = false
palette = "omakeb"

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
