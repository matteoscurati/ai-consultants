#!/usr/bin/env bash
# AI Consultants - Installation Script
# Installs the skill to ~/.claude/skills/ai-consultants

set -euo pipefail

INSTALL_DIR="${HOME}/.claude/skills/ai-consultants"
REPO_URL="git@github.com:matteoscurati/ai-consultants.git"

echo "==================================="
echo "  AI Consultants - Installation"
echo "==================================="
echo ""

# Create .claude/skills directory if it doesn't exist
mkdir -p "${HOME}/.claude/skills"

# Clone or update
if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation..."
    cd "$INSTALL_DIR" && git pull
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Set executable permissions
echo "Setting permissions..."
chmod +x "$INSTALL_DIR"/scripts/*.sh
chmod +x "$INSTALL_DIR"/scripts/lib/*.sh 2>/dev/null || true

echo ""
echo "Installation complete!"
echo ""
echo "==================================="
echo "  Next Steps: Configure"
echo "==================================="
echo ""
echo "Choose one of these options:"
echo ""
echo "Option A - Interactive Script:"
echo "  $INSTALL_DIR/scripts/setup_wizard.sh"
echo ""
echo "Option B - Claude Code Slash Commands:"
echo "  /ai-consultants:config-check    - Verify CLI installations"
echo "  /ai-consultants:config-status   - View current configuration"
echo "  /ai-consultants:config-api      - Add API consultants"
echo "  /ai-consultants:config-personas - Change personalities"
echo "  /ai-consultants:config-wizard   - Full interactive wizard"
echo ""
