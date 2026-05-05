# Package configuration for Spaceman's Auto-Personalizer

# macOS packages via Homebrew
macos_brew_formulae=(
  mas  # Mac App Store CLI tool
  gh
  nmap
  netcat
  neofetch
)

macos_brew_casks=(
  iterm2
  # magnet        # No longer available as cask - install from App Store
  bettertouchtool
)

# Mac App Store apps (requires mas CLI)
# Find app IDs with: mas search "app name"
macos_appstore_apps=(
  441258766   # Magnet (window manager)
  # 409183694   # Keynote
  # 409201541   # Pages
  # 409203825   # Numbers
)

# Linux packages per package manager (extendable)
linux_apt_packages=(
  nmap
  netcat-openbsd
  neofetch
)

linux_dnf_packages=(
  nmap
  nmap-ncat
  neofetch
)

linux_pacman_packages=(
  nmap
  neofetch
)

linux_paru_packages=(
  gnu-netcat
)
