#!/usr/bin/env bash
# Signal Mine palette. Format: <256-color index>:<hex>
# Sets color roles only. Must not touch PS1/PROMPT or install hooks.

# Every variable below is this module's public interface, read by the prompt
# files rather than by this script. A directive before the first command is
# file-wide in shellcheck, which is exactly the intent here.
# shellcheck disable=SC2034
MP_ACCENT1=208:FF7705   # Signal Orange
MP_ACCENT2=203:FF3C4B   # Signal Coral
MP_ACCENT3=198:FF0090   # Signal Magenta
MP_OK=190:D2FC00        # Electric Lime
MP_INFO=43:00D9B5       # Cyan
MP_ERR=203:FF3C4B       # Signal Coral
MP_MUTED=244:808080     # Gray
