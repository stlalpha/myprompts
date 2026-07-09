#!/usr/bin/env bash
# Vaporwave palette. Format: <256-color index>:<hex>
# Sets color roles only. Must not touch PS1/PROMPT or install hooks.

# shellcheck disable=SC2034
# These roles are the module's public interface: consumed by the bash/zsh
# prompts via mp_load_theme, not read within this file.
MP_ACCENT1=209:FF875F   # Sunset orange
MP_ACCENT2=141:AF87FF   # Light purple
MP_ACCENT3=198:FF0087   # Hot pink
MP_OK=85:5FFFD7         # Mint
MP_INFO=51:00FFFF       # Bright cyan
MP_ERR=196:FF0000       # Red
MP_MUTED=244:808080     # Gray
