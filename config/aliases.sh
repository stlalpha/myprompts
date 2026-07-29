#!/usr/bin/env bash
# Alias definitions for supported shells

# Every array below is this module's public interface, read by install.sh
# after sourcing rather than by this script. A directive before the first
# command is file-wide in shellcheck, which is exactly the intent here.
# shellcheck disable=SC2034
zsh_aliases=(
  "alias envme='vi ~/.zshrc'"
)

bash_aliases=(
  "alias envme='vi ~/.bashrc'"
)
