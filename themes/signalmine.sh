#!/usr/bin/env bash
# Signal Mine palette. Format: <256-color index>:<hex>
# Sets color roles only. Must not touch PS1/PROMPT or install hooks.

# shellcheck disable=SC2034
# These roles are the module's public interface: consumed by the bash/zsh
# prompts via mp_load_theme, not read within this file.
MP_ACCENT1=208:FF7705   # Signal Orange
MP_ACCENT2=203:FF3C4B   # Signal Coral
MP_ACCENT3=198:FF0090   # Signal Magenta
MP_OK=190:D2FC00        # Electric Lime
MP_INFO=43:00D9B5       # Cyan
MP_ERR=203:FF3C4B       # Signal Coral
MP_MUTED=244:808080     # Gray
