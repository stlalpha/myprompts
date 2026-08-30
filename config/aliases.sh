#!/usr/bin/env bash
# Alias definitions for supported shells

# Every array below is this module's public interface, read by install.sh
# after sourcing rather than by this script. A directive before the first
# command is file-wide in shellcheck, which is exactly the intent here.
# shellcheck disable=SC2034
# sysinfo runs fastfetch inside a closed box. fastfetch cannot draw the right
# border itself -- it has no way to pad a line to a fixed width -- so
# boxfetch.sh measures the rendered output and draws the frame around it.
zsh_aliases=(
  "alias envme='vi ~/.zshrc'"
  "alias sysinfo='$INSTALL_ROOT/fastfetch/boxfetch.sh'"
)

bash_aliases=(
  "alias envme='vi ~/.bashrc'"
  "alias sysinfo='$INSTALL_ROOT/fastfetch/boxfetch.sh'"
)
