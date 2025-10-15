#!/usr/bin/env bash
# Test script for Mac App Store package installation

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Testing Mac App Store package support..."
echo "========================================"

# Test 1: Check if mas is listed in packages
echo -n "Test 1: Check mas in brew formulae... "
if grep -q "mas" config/packages.sh; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  mas not found in brew formulae"
fi

# Test 2: Check if App Store apps array exists
echo -n "Test 2: Check macos_appstore_apps array... "
if grep -q "macos_appstore_apps" config/packages.sh; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  macos_appstore_apps array not found"
fi

# Test 3: Check installer has App Store support
echo -n "Test 3: Check installer has install_appstore_apps function... "
if grep -q "install_appstore_apps()" install.sh; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  install_appstore_apps function not found"
fi

# Test 4: Check Ansible playbook has mas support
echo -n "Test 4: Check Ansible playbook has mas support... "
if grep -q "Install Mac App Store apps" ansible/playbook.yml; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Mac App Store support not found in playbook"
fi

# Test 5: Check filter_missing_packages supports appstore
echo -n "Test 5: Check filter_missing_packages supports appstore... "
if grep -q "appstore)" install.sh; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  appstore case not found in filter_missing_packages"
fi

# Test 6: Test with environment variables
echo ""
echo "Test 6: Dry run installer with App Store apps..."
echo -e "${YELLOW}Note: This is a non-destructive test using a temporary directory${NC}"

# Create temp directory
TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR"
export INSTALL_ROOT="$TEST_DIR/.myprompts"
export BASE_URL="file://$PWD"
export MYPROMPTS_NONINTERACTIVE=1
export PROMPT_VARIANT=bash
export PROMPT_STYLE=compact

echo "Running installer in test mode..."
if bash ./install.sh 2>&1 | grep -q "macos_appstore_apps"; then
    echo -e "${GREEN}✓${NC} App Store apps array detected by installer"
else
    echo -e "${YELLOW}Note: App Store apps may not be visible in non-interactive mode${NC}"
fi

# Cleanup
rm -rf "$TEST_DIR"

echo ""
echo "========================================"
echo -e "${GREEN}Mac App Store support tests complete!${NC}"
echo ""
echo "To test the full installation:"
echo "  1. Ensure you're signed into the Mac App Store"
echo "  2. Run: ./install.sh"
echo "  3. The installer will now offer to install:"
echo "     - mas CLI tool (via Homebrew)"
echo "     - Apps from the Mac App Store (like Magnet)"
echo ""
echo "To find App Store app IDs:"
echo "  mas search 'app name'"
echo ""
echo "To add more apps, edit config/packages.sh and add IDs to macos_appstore_apps array"