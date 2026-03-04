#!/bin/bash
# symbol_map.sh - Symbol compression for AI Consultants v2.1
# Replaces long identifiers with short symbols (f1, v1, c1) to reduce tokens.

# Source common utilities
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCRIPT_DIR/common.sh" 2>/dev/null || true

# Logging stubs if common.sh unavailable
if ! command -v log_debug &>/dev/null; then
    log_debug() { :; }
    log_info() { echo "[INFO] $1" >&2; }
    log_warn() { echo "[WARN] $1" >&2; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

# Map function stubs if common.sh unavailable
if ! command -v map_set &>/dev/null; then
    _SYMBOL_MAP_FILE="/tmp/symbol_map_$$"
    map_clear() { rm -f "${_SYMBOL_MAP_FILE}_$1" 2>/dev/null; touch "${_SYMBOL_MAP_FILE}_$1"; }
    map_set() { echo "$2=$3" >> "${_SYMBOL_MAP_FILE}_$1"; }
    map_get() { grep "^$2=" "${_SYMBOL_MAP_FILE}_$1" 2>/dev/null | tail -1 | cut -d= -f2-; }
    map_has() { grep -q "^$2=" "${_SYMBOL_MAP_FILE}_$1" 2>/dev/null; }
    map_keys() { cut -d= -f1 "${_SYMBOL_MAP_FILE}_$1" 2>/dev/null | sort -u | tr '\n' ' '; }
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable/disable symbol compression
ENABLE_SYMBOL_COMPRESSION="${ENABLE_SYMBOL_COMPRESSION:-true}"

# Minimum identifier length to compress (shorter ones are kept as-is)
MIN_IDENTIFIER_LENGTH="${MIN_IDENTIFIER_LENGTH:-8}"

# Preserve exported/public names (function exports, class exports)
PRESERVE_EXPORTS="${PRESERVE_EXPORTS:-true}"

# =============================================================================
# LANGUAGE KEYWORDS (preserved, not compressed)
# =============================================================================

# Common keywords across multiple languages
KEYWORDS_COMMON="if else elif fi then for while do done case esac in return break continue function"

# JavaScript/TypeScript keywords
KEYWORDS_JS="const let var function class extends implements interface type enum async await import export default from new this super static public private protected readonly typeof instanceof void null undefined true false try catch finally throw"

# Python keywords
KEYWORDS_PYTHON="def class return if elif else for while in not and or is None True False import from as try except finally raise with lambda pass break continue global nonlocal assert yield del"

# Go keywords
KEYWORDS_GO="func package import var const type struct interface map chan go defer return if else for range switch case default break continue fallthrough select"

# Java/C# keywords
KEYWORDS_JAVA="public private protected static final abstract class interface extends implements new this super return if else for while do switch case default break continue try catch finally throw throws void int long float double boolean char String null true false import package"

# Rust keywords
KEYWORDS_RUST="fn let mut const static struct enum impl trait pub mod use crate self super where async await move return if else for while loop match break continue"

# Bash keywords
KEYWORDS_BASH="if then else elif fi case esac for while until do done in function return exit local export readonly declare typeset source"

# All keywords combined (space-separated)
ALL_KEYWORDS="$KEYWORDS_COMMON $KEYWORDS_JS $KEYWORDS_PYTHON $KEYWORDS_GO $KEYWORDS_JAVA $KEYWORDS_RUST $KEYWORDS_BASH"

# =============================================================================
# BUILT-IN FUNCTIONS (preserved)
# =============================================================================

BUILTINS_JS="console log warn error info debug setTimeout setInterval clearTimeout clearInterval fetch Promise JSON Math Array Object String Number Date RegExp Map Set parseInt parseFloat isNaN isFinite encodeURI decodeURI require module exports"

BUILTINS_PYTHON="print len range type str int float list dict set tuple bool open input abs min max sum sorted reversed enumerate zip map filter any all isinstance issubclass hasattr getattr setattr delattr"

BUILTINS_GO="fmt Println Printf Sprintf Errorf make len cap append copy delete panic recover new close"

BUILTINS_BASH="echo printf read eval exec source exit return test true false cd pwd ls cat grep sed awk cut sort uniq wc head tail tr"

ALL_BUILTINS="$BUILTINS_JS $BUILTINS_PYTHON $BUILTINS_GO $BUILTINS_BASH"

# =============================================================================
# SYMBOL COUNTERS (use file-based counters for Bash 3.2 subshell compatibility)
# =============================================================================

# Temporary files (avoids subshell variable isolation issues)
_SYM_COUNTER_FILE="${TMPDIR:-/tmp}/.symbol_map_counters_$$"
_SYM_MAP_FILE="${TMPDIR:-/tmp}/.symbol_map_json_$$"

# Initialize counter file
_init_symbol_counters() {
    cat > "$_SYM_COUNTER_FILE" << 'EOF'
_SYM_FUNC_COUNTER=0
_SYM_VAR_COUNTER=0
_SYM_CLASS_COUNTER=0
_SYM_METHOD_COUNTER=0
_SYM_TYPE_COUNTER=0
EOF
}

# Reset all counters
_reset_symbol_counters() {
    _init_symbol_counters
}

# Load current counter values
_load_symbol_counters() {
    if [[ -f "$_SYM_COUNTER_FILE" ]]; then
        source "$_SYM_COUNTER_FILE"
    else
        _init_symbol_counters
        source "$_SYM_COUNTER_FILE"
    fi
}

# Save counter values
_save_symbol_counters() {
    cat > "$_SYM_COUNTER_FILE" << EOF
_SYM_FUNC_COUNTER=$_SYM_FUNC_COUNTER
_SYM_VAR_COUNTER=$_SYM_VAR_COUNTER
_SYM_CLASS_COUNTER=$_SYM_CLASS_COUNTER
_SYM_METHOD_COUNTER=$_SYM_METHOD_COUNTER
_SYM_TYPE_COUNTER=$_SYM_TYPE_COUNTER
EOF
}

# Cleanup temporary files on exit
_cleanup_symbol_counters() {
    rm -f "$_SYM_COUNTER_FILE" 2>/dev/null
    rm -f "$_SYM_MAP_FILE" 2>/dev/null
}

# Save symbol map to file for cross-subshell access
_save_symbol_map() {
    local map_json="$1"
    echo "$map_json" > "$_SYM_MAP_FILE"
}

# Load symbol map from file
_load_symbol_map() {
    if [[ -f "$_SYM_MAP_FILE" ]]; then
        cat "$_SYM_MAP_FILE"
    else
        echo "{}"
    fi
}

# Register cleanup (only if not already registered)
if [[ -z "${_SYM_CLEANUP_REGISTERED:-}" ]]; then
    trap _cleanup_symbol_counters EXIT
    _SYM_CLEANUP_REGISTERED=1
fi

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Check if a word is a keyword or builtin
# Usage: _is_preserved_word "word"
# Returns: 0 if preserved, 1 if not
_is_preserved_word() {
    local word="$1"
    local preserved=" $ALL_KEYWORDS $ALL_BUILTINS "

    if [[ "$preserved" == *" $word "* ]]; then
        return 0
    fi
    return 1
}

# Check if identifier should be preserved (export, short, or keyword)
# Usage: _should_preserve "identifier" "is_exported"
_should_preserve() {
    local identifier="$1"
    local is_exported="${2:-false}"

    # Preserve keywords and builtins
    if _is_preserved_word "$identifier"; then
        return 0
    fi

    # Preserve short identifiers
    local len=${#identifier}
    if [[ $len -lt $MIN_IDENTIFIER_LENGTH ]]; then
        return 0
    fi

    # Preserve exports if configured
    if [[ "$PRESERVE_EXPORTS" == "true" && "$is_exported" == "true" ]]; then
        return 0
    fi

    return 1
}

# Get next symbol for a category
# Usage: _get_next_symbol "function|variable|class|method|type"
# Note: Uses file-based counters for subshell compatibility
_get_next_symbol() {
    local category="$1"
    local symbol=""

    # Load current counter values from file
    _load_symbol_counters

    case "$category" in
        function)
            _SYM_FUNC_COUNTER=$((_SYM_FUNC_COUNTER + 1))
            symbol="f${_SYM_FUNC_COUNTER}"
            ;;
        variable)
            _SYM_VAR_COUNTER=$((_SYM_VAR_COUNTER + 1))
            symbol="v${_SYM_VAR_COUNTER}"
            ;;
        class)
            _SYM_CLASS_COUNTER=$((_SYM_CLASS_COUNTER + 1))
            symbol="c${_SYM_CLASS_COUNTER}"
            ;;
        method)
            _SYM_METHOD_COUNTER=$((_SYM_METHOD_COUNTER + 1))
            symbol="m${_SYM_METHOD_COUNTER}"
            ;;
        type)
            _SYM_TYPE_COUNTER=$((_SYM_TYPE_COUNTER + 1))
            symbol="t${_SYM_TYPE_COUNTER}"
            ;;
        *)
            _SYM_VAR_COUNTER=$((_SYM_VAR_COUNTER + 1))
            symbol="v${_SYM_VAR_COUNTER}"
            ;;
    esac

    # Save updated counters back to file
    _save_symbol_counters

    echo "$symbol"
}

# Detect identifier category based on context
# Usage: _detect_category "identifier" "context_before"
_detect_category() {
    local identifier="$1"
    local context="$2"

    # Function detection patterns
    if echo "$context" | grep -qE '(function|def|func|fn)\s*$'; then
        echo "function"
        return
    fi

    # Method detection (after dot or within class)
    if echo "$context" | grep -qE '\.\s*$'; then
        echo "method"
        return
    fi

    # Class detection patterns
    if echo "$context" | grep -qE '(class|struct|interface|type)\s*$'; then
        echo "class"
        return
    fi

    # Type detection (after colon for type annotations)
    if echo "$context" | grep -qE ':\s*$'; then
        echo "type"
        return
    fi

    # Variable detection (after assignment operators, var, let, const)
    if echo "$context" | grep -qE '(var|let|const|local)\s*$'; then
        echo "variable"
        return
    fi

    # Default to variable for unrecognized patterns
    echo "variable"
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Generate a symbol map from code
# Extracts identifiers and creates mapping for compression
#
# Usage: generate_symbol_map "code"
# Output: JSON object with mappings { "originalName": {"symbol": "f1", "category": "function"}, ... }
generate_symbol_map() {
    local code="$1"

    if [[ "$ENABLE_SYMBOL_COMPRESSION" != "true" ]]; then
        echo "{}"
        return
    fi

    # Reset counters for fresh mapping
    _reset_symbol_counters

    # Clear any previous mapping
    map_clear "SYMMAP"
    map_clear "SYMMAP_CATEGORY"

    # Remove string literals and comments to avoid extracting identifiers from them
    local clean_code
    clean_code=$(echo "$code" | sed -E '
        # Remove single-line comments (// and #)
        s|//[^"]*$||g
        s|#[^"]*$||g
        # Remove multi-line comment markers (simplified)
        s|/\*[^*]*\*/||g
    ')

    # Extract potential identifiers (alphanumeric + underscore, starting with letter or underscore)
    # Pattern matches camelCase, snake_case, PascalCase identifiers
    local identifiers
    identifiers=$(echo "$clean_code" | grep -oE '\b[a-zA-Z_][a-zA-Z0-9_]*\b' | sort -u)

    local json_entries=""
    local first_entry=true

    for identifier in $identifiers; do
        # Skip if should be preserved
        if _should_preserve "$identifier" "false"; then
            continue
        fi

        # Skip if already mapped
        if map_has "SYMMAP" "$identifier"; then
            continue
        fi

        # Detect category from code context
        local context_line
        context_line=$(echo "$code" | grep -m1 -E "(^|[^a-zA-Z0-9_])$identifier([^a-zA-Z0-9_]|$)" | head -1)
        local context_before
        context_before=$(echo "$context_line" | sed -E "s/$identifier.*//")

        local category
        category=$(_detect_category "$identifier" "$context_before")

        # Get symbol for this category
        local symbol
        symbol=$(_get_next_symbol "$category")

        # Store in map
        map_set "SYMMAP" "$identifier" "$symbol"
        map_set "SYMMAP_CATEGORY" "$identifier" "$category"

        # Build JSON entry
        if [[ "$first_entry" == "true" ]]; then
            first_entry=false
        else
            json_entries="$json_entries,"
        fi

        # Escape special characters in identifier for JSON
        local safe_identifier
        safe_identifier=$(echo "$identifier" | sed 's/\\/\\\\/g; s/"/\\"/g')

        json_entries="$json_entries
    \"$safe_identifier\": {\"symbol\": \"$symbol\", \"category\": \"$category\"}"
    done

    local result="{$json_entries
}"

    # Save to file for cross-subshell access
    _save_symbol_map "$result"

    echo "$result"
}

# Portable word boundary replacement (works on BSD and GNU sed)
# Replaces identifier only when surrounded by non-word characters
# Usage: _replace_word "text" "old_word" "new_word"
_replace_word() {
    local text="$1"
    local old_word="$2"
    local new_word="$3"

    # Use sed with explicit boundary patterns (portable across BSD/GNU)
    # Match word at: start of line, after non-word char, before non-word char, end of line
    echo "$text" | sed -E "
        s/(^|[^a-zA-Z0-9_])${old_word}([^a-zA-Z0-9_]|$)/\1${new_word}\2/g
        s/(^|[^a-zA-Z0-9_])${old_word}([^a-zA-Z0-9_]|$)/\1${new_word}\2/g
    "
}

# Compress symbols in code using generated or provided map
#
# Usage: compress_symbols "code" [symbol_map_json]
# Output: Compressed code with identifiers replaced by short symbols
#         Also sets SYMBOL_MAP_JSON global variable with the map
compress_symbols() {
    local code="$1"
    local provided_map="${2:-}"

    if [[ "$ENABLE_SYMBOL_COMPRESSION" != "true" ]]; then
        echo "$code"
        return
    fi

    # Generate map if not provided
    local map_json
    if [[ -z "$provided_map" ]]; then
        map_json=$(generate_symbol_map "$code")
    else
        map_json="$provided_map"
    fi

    # Export map for later decompression
    SYMBOL_MAP_JSON="$map_json"

    # Check if map is empty
    if [[ "$map_json" == "{}" || "$map_json" == "{
}" ]]; then
        echo "$code"
        return
    fi

    local result="$code"

    # Process each mapping (extract from JSON without jq dependency for portability)
    # Parse JSON entries: "identifier": {"symbol": "f1", ...}
    local entries
    entries=$(echo "$map_json" | grep -oE '"[^"]+": \{"symbol": "[^"]+"' | sed 's/": {"symbol": "/ /; s/"//g')

    # Sort by identifier length (longest first) to avoid partial replacements
    entries=$(echo "$entries" | awk '{print length($1), $0}' | sort -rn | cut -d' ' -f2-)

    while IFS=' ' read -r identifier symbol; do
        if [[ -n "$identifier" && -n "$symbol" ]]; then
            # Replace identifier with symbol using portable word boundaries
            result=$(_replace_word "$result" "$identifier" "$symbol")
        fi
    done <<< "$entries"

    echo "$result"
}

# Get the last generated symbol map (useful after compress_symbols in subshell)
# Usage: map_json=$(get_last_symbol_map)
get_last_symbol_map() {
    _load_symbol_map
}
