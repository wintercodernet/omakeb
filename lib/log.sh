#!/bin/bash
# shellcheck shell=bash

if [[ -t 1 ]]; then
  _c_reset=$'\e[0m'; _c_dim=$'\e[2m'; _c_red=$'\e[31m'
  _c_green=$'\e[32m'; _c_yellow=$'\e[33m'; _c_blue=$'\e[34m'
else
  _c_reset=; _c_dim=; _c_red=; _c_green=; _c_yellow=; _c_blue=
fi

log_step()  { printf '\n%s==>%s %s\n' "$_c_blue" "$_c_reset" "$*"; }
log_info()  { printf '  %s\n' "$*"; }
log_skip()  { printf '  %s- %s%s\n' "$_c_dim" "$*" "$_c_reset"; }
log_ok()    { printf '  %s✓%s %s\n' "$_c_green" "$_c_reset" "$*"; }
log_warn()  { printf '  %s!%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
log_error() { printf '\n%serror:%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; }
log_done()  { printf '\n%s%s%s\n' "$_c_green" "$*" "$_c_reset"; }

die() { log_error "$*"; exit 1; }
