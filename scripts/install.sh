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

# Copy commands to user commands directory
echo "Installing slash commands..."
mkdir -p "${HOME}/.claude/commands"
cp "$INSTALL_DIR"/.claude/commands/*.md "${HOME}/.claude/commands/"

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Run /ai-consultants:config-wizard in Claude Code"
echo "  2. Or run: $INSTALL_DIR/scripts/configure.sh"
echo ""
