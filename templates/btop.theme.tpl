# omakeb — btop theme, rendered from the active theme.
# Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
#
# btop reads theme[<key>]. NOT theme_color[<key>] — at least one community
# theme in the wild ships a btop.theme written with theme_color[...] keys, and
# btop parses that file happily, finds nothing it recognises and renders in its
# built-in colours with no error at all. That is why we generate this file from
# the palette instead of accepting a theme-shipped one, even though btop.theme
# is one of only two formats that would otherwise transfer unchanged.

theme[main_bg]="{{ background }}"
theme[main_fg]="{{ foreground }}"
theme[title]="{{ bright_foreground }}"
theme[hi_fg]="{{ accent }}"
theme[selected_bg]="{{ omakeb_surface }}"
theme[selected_fg]="{{ bright_foreground }}"
theme[inactive_fg]="{{ omakeb_muted }}"
theme[graph_text]="{{ omakeb_dim }}"
theme[meter_bg]="{{ omakeb_surface }}"
theme[proc_misc]="{{ cyan }}"

theme[cpu_box]="{{ omakeb_surface }}"
theme[mem_box]="{{ omakeb_surface }}"
theme[net_box]="{{ omakeb_surface }}"
theme[proc_box]="{{ omakeb_surface }}"
theme[div_line]="{{ omakeb_surface }}"

theme[temp_start]="{{ green }}"
theme[temp_mid]="{{ yellow }}"
theme[temp_end]="{{ red }}"

theme[cpu_start]="{{ green }}"
theme[cpu_mid]="{{ yellow }}"
theme[cpu_end]="{{ red }}"

theme[free_start]="{{ blue }}"
theme[free_mid]="{{ cyan }}"
theme[free_end]="{{ green }}"

theme[cached_start]="{{ cyan }}"
theme[cached_mid]="{{ blue }}"
theme[cached_end]="{{ magenta }}"

theme[available_start]="{{ yellow }}"
theme[available_mid]="{{ orange }}"
theme[available_end]="{{ red }}"

theme[used_start]="{{ green }}"
theme[used_mid]="{{ yellow }}"
theme[used_end]="{{ red }}"

theme[download_start]="{{ magenta }}"
theme[download_mid]="{{ blue }}"
theme[download_end]="{{ cyan }}"

theme[upload_start]="{{ green }}"
theme[upload_mid]="{{ yellow }}"
theme[upload_end]="{{ orange }}"

theme[process_start]="{{ blue }}"
theme[process_mid]="{{ magenta }}"
theme[process_end]="{{ red }}"
