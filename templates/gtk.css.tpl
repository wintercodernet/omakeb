/* omakeb — GTK accent colours, rendered from the active theme.
 * Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
 * Written to both gtk-3.0/gtk.css and gtk-4.0/gtk.css.
 *
 * This is GTK CSS and needs '#rrggbb', like the waybar stylesheet and unlike
 * every Hyprland file the theme system writes.
 *
 * Deliberately small. The heavy lifting is Adwaita plus the colour-scheme and
 * icon-theme gsettings that omakeb-theme-set applies; this only pulls the
 * accent and selection across so GTK apps agree with the bar. Overriding more
 * than this fights the system theme and breaks on the next Adwaita release. */

@define-color omakeb_background {{ background }};
@define-color omakeb_surface {{ omakeb_surface }};
@define-color omakeb_foreground {{ foreground }};
@define-color omakeb_accent {{ accent }};
@define-color omakeb_urgent {{ omakeb_urgent }};

@define-color accent_color {{ accent }};
@define-color accent_bg_color {{ accent }};
@define-color accent_fg_color {{ background }};
@define-color destructive_color {{ omakeb_urgent }};
@define-color theme_selected_bg_color {{ accent }};
@define-color theme_selected_fg_color {{ background }};

/* GTK CSS is not web CSS: it has no `::selection` pseudo-element. GTK models
   the selection as a node named `selection`, and a `::`-prefixed selector makes
   the parser log "Invalid name of pseudo-class" and drop the rule — visible in
   the journal of every GTK app that re-reads this file on a theme change. */
selection {
  background-color: {{ accent }};
  color: {{ background }};
}

progressbar > trough > progress {
  background-color: {{ accent }};
}
