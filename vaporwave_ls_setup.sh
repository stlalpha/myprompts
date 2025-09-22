#!/bin/bash
# Quick setup script to add vaporwave LS_COLORS to your shell

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   S E T T I N G   U P   V A P O R W A V E   L S         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Add to bashrc
if [ -f ~/.bashrc ]; then
    if ! grep -q "source ~/.vaporwave_lscolors" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "# Vaporwave LS_COLORS theme" >> ~/.bashrc
        echo "[ -f ~/.vaporwave_lscolors ] && source ~/.vaporwave_lscolors" >> ~/.bashrc
        echo "✓ Added to ~/.bashrc"
    else
        echo "⚡ Already configured in ~/.bashrc"
    fi
fi

# Add to zshrc if it exists
if [ -f ~/.zshrc ]; then
    if ! grep -q "source ~/.vaporwave_lscolors" ~/.zshrc; then
        echo "" >> ~/.zshrc
        echo "# Vaporwave LS_COLORS theme" >> ~/.zshrc
        echo "[ -f ~/.vaporwave_lscolors ] && source ~/.vaporwave_lscolors" >> ~/.zshrc
        echo "✓ Added to ~/.zshrc"
    else
        echo "⚡ Already configured in ~/.zshrc"
    fi
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   V A P O R W A V E   T H E M E   R E A D Y             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "To activate now, run:"
echo "  source ~/.vaporwave_lscolors"
echo ""
echo "Your ls commands will now display in full vaporwave glory!"
echo "Try: ls -la --color=auto"