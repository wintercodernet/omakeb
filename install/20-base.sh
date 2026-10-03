#!/bin/bash
# Tier-1 terminal environment.
# shellcheck shell=bash

mapfile -t base_pkgs < <(pkg_list "$OMAKEB_PATH/packages/base.list")
apt_install "${base_pkgs[@]}"
