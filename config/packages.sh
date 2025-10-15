# Package configuration for Spaceman's Auto-Personalizer

# macOS packages via Homebrew
macos_brew_formulae=(
  mas  # Mac App Store CLI tool
  gh
  nmap
  netcat
)

macos_brew_casks=(
  iterm2
  # magnet        # No longer available as cask - install from App Store
  bettertouchtool
)

# Mac App Store apps (requires mas CLI)
# Find app IDs with: mas search "app name"
macos_appstore_apps=(
  587512244   # Magnet (window manager)
  # 409183694   # Keynote
  # 409201541   # Pages
  # 409203825   # Numbers
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
