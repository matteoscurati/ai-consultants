#!/bin/bash
# build_context.sh - Automatically generates a context file for AI consultation
#
# Usage: ./build_context.sh <output_file> "Your question" [file1] [file2] ...
#
# Example:
#   ./build_context.sh /tmp/context.md "How to optimize this function?" src/utils.py src/main.py

set -euo pipefail

# Load common functions for validation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- Parameters ---
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <output_file> \"question\" [file1] [file2] ..." >&2
    exit 1
fi

OUTPUT_FILE="$1"
shift
QUERY="$1"
shift

# Validate output file path (allow /tmp for output)
if [[ "$OUTPUT_FILE" == /tmp/* ]]; then
    : # Allow /tmp paths for output
elif ! validate_file_path "$OUTPUT_FILE" "true"; then
    log_error "Invalid output file path: $OUTPUT_FILE"
    exit 1
fi

# FILES array handling (compatible with set -u)
# Validate each file path
FILES=()
while [[ $# -gt 0 ]]; do
    file_arg="$1"
    shift
    # Allow relative paths and /tmp paths for context files
    if [[ "$file_arg" == /tmp/* ]] || validate_file_path "$file_arg" "false" 2>/dev/null; then
        FILES+=("$file_arg")
    else
        log_warn "Skipping invalid file path: $file_arg"
    fi
done

# --- Build Context ---
{
    echo "# Project Context"
    echo ""

    # Working directory
    echo "## Working Directory"
    echo '```'
    pwd
    echo '```'
    echo ""

    # Project structure (relevant files, excluding noise)
    echo "## Project Structure"
    echo '```'
    find . -maxdepth 4 -type f \( \
        -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" \
        -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.kt" \
        -o -name "*.rb" -o -name "*.php" -o -name "*.swift" -o -name "*.c" \
        -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" -o -name "*.cs" \
        -o -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \
        -o -name "Dockerfile" -o -name "docker-compose*.yml" \
        -o -name "Makefile" -o -name "CMakeLists.txt" \
        -o -name "*.json" -o -name "*.toml" -o -name "*.yaml" -o -name "*.yml" \
        -o -name "*.md" \
    \) \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/.venv/*' \
    -not -path '*/venv/*' \
    -not -path '*/target/*' \
    -not -path '*/.next/*' \
    2>/dev/null | sort | head -100 || true
    echo '```'
    echo ""

    # Content of specific files
    if [[ ${#FILES[@]} -gt 0 ]]; then
        echo "## Relevant Files"
        echo ""

        for file_path in "${FILES[@]}"; do
            if [[ -f "$file_path" ]]; then
                # Extract extension for syntax highlighting
                extension="${file_path##*.}"

                # Map extensions to languages for markdown
                case "$extension" in
                    py) lang="python" ;;
                    js) lang="javascript" ;;
                    ts|tsx) lang="typescript" ;;
                    rb) lang="ruby" ;;
                    go) lang="go" ;;
                    rs) lang="rust" ;;
                    java|kt) lang="java" ;;
                    sh|bash|zsh) lang="bash" ;;
                    json) lang="json" ;;
                    yaml|yml) lang="yaml" ;;
                    toml) lang="toml" ;;
                    md) lang="markdown" ;;
                    sql) lang="sql" ;;
                    *) lang="$extension" ;;
                esac

                echo "### File: \`$file_path\`"
                echo ""
                echo "\`\`\`$lang"
                cat "$file_path"
                echo ""
                echo "\`\`\`"
                echo ""
            else
                echo "### File: \`$file_path\`"
                echo ""
                echo "*File not found*"
                echo ""
            fi
        done
    fi

    # Question
    echo "---"
    echo ""
    echo "# Question"
    echo ""
    echo "$QUERY"
    echo ""

} > "$OUTPUT_FILE"

# Output: path of created file (for use in scripts)
echo "$OUTPUT_FILE"
