#!/usr/bin/env bash
# Operating system and package manager detection.

detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    *) echo unknown ;;
  esac
}

detect_linux_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  else
    echo unknown
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Missing required command '$1'. Please install it and rerun."
    exit 1
  fi
}
