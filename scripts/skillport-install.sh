#!/bin/bash
# AI Consultants - SkillPort Installation Script
# Installs the skill via SkillPort for multi-agent support
# Supports: Cursor, Copilot, Windsurf, and other SkillPort-compatible agents
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_usage() {
    cat << EOF
AI Consultants - SkillPort Installation

Usage: $0 [command]

Commands:
    install     Install skill via SkillPort (default)
    uninstall   Remove skill from SkillPort
    generate    Generate AGENTS.md for Copilot/Cursor/Windsurf
    status      Check SkillPort installation status
    help        Show this help message

Requirements:
    - SkillPort CLI (https://github.com/gotalab/skillport)

Examples:
    $0                    # Install skill
    $0 install            # Install skill
    $0 generate           # Generate AGENTS.md
    $0 status             # Check status
EOF
}

check_skillport() {
    if ! command -v skillport &> /dev/null; then
        log_error "SkillPort CLI not found"
        echo ""
        echo "Install SkillPort:"
        echo "  npm install -g skillport"
        echo ""
        echo "Or visit: https://github.com/gotalab/skillport"
        return 1
    fi
    log_success "SkillPort CLI found"
    return 0
}

install_skill() {
    log_info "Installing AI Consultants via SkillPort..."

    if ! check_skillport; then
        return 1
    fi

    # Add skill to SkillPort
    if skillport add "$SKILL_DIR"; then
        log_success "Skill added to SkillPort"
    else
        log_error "Failed to add skill to SkillPort"
        return 1
    fi

    # Verify installation
    if skillport list | grep -q "ai-consultants"; then
        log_success "AI Consultants installed successfully"
        echo ""
        echo "Usage:"
        echo "  skillport show ai-consultants    # Load skill in compatible agents"
        echo "  skillport list                   # View all installed skills"
    else
        log_warn "Skill may not be fully registered"
    fi
}

uninstall_skill() {
    log_info "Removing AI Consultants from SkillPort..."

    if ! check_skillport; then
        return 1
    fi

    if skillport remove ai-consultants 2>/dev/null; then
        log_success "Skill removed from SkillPort"
    else
        log_warn "Skill may not have been installed via SkillPort"
    fi
}

generate_agents_md() {
    log_info "Generating AGENTS.md for multi-agent compatibility..."

    local agents_file="$SKILL_DIR/AGENTS.md"

    if [[ -f "$agents_file" ]]; then
        log_success "AGENTS.md already exists at $agents_file"
    else
        log_warn "AGENTS.md not found - it should exist in the repository"
    fi

    # If SkillPort is available, use it to generate
    if command -v skillport &> /dev/null; then
        log_info "Running SkillPort doc generator..."
        if skillport doc "$SKILL_DIR" 2>/dev/null; then
            log_success "SkillPort documentation generated"
        else
            log_warn "SkillPort doc generation skipped (may already exist)"
        fi
    fi
}

check_status() {
    echo "AI Consultants - SkillPort Status"
    echo "=================================="
    echo ""

    # Check SkillPort
    echo "SkillPort CLI:"
    if command -v skillport &> /dev/null; then
        echo "  Status: Installed"
        echo "  Version: $(skillport --version 2>/dev/null || echo 'unknown')"
    else
        echo "  Status: Not installed"
        echo "  Install: npm install -g skillport"
    fi
    echo ""

    # Check AGENTS.md
    echo "AGENTS.md:"
    if [[ -f "$SKILL_DIR/AGENTS.md" ]]; then
        echo "  Status: Present"
        echo "  Path: $SKILL_DIR/AGENTS.md"
    else
        echo "  Status: Missing"
        echo "  Generate: $0 generate"
    fi
    echo ""

    # Check SKILL.md
    echo "SKILL.md:"
    if [[ -f "$SKILL_DIR/SKILL.md" ]]; then
        echo "  Status: Present"
        local skill_name
        skill_name=$(grep "^name:" "$SKILL_DIR/SKILL.md" | head -1 | cut -d: -f2 | tr -d ' ')
        echo "  Name: $skill_name"
    else
        echo "  Status: Missing"
    fi
    echo ""

    # Check SkillPort registration
    if command -v skillport &> /dev/null; then
        echo "SkillPort Registration:"
        if skillport list 2>/dev/null | grep -q "ai-consultants"; then
            echo "  Status: Registered"
        else
            echo "  Status: Not registered"
            echo "  Register: $0 install"
        fi
    fi
}

# Main
case "${1:-install}" in
    install)
        install_skill
        ;;
    uninstall|remove)
        uninstall_skill
        ;;
    generate|doc)
        generate_agents_md
        ;;
    status|check)
        check_status
        ;;
    help|--help|-h)
        print_usage
        ;;
    *)
        log_error "Unknown command: $1"
        print_usage
        exit 1
        ;;
esac
