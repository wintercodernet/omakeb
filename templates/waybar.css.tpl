/* omakeb — waybar stylesheet, rendered from the active theme.
 * Managed by omakeb-theme-set. Edits are overwritten when the theme changes.
 *
 * This is GTK CSS, NOT hyprlang: colours here are written '#rrggbb' and must
 * stay that way. The '##' escape a Hyprland config needs would be a syntax
 * error in this file.
 *
 * Layout is ours and never comes from the theme. An upstream theme's
 * waybar.css carries exactly two colours and Omarchy v1's module names; the
 * palette is the only durable part of it, so that is all we take (D11). */

* {
  font-family: "JetBrains Mono", monospace;
  font-size: 13px;
  min-height: 0;
  border: none;
  border-radius: 0;
}

/* The bar's translucency is an omakeb constant, not a theme value. Even
 * upstream keeps this out of the palette — there is no key to ask. */
window#waybar {
  background: rgba({{ background_rgb }}, {{ omakeb_bar_alpha }});
  color: {{ foreground }};
}

#custom-omakeb {
  color: {{ accent }};
  font-size: 17px;
  padding: 0 14px 0 12px;
}

#workspaces button {
  padding: 0 9px;
  color: {{ omakeb_muted }};
  background: transparent;
}

#workspaces button.active {
  color: {{ background }};
  background: {{ accent }};
  border-radius: 6px;
}

#workspaces button.urgent {
  color: {{ background }};
  background: {{ omakeb_urgent }};
  border-radius: 6px;
}

#workspaces button:hover {
  color: {{ foreground }};
  background: rgba({{ accent_rgb }}, 0.2);
  border-radius: 6px;
}

#submap {
  color: {{ omakeb_warning }};
  padding: 0 10px;
}

#clock {
  color: {{ foreground }};
  font-weight: bold;
  padding: 0 12px;
}

#tray,
#pulseaudio,
#bluetooth,
#network,
#cpu,
#memory,
#battery {
  padding: 0 10px;
  color: {{ omakeb_dim }};
}

#pulseaudio.muted,
#network.disconnected {
  color: {{ omakeb_muted }};
}

#battery.warning {
  color: {{ omakeb_warning }};
}

#battery.critical {
  color: {{ omakeb_urgent }};
}

#tray > .passive {
  -gtk-icon-effect: dim;
}
