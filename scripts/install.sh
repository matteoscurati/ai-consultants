#!/usr/bin/env bash
# AI Consultants - Installation Script v2.2
#
# One-liner install:
#   curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
#
# Or with options:
#   curl -fsSL ... | bash -s -- --no-commands --branch dev
#
# Options:
#   --branch <name>    Install from specific branch (default: main)
#   --no-commands      Skip installing slash commands
#   --update           Update existing installation
#   --uninstall        Remove AI Consultants
#   --help             Show this help

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

INSTALL_DIR="${AI_CONSULTANTS_DIR:-${HOME}/.claude/skills/ai-consultants}"
COMMANDS_DIR="${HOME}/.claude/commands"
REPO_URL="${AI_CONSULTANTS_REPO:-https://github.com/matteoscurati/ai-consultants.git}"
BRANCH="main"
INSTALL_COMMANDS=true
UPDATE_MODE=false
UNINSTALL_MODE=false

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}+---------------------------------------------------------------+${NC}"
    echo -e "${BLUE}|           AI Consultants v2.2 - Installation                  |${NC}"
    echo -e "${BLUE}+---------------------------------------------------------------+${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    cat << 'EOF'
AI Consultants - Installation Script

Usage:
  ./install.sh [options]

One-liner install:
  curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash

Options:
  --branch <name>    Install from specific branch (default: main)
  --no-commands      Skip installing slash commands to ~/.claude/commands
  --update           Update existing installation (git pull)
  --uninstall        Remove AI Consultants completely
  --help             Show this help message

Environment Variables:
  AI_CONSULTANTS_DIR   Override installation directory
  AI_CONSULTANTS_REPO  Override repository URL

Examples:
  # Standard install
  ./install.sh

  # Install from dev branch
  ./install.sh --branch dev

  # Update existing installation
  ./install.sh --update

  # Uninstall
  ./install.sh --uninstall
EOF
}

check_dependencies() {
    local missing=()

    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        echo ""
        log_info "Install them with:"

        if [[ "$(uname)" == "Darwin" ]]; then
            for dep in "${missing[@]}"; do
                echo "  brew install $dep"
            done
        else
            for dep in "${missing[@]}"; do
                echo "  apt install $dep  # or: yum install $dep"
            done
        fi
        return 1
    fi

    return 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --no-commands)
            INSTALL_COMMANDS=false
            shift
            ;;
        --update)
            UPDATE_MODE=true
            shift
            ;;
        --uninstall)
            UNINSTALL_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# =============================================================================
# UNINSTALL
# =============================================================================

if [[ "$UNINSTALL_MODE" == "true" ]]; then
    print_header
    log_info "Uninstalling AI Consultants..."

    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        log_success "Removed: $INSTALL_DIR"
    else
        log_warn "Installation directory not found: $INSTALL_DIR"
    fi

    # Remove commands (with confirmation)
    if [[ -d "$COMMANDS_DIR" ]]; then
        ai_commands=$(find "$COMMANDS_DIR" -name "ai-consultants*.md" -o -name "consult*.md" 2>/dev/null || true)
        if [[ -n "$ai_commands" ]]; then
            echo "$ai_commands" | while read -r cmd_file; do
                rm -f "$cmd_file"
                log_success "Removed command: $(basename "$cmd_file")"
            done
        fi
    fi

    echo ""
    log_success "AI Consultants uninstalled successfully"
    exit 0
fi

# =============================================================================
# INSTALL / UPDATE
# =============================================================================

print_header

# Check dependencies
log_info "Checking dependencies..."
if ! check_dependencies; then
    exit 1
fi
log_success "All dependencies found"

# Create directories
log_info "Setting up directories..."
mkdir -p "$(dirname "$INSTALL_DIR")"
mkdir -p "$COMMANDS_DIR"

# Clone or update
if [[ -d "$INSTALL_DIR" ]]; then
    if [[ "$UPDATE_MODE" == "true" ]]; then
        log_info "Updating existing installation..."
        cd "$INSTALL_DIR"

        # Stash any local changes
        if ! git diff --quiet 2>/dev/null; then
            log_warn "Local changes detected, stashing..."
            git stash
        fi

        # Pull updates
        git fetch origin
        git checkout "$BRANCH"
        git pull origin "$BRANCH"
        log_success "Updated to latest version"
    else
        log_warn "Installation already exists at: $INSTALL_DIR"
        log_info "Use --update to update, or --uninstall to remove first"
        exit 1
    fi
else
    log_info "Cloning repository..."
    git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    log_success "Cloned repository"
fi

# Set permissions
log_info "Setting executable permissions..."
chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR"/scripts/lib/*.sh 2>/dev/null || true
log_success "Permissions set"

# Install slash commands
if [[ "$INSTALL_COMMANDS" == "true" ]]; then
    log_info "Installing slash commands..."

    if [[ -d "$INSTALL_DIR/.claude/commands" ]]; then
        cp "$INSTALL_DIR"/.claude/commands/*.md "$COMMANDS_DIR/" 2>/dev/null || true
        cmd_count=$(ls -1 "$INSTALL_DIR/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
        log_success "Installed $cmd_count slash commands"
    else
        log_warn "No slash commands found to install"
    fi
fi

# Run doctor check
echo ""
log_info "Running health check..."
if "$INSTALL_DIR/scripts/doctor.sh" --json > /dev/null 2>&1; then
    log_success "Health check passed"
else
    log_warn "Some issues detected. Run: $INSTALL_DIR/scripts/doctor.sh"
fi

# =============================================================================
# POST-INSTALL
# =============================================================================

echo ""
echo -e "${GREEN}+---------------------------------------------------------------+${NC}"
echo -e "${GREEN}|                   Installation Complete!                      |${NC}"
echo -e "${GREEN}+---------------------------------------------------------------+${NC}"
echo ""

log_info "Installation directory: $INSTALL_DIR"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Option A: Configure via Claude Code (recommended)"
echo ""
echo "  1. Run the setup wizard:"
echo "     /ai-consultants:config-wizard"
echo ""
echo "  2. Start consulting:"
echo "     /ai-consultants:consult \"Your question here\""
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Option B: Configure via Bash"
echo ""
echo "  1. Run the setup wizard:"
echo "     $INSTALL_DIR/scripts/setup_wizard.sh"
echo ""
echo "  2. Run a consultation:"
echo "     $INSTALL_DIR/scripts/consult_all.sh \"Your question\""
echo ""
echo "  3. Diagnose issues:"
echo "     $INSTALL_DIR/scripts/doctor.sh"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_info "Using another CLI? (Codex, Gemini, Cursor, Aider)"
echo "     See: https://github.com/matteoscurati/ai-consultants#supported-cli-agents"
echo ""
