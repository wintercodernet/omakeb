# omakeb:migration=Keep the omakeb prompt layout on machines that never chose one, now that new installs default to darkgreen.
#
# A state key whose meaning changed: an unset `prompt` used to mean `omakeb`
# and now means darkgreen (OMAKEB_PROMPT_DEFAULT). Writing the old meaning down
# keeps an existing prompt where it was; a fresh install stamps past this and
# gets the new default. A machine that already chose a layout is left alone.
if [[ -n $(state_get prompt) ]]; then
  log_skip "prompt layout already chosen: $(state_get prompt)"
else
  state_set prompt omakeb
  log_ok "kept the omakeb prompt layout (try darkgreen: omakeb-prompt-set darkgreen)"
fi
