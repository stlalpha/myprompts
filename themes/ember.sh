#!/usr/bin/env bash
# Ember palette — warm ember-orange accents on cool steel, modelled after
# send.themcbros.com. Format: <256-color index>:<hex>. Sets color roles only.
# Must not touch PS1/PROMPT or install hooks.

# Every variable below is this module's public interface, read by the prompt
# files rather than by this script. A directive before the first command is
# file-wide in shellcheck, which is exactly the intent here.
# shellcheck disable=SC2034
MP_ACCENT1=208:FF7A1A   # Ember orange
MP_ACCENT2=202:FF6A00   # Molten orange
MP_ACCENT3=209:FF8A3A   # Ember highlight
MP_OK=251:C8D2DA        # Steel light
MP_INFO=245:8A97A2      # Steel mid
MP_ERR=196:FF2400       # Molten red
MP_MUTED=240:5A6570     # Dim steel
