# Package configuration for Spaceman's Auto-Personalizer

# macOS packages via Homebrew
macos_brew_formulae=(
  gh
  nmap
  netcat
)

macos_brew_casks=(
  iterm2
  # magnet        # No longer available as cask - install from App Store
  bettertouchtool
)

# Linux packages per package manager (extendable)
linux_apt_packages=(
  nmap
  netcat
)

linux_dnf_packages=(
  nmap
  nmap-ncat
)

linux_pacman_packages=(
  nmap
)

linux_paru_packages=(
  gnu-netcat
)
