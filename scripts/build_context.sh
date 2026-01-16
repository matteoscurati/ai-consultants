#!/bin/bash
# build_context.sh - Automatically generates a context file for AI consultation
#
# Usage: ./build_context.sh <output_file> "Your question" [file1] [file2] ...
#
# Example:
#   ./build_context.sh /tmp/context.md "How to optimize this function?" src/utils.py src/main.py
#
# Token Optimization Modes (v2.2):
#   - none:  Include file contents as-is (no optimization)
#   - basic: Simple byte-based truncation (legacy behavior)
#   - ast:   Extract code skeleton using AST (default)
#   - full:  AST + symbol compression + semantic chunking

set -euo pipefail

# Load common functions for validation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# =============================================================================
# TOKEN OPTIMIZATION CONFIGURATION (v2.2)
# =============================================================================

# Optimization mode: "none", "basic", "ast", "full"
TOKEN_OPTIMIZATION_MODE="${TOKEN_OPTIMIZATION_MODE:-ast}"

# Enable AST-based code skeleton extraction
ENABLE_AST_EXTRACTION="${ENABLE_AST_EXTRACTION:-true}"

# Enable symbol compression (replaces long identifiers with short tokens)
# Note: Opt-in because it requires the symbol map to decode
ENABLE_SYMBOL_COMPRESSION="${ENABLE_SYMBOL_COMPRESSION:-false}"

# Enable semantic chunking (splits large files into meaningful chunks)
ENABLE_SEMANTIC_CHUNKING="${ENABLE_SEMANTIC_CHUNKING:-true}"

# Maximum bytes per context file before optimization kicks in
MAX_CONTEXT_FILE_BYTES="${MAX_CONTEXT_FILE_BYTES:-8000}"

# =============================================================================
# MODULE LOADING WITH FALLBACK
# =============================================================================

# Track which optimization modules are available
_HAS_CODE_OPTIMIZER=false
_HAS_CHUNKING=false
_HAS_SYMBOL_MAP=false

# Try to source optimization modules (optional dependencies)
if [[ -f "$SCRIPT_DIR/lib/code_optimizer.sh" ]]; then
    source "$SCRIPT_DIR/lib/code_optimizer.sh"
    _HAS_CODE_OPTIMIZER=true
    log_debug "Loaded code_optimizer.sh module"
fi

if [[ -f "$SCRIPT_DIR/lib/chunking.sh" ]]; then
    source "$SCRIPT_DIR/lib/chunking.sh"
    _HAS_CHUNKING=true
    log_debug "Loaded chunking.sh module"
fi

if [[ -f "$SCRIPT_DIR/lib/symbol_map.sh" ]]; then
    source "$SCRIPT_DIR/lib/symbol_map.sh"
    _HAS_SYMBOL_MAP=true
    log_debug "Loaded symbol_map.sh module"
fi

# Determine effective optimization mode based on available modules
_determine_effective_mode() {
    local mode="$1"

    case "$mode" in
        none|basic)
            echo "$mode"
            ;;
        ast|full)
            if [[ "$_HAS_CODE_OPTIMIZER" != "true" ]]; then
                log_warn "Mode '$mode' requires code_optimizer.sh, falling back to basic"
                echo "basic"
                return
            fi
            # Disable features if modules unavailable
            [[ "$mode" == "full" && "$ENABLE_SYMBOL_COMPRESSION" == "true" && "$_HAS_SYMBOL_MAP" != "true" ]] && ENABLE_SYMBOL_COMPRESSION="false"
            [[ "$mode" == "full" && "$ENABLE_SEMANTIC_CHUNKING" == "true" && "$_HAS_CHUNKING" != "true" ]] && ENABLE_SEMANTIC_CHUNKING="false"
            echo "$mode"
            ;;
        *)
            log_warn "Unknown mode '$mode', using basic"
            echo "basic"
            ;;
    esac
}

# =============================================================================
# OPTIMIZATION STATISTICS TRACKING
# =============================================================================

# Global counters for statistics
_TOTAL_FILES_PROCESSED=0
_TOTAL_ORIGINAL_BYTES=0
_TOTAL_OPTIMIZED_BYTES=0
_FILES_OPTIMIZED=0
_FILES_PASSED_THROUGH=0

# Per-file tracking (using map functions from common.sh)
# Maps: ORIGINAL_SIZES, OPTIMIZED_SIZES, OPTIMIZATION_APPLIED

# Reset statistics
_reset_stats() {
    _TOTAL_FILES_PROCESSED=0
    _TOTAL_ORIGINAL_BYTES=0
    _TOTAL_OPTIMIZED_BYTES=0
    _FILES_OPTIMIZED=0
    _FILES_PASSED_THROUGH=0
    map_clear "ORIGINAL_SIZES"
    map_clear "OPTIMIZED_SIZES"
    map_clear "OPTIMIZATION_APPLIED"
}

# Record file statistics
# Usage: _record_file_stats "filename" original_size optimized_size "optimization_type"
_record_file_stats() {
    local filename="$1"
    local original_size="$2"
    local optimized_size="$3"
    local opt_type="$4"

    local safe_name
    safe_name=$(echo "$filename" | tr '/' '_' | tr '.' '_')

    map_set "ORIGINAL_SIZES" "$safe_name" "$original_size"
    map_set "OPTIMIZED_SIZES" "$safe_name" "$optimized_size"
    map_set "OPTIMIZATION_APPLIED" "$safe_name" "$opt_type"

    _TOTAL_FILES_PROCESSED=$((_TOTAL_FILES_PROCESSED + 1))
    _TOTAL_ORIGINAL_BYTES=$((_TOTAL_ORIGINAL_BYTES + original_size))
    _TOTAL_OPTIMIZED_BYTES=$((_TOTAL_OPTIMIZED_BYTES + optimized_size))

    if [[ "$opt_type" != "none" && "$opt_type" != "passthrough" ]]; then
        _FILES_OPTIMIZED=$((_FILES_OPTIMIZED + 1))
    else
        _FILES_PASSED_THROUGH=$((_FILES_PASSED_THROUGH + 1))
    fi
}

# Log optimization statistics summary
_log_optimization_stats() {
    if [[ $_TOTAL_FILES_PROCESSED -eq 0 ]]; then
        return
    fi

    local savings_bytes=$((_TOTAL_ORIGINAL_BYTES - _TOTAL_OPTIMIZED_BYTES))
    local savings_pct=0
    if [[ $_TOTAL_ORIGINAL_BYTES -gt 0 ]]; then
        savings_pct=$((savings_bytes * 100 / _TOTAL_ORIGINAL_BYTES))
    fi

    local original_tokens=$((_TOTAL_ORIGINAL_BYTES / 4))
    local optimized_tokens=$((_TOTAL_OPTIMIZED_BYTES / 4))
    local tokens_saved=$((original_tokens - optimized_tokens))

    log_info "Context optimization summary:"
    log_info "  Files processed: $_TOTAL_FILES_PROCESSED (optimized: $_FILES_OPTIMIZED, passed through: $_FILES_PASSED_THROUGH)"
    log_info "  Original size: $_TOTAL_ORIGINAL_BYTES bytes (~$original_tokens tokens)"
    log_info "  Optimized size: $_TOTAL_OPTIMIZED_BYTES bytes (~$optimized_tokens tokens)"
    log_info "  Savings: $savings_bytes bytes (~$tokens_saved tokens, ${savings_pct}%)"
}

# =============================================================================
# FILE CONTENT OPTIMIZATION
# =============================================================================

# Get language identifier for a file extension
# Usage: _get_lang_for_extension "py"
_get_lang_for_extension() {
    local extension="$1"
    case "$extension" in
        py) echo "python" ;;
        js) echo "javascript" ;;
        ts|tsx) echo "typescript" ;;
        rb) echo "ruby" ;;
        go) echo "go" ;;
        rs) echo "rust" ;;
        java|kt) echo "java" ;;
        sh|bash|zsh) echo "bash" ;;
        json) echo "json" ;;
        yaml|yml) echo "yaml" ;;
        toml) echo "toml" ;;
        md) echo "markdown" ;;
        sql) echo "sql" ;;
        c) echo "c" ;;
        cpp|cc|cxx) echo "cpp" ;;
        h|hpp) echo "cpp" ;;
        cs) echo "csharp" ;;
        swift) echo "swift" ;;
        php) echo "php" ;;
        *) echo "$extension" ;;
    esac
}

# Check if file type supports AST extraction
# Usage: _supports_ast_extraction "python"
_supports_ast_extraction() {
    local lang="$1"
    # Languages that typically support AST-based extraction
    case "$lang" in
        python|javascript|typescript|go|rust|java|cpp|c|csharp|ruby|php|swift)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Generate truncated content with header
_truncate_file() {
    local file_path="$1"
    local original_size="$2"
    echo "# File: $file_path (truncated: ${original_size} bytes, showing first ${MAX_CONTEXT_FILE_BYTES})
$(head -c "$MAX_CONTEXT_FILE_BYTES" "$file_path")
# ... [truncated] ..."
}

# Optimize file content based on mode
_optimize_file_content() {
    local file_path="$1"
    local mode="$2"
    local lang="$3"

    local original_size
    original_size=$(wc -c < "$file_path" | tr -d ' ')
    local optimized_content=""
    local opt_type="none"

    # Small files pass through unchanged
    if [[ "$mode" != "none" && $original_size -le $MAX_CONTEXT_FILE_BYTES ]]; then
        optimized_content=$(cat "$file_path")
        opt_type="passthrough"
    else
        case "$mode" in
            none)
                optimized_content=$(cat "$file_path")
                opt_type="none"
                ;;

            basic)
                optimized_content=$(_truncate_file "$file_path" "$original_size")
                opt_type="truncated"
                ;;

            ast)
                if _supports_ast_extraction "$lang" && [[ "$_HAS_CODE_OPTIMIZER" == "true" ]]; then
                    local extracted=""
                    if extracted=$(optimize_code_file "$file_path" 2>/dev/null) && [[ -n "$extracted" ]]; then
                        optimized_content="# File: $file_path (AST skeleton: ${original_size} bytes -> optimized)
$extracted"
                        opt_type="ast_skeleton"
                    fi
                fi
                # Fallback to truncation
                if [[ -z "$optimized_content" ]]; then
                    optimized_content=$(_truncate_file "$file_path" "$original_size")
                    opt_type="truncated"
                fi
                ;;

            full)
                local temp_content=""
                local applied_opts=""

                # Step 1: AST extraction
                if _supports_ast_extraction "$lang" && [[ "$_HAS_CODE_OPTIMIZER" == "true" ]]; then
                    if temp_content=$(optimize_code_file "$file_path" 2>/dev/null) && [[ -n "$temp_content" ]]; then
                        applied_opts="ast"
                    fi
                fi
                [[ -z "$temp_content" ]] && temp_content=$(cat "$file_path")

                # Step 2: Symbol compression
                if [[ "$ENABLE_SYMBOL_COMPRESSION" == "true" && "$_HAS_SYMBOL_MAP" == "true" ]]; then
                    local compressed=""
                    if compressed=$(compress_symbols "$temp_content" "$lang" 2>/dev/null) && [[ -n "$compressed" ]]; then
                        temp_content="$compressed"
                        applied_opts="${applied_opts:+$applied_opts+}symbol_compression"
                    fi
                fi

                # Step 3: Semantic chunking if still too large
                local temp_size
                temp_size=$(echo -n "$temp_content" | wc -c | tr -d ' ')
                if [[ "$ENABLE_SEMANTIC_CHUNKING" == "true" && "$_HAS_CHUNKING" == "true" && $temp_size -gt $MAX_CONTEXT_FILE_BYTES ]]; then
                    local chunks_json=""
                    chunks_json=$(chunk_file_semantically "$file_path" 2>/dev/null) || chunks_json="[]"
                    if [[ -n "$chunks_json" && "$chunks_json" != "[]" ]]; then
                        local chunked_content=""
                        chunked_content=$(echo "$chunks_json" | jq -r '
                            sort_by(-.priority) | .[0:5] |
                            map("# Chunk: \(.id) (priority: \(.priority))\n\(.content)") |
                            join("\n\n---\n\n")
                        ' 2>/dev/null) || chunked_content=""
                        if [[ -n "$chunked_content" ]]; then
                            temp_content="$chunked_content"
                            applied_opts="${applied_opts:+$applied_opts+}chunking"
                        fi
                    fi
                fi

                # Final truncation if still too large
                temp_size=$(echo -n "$temp_content" | wc -c | tr -d ' ')
                if [[ $temp_size -gt $MAX_CONTEXT_FILE_BYTES ]]; then
                    temp_content=$(echo "$temp_content" | head -c "$MAX_CONTEXT_FILE_BYTES")
                    applied_opts="${applied_opts:+$applied_opts+}truncated"
                fi

                opt_type="${applied_opts:-truncated}"
                optimized_content="# File: $file_path (optimized: ${original_size} bytes -> ${temp_size} bytes, mode: $opt_type)
$temp_content"
                ;;
        esac
    fi

    # Record statistics and output
    local optimized_size
    optimized_size=$(echo -n "$optimized_content" | wc -c | tr -d ' ')
    _record_file_stats "$file_path" "$original_size" "$optimized_size" "$opt_type"
    log_debug "Optimized $file_path: $original_size -> $optimized_size bytes (mode: $opt_type)"
    echo "$optimized_content"
}

# =============================================================================
# SYMBOL MAP GENERATION
# =============================================================================

# Generate symbol map section for manifest
# Only included if symbol compression was used
_generate_symbol_map_section() {
    if [[ "$ENABLE_SYMBOL_COMPRESSION" != "true" || "$_HAS_SYMBOL_MAP" != "true" ]]; then
        return
    fi

    # Check if get_last_symbol_map function exists and returns content
    if type get_last_symbol_map &>/dev/null; then
        local map_content
        if map_content=$(get_last_symbol_map 2>/dev/null) && [[ -n "$map_content" ]]; then
            echo ""
            echo "### Symbol Map"
            echo "The following symbols were compressed. Use this map to decode:"
            echo '```json'
            echo "$map_content"
            echo '```'
        fi
    fi
}

# =============================================================================
# CONTEXT MANIFEST GENERATION
# =============================================================================

# Generate the context manifest header
# Usage: _generate_manifest "mode"
_generate_manifest() {
    local mode="$1"

    local original_tokens=$((_TOTAL_ORIGINAL_BYTES / 4))
    local optimized_tokens=$((_TOTAL_OPTIMIZED_BYTES / 4))
    local savings_pct=0
    if [[ $_TOTAL_ORIGINAL_BYTES -gt 0 ]]; then
        savings_pct=$(((_TOTAL_ORIGINAL_BYTES - _TOTAL_OPTIMIZED_BYTES) * 100 / _TOTAL_ORIGINAL_BYTES))
    fi

    echo "## Context Manifest"
    echo ""
    echo "| Property | Value |"
    echo "|----------|-------|"
    echo "| Files Processed | $_TOTAL_FILES_PROCESSED |"
    echo "| Optimization Mode | $mode |"
    echo "| Token Estimate (before) | ~$original_tokens |"
    echo "| Token Estimate (after) | ~$optimized_tokens |"
    echo "| Token Savings | ${savings_pct}% |"

    # Add detailed breakdown if there are files
    if [[ $_TOTAL_FILES_PROCESSED -gt 0 ]]; then
        echo ""
        echo "### Optimization Details"
        echo "| File | Original | Optimized | Method |"
        echo "|------|----------|-----------|--------|"

        # Iterate through tracked files
        for key in $(map_keys "ORIGINAL_SIZES"); do
            local orig
            local opt
            local method
            orig=$(map_get "ORIGINAL_SIZES" "$key")
            opt=$(map_get "OPTIMIZED_SIZES" "$key")
            method=$(map_get "OPTIMIZATION_APPLIED" "$key")
            # Convert key back to something readable (approximate)
            local display_name
            display_name=$(echo "$key" | tr '_' '/')
            echo "| $display_name | ${orig}B | ${opt}B | $method |"
        done
    fi

    # Add symbol map if compression was used
    _generate_symbol_map_section

    echo ""
}

# =============================================================================
# PARAMETERS VALIDATION
# =============================================================================

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <output_file> \"question\" [file1] [file2] ..." >&2
    echo "" >&2
    echo "Environment variables:" >&2
    echo "  TOKEN_OPTIMIZATION_MODE  - none, basic, ast, full (default: ast)" >&2
    echo "  ENABLE_AST_EXTRACTION    - true/false (default: true)" >&2
    echo "  ENABLE_SYMBOL_COMPRESSION - true/false (default: false)" >&2
    echo "  ENABLE_SEMANTIC_CHUNKING - true/false (default: true)" >&2
    echo "  MAX_CONTEXT_FILE_BYTES   - threshold in bytes (default: 8000)" >&2
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

# =============================================================================
# BUILD CONTEXT
# =============================================================================

# Determine effective optimization mode
EFFECTIVE_MODE=$(_determine_effective_mode "$TOKEN_OPTIMIZATION_MODE")
log_info "Building context with optimization mode: $EFFECTIVE_MODE"

# Reset statistics
_reset_stats

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
                lang=$(_get_lang_for_extension "$extension")

                echo "### File: \`$file_path\`"
                echo ""

                echo "\`\`\`$lang"
                # Use intelligent optimization
                _optimize_file_content "$file_path" "$EFFECTIVE_MODE" "$lang"
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

} > "${OUTPUT_FILE}.tmp"

# Now prepend the manifest to the output
{
    echo "# Project Context"
    echo ""

    # Generate manifest with statistics
    _generate_manifest "$EFFECTIVE_MODE"

    # Append the rest of the content (skip the first "# Project Context" line)
    tail -n +3 "${OUTPUT_FILE}.tmp"

} > "$OUTPUT_FILE"

# Clean up temp file
rm -f "${OUTPUT_FILE}.tmp"

# Log final statistics
_log_optimization_stats

# Output: path of created file (for use in scripts)
echo "$OUTPUT_FILE"
