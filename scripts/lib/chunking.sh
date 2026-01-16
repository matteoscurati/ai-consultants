#!/bin/bash
# chunking.sh - Semantic chunking for code files (Bash 3.2 compatible)

# Source common utilities
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCRIPT_DIR/common.sh" 2>/dev/null || true

# Logging stubs if common.sh unavailable
if ! command -v log_debug &>/dev/null; then
    log_debug() { :; }
    log_info() { echo "[INFO] $1" >&2; }
    log_warn() { echo "[WARN] $1" >&2; }
    log_error() { echo "[ERROR] $1" >&2; }
    estimate_tokens() { echo $(( $(echo -n "$1" | wc -c | tr -d ' ') / 4 )); }
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Maximum tokens per chunk (approximate: 1 token ~ 4 chars)
CHUNK_MAX_TOKENS="${CHUNK_MAX_TOKENS:-500}"

# Number of lines to overlap between adjacent chunks
CHUNK_OVERLAP_LINES="${CHUNK_OVERLAP_LINES:-5}"

# Priority keywords (comma-separated) for scoring chunks
CHUNK_PRIORITY_KEYWORDS="${CHUNK_PRIORITY_KEYWORDS:-main,export,public,api,handler,controller}"

# Temporary directory for chunk storage
CHUNK_TEMP_DIR="${CHUNK_TEMP_DIR:-/tmp/ai_consultants_chunks}"

# Initialize chunk storage directory with secure permissions
if [[ ! -d "$CHUNK_TEMP_DIR" ]]; then
    mkdir -p "$CHUNK_TEMP_DIR" 2>/dev/null || true
fi
chmod 700 "$CHUNK_TEMP_DIR" 2>/dev/null || true

# =============================================================================
# INTERNAL STATE (file-scoped, cleared between operations)
# =============================================================================

# Current file being processed
_CHUNK_CURRENT_FILE=""

# Chunk counter for generating IDs
_CHUNK_COUNTER=0

# Session ID for current chunking operation
_CHUNK_SESSION_ID=""

# =============================================================================
# LANGUAGE DETECTION
# =============================================================================

# Detect programming language from file extension
# Usage: _detect_language "file.py"
# Returns: python|javascript|typescript|go|java|ruby|bash|c|cpp|rust|unknown
_detect_language() {
    local file_path="$1"
    local extension="${file_path##*.}"

    case "$extension" in
        py)           echo "python" ;;
        js|mjs|cjs)   echo "javascript" ;;
        ts|tsx)       echo "typescript" ;;
        go)           echo "go" ;;
        java)         echo "java" ;;
        rb)           echo "ruby" ;;
        sh|bash)      echo "bash" ;;
        c|h)          echo "c" ;;
        cpp|cc|hpp)   echo "cpp" ;;
        rs)           echo "rust" ;;
        *)            echo "unknown" ;;
    esac
}

# =============================================================================
# PATTERN DEFINITIONS
# =============================================================================

# Get function pattern for a language
# Usage: _get_function_pattern "python"
_get_function_pattern() {
    local lang="$1"

    case "$lang" in
        python)
            echo '^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\('
            ;;
        javascript|typescript)
            # Match: function name(), async function name(), const name = () =>, const name = function()
            echo '^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\('
            ;;
        go)
            echo '^func[[:space:]]+(\([^)]+\)[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\('
            ;;
        java)
            echo '^[[:space:]]*(public|private|protected)?[[:space:]]*(static)?[[:space:]]*(void|[A-Za-z_][A-Za-z0-9_<>,]*)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\('
            ;;
        ruby)
            echo '^[[:space:]]*def[[:space:]]+[a-zA-Z_][a-zA-Z0-9_?!]*'
            ;;
        bash)
            echo '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)[[:space:]]*\{|^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*'
            ;;
        c|cpp)
            echo '^[a-zA-Z_][a-zA-Z0-9_*[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([^;]*$'
            ;;
        rust)
            echo '^[[:space:]]*(pub[[:space:]]+)?(async[[:space:]]+)?fn[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*'
            ;;
        *)
            echo '^(function|def|fn|func)[[:space:]]+[a-zA-Z_]'
            ;;
    esac
}

# Get class pattern for a language
# Usage: _get_class_pattern "python"
_get_class_pattern() {
    local lang="$1"

    case "$lang" in
        python)
            echo '^class[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*'
            ;;
        javascript|typescript)
            echo '^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?class[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*'
            ;;
        java)
            echo '^[[:space:]]*(public|private)?[[:space:]]*(abstract)?[[:space:]]*class[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*'
            ;;
        ruby)
            echo '^class[[:space:]]+[A-Z][a-zA-Z0-9_]*'
            ;;
        cpp)
            echo '^[[:space:]]*(class|struct)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*'
            ;;
        rust)
            echo '^[[:space:]]*(pub[[:space:]]+)?(struct|enum|impl)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*'
            ;;
        go)
            echo '^type[[:space:]]+[A-Z][a-zA-Z0-9_]*[[:space:]]+(struct|interface)'
            ;;
        *)
            echo '^class[[:space:]]+[a-zA-Z_]'
            ;;
    esac
}

# Get import pattern for a language
# Usage: _get_import_pattern "python"
_get_import_pattern() {
    local lang="$1"

    case "$lang" in
        python)
            echo '^(import[[:space:]]|from[[:space:]])'
            ;;
        javascript|typescript)
            echo "^(import[[:space:]]|const[[:space:]]+.*=[[:space:]]*require\(|export[[:space:]]+\{)"
            ;;
        go)
            echo '^import[[:space:]]'
            ;;
        java)
            echo '^import[[:space:]]'
            ;;
        ruby)
            echo "^(require[[:space:]]|require_relative[[:space:]]|include[[:space:]])"
            ;;
        rust)
            echo '^use[[:space:]]'
            ;;
        c|cpp)
            echo '^#include[[:space:]]'
            ;;
        *)
            echo '^import[[:space:]]'
            ;;
    esac
}

# =============================================================================
# CHECKSUM UTILITIES
# =============================================================================

# Calculate MD5 checksum of content (portable)
# Usage: _calculate_checksum "content"
_calculate_checksum() {
    local content="$1"

    # Try md5sum (Linux) first, then md5 (macOS)
    if command -v md5sum &>/dev/null; then
        echo -n "$content" | md5sum | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        echo -n "$content" | md5 -q
    else
        # Fallback: use character count and line count as pseudo-checksum
        local chars lines
        chars=$(echo -n "$content" | wc -c | tr -d ' ')
        lines=$(echo "$content" | wc -l | tr -d ' ')
        echo "fallback_${chars}_${lines}"
    fi
}

# =============================================================================
# LINE EXTRACTION UTILITIES
# =============================================================================

# Extract lines from file (1-indexed, inclusive)
# Usage: _extract_lines "file" start_line end_line
_extract_lines() {
    local file="$1"
    local start_line="$2"
    local end_line="$3"

    # Validate inputs
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    # Use sed for portable line extraction
    sed -n "${start_line},${end_line}p" "$file"
}

# Count total lines in file
# Usage: _count_lines "file"
_count_lines() {
    local file="$1"
    wc -l < "$file" | tr -d ' '
}

# =============================================================================
# SEMANTIC BOUNDARY DETECTION
# =============================================================================

# Find all semantic boundaries in a file
# Usage: _find_semantic_boundaries "file" "language"
# Output: Line numbers where semantic units start (one per line)
_find_semantic_boundaries() {
    local file="$1"
    local lang="$2"

    local func_pattern class_pattern import_pattern
    func_pattern=$(_get_function_pattern "$lang")
    class_pattern=$(_get_class_pattern "$lang")
    import_pattern=$(_get_import_pattern "$lang")

    local line_num=0
    local in_import_block=0
    local last_import_line=0
    local boundaries=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # Check for import lines (group consecutive imports)
        if echo "$line" | grep -qE "$import_pattern" 2>/dev/null; then
            if [[ $in_import_block -eq 0 ]]; then
                # Start of import block
                boundaries="${boundaries}${line_num}:import
"
                in_import_block=1
            fi
            last_import_line=$line_num
            continue
        fi

        # End import block if we've moved past imports
        if [[ $in_import_block -eq 1 && $line_num -gt $((last_import_line + 1)) ]]; then
            in_import_block=0
        fi

        # Check for class definitions
        if echo "$line" | grep -qE "$class_pattern" 2>/dev/null; then
            boundaries="${boundaries}${line_num}:class
"
            continue
        fi

        # Check for function definitions
        if echo "$line" | grep -qE "$func_pattern" 2>/dev/null; then
            boundaries="${boundaries}${line_num}:function
"
            continue
        fi

    done < "$file"

    echo -n "$boundaries"
}

# Find the end of a semantic unit (function, class, etc.)
# Usage: _find_unit_end "file" start_line unit_type language
_find_unit_end() {
    local file="$1"
    local start_line="$2"
    local unit_type="$3"
    local lang="$4"

    local total_lines
    total_lines=$(_count_lines "$file")

    # For imports, find consecutive import lines
    if [[ "$unit_type" == "import" ]]; then
        local import_pattern
        import_pattern=$(_get_import_pattern "$lang")
        local current_line=$start_line
        local last_import=$start_line

        while [[ $current_line -le $total_lines ]]; do
            local line
            line=$(sed -n "${current_line}p" "$file")

            # Check if line is empty or comment (allow gaps)
            if [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*// ]]; then
                current_line=$((current_line + 1))
                # Allow up to 2 blank lines in import block
                if [[ $current_line -gt $((last_import + 3)) ]]; then
                    break
                fi
                continue
            fi

            # Check if still in imports
            if echo "$line" | grep -qE "$import_pattern" 2>/dev/null; then
                last_import=$current_line
                current_line=$((current_line + 1))
            else
                break
            fi
        done

        echo $last_import
        return
    fi

    # For functions and classes, use brace/indent counting
    local brace_count=0
    local indent_based=0
    local base_indent=""
    local found_start=0
    local current_line=$start_line

    # Python and Ruby use indentation
    if [[ "$lang" == "python" || "$lang" == "ruby" ]]; then
        indent_based=1
        # Get base indentation of the definition line
        local def_line
        def_line=$(sed -n "${start_line}p" "$file")
        base_indent=$(echo "$def_line" | sed 's/[^[:space:]].*//')
    fi

    while [[ $current_line -le $total_lines ]]; do
        local line
        line=$(sed -n "${current_line}p" "$file")

        if [[ $indent_based -eq 1 ]]; then
            # Skip the definition line itself
            if [[ $current_line -eq $start_line ]]; then
                current_line=$((current_line + 1))
                continue
            fi

            # Skip empty lines
            if [[ -z "${line// /}" ]]; then
                current_line=$((current_line + 1))
                continue
            fi

            # Get current line's indentation
            local current_indent
            current_indent=$(echo "$line" | sed 's/[^[:space:]].*//')

            # If we've returned to base indentation (or less), we're done
            if [[ ${#current_indent} -le ${#base_indent} ]]; then
                echo $((current_line - 1))
                return
            fi
        else
            # Brace counting for C-like languages
            local open_braces close_braces

            # Count braces in line
            open_braces=$(echo "$line" | tr -cd '{' | wc -c | tr -d ' ')
            close_braces=$(echo "$line" | tr -cd '}' | wc -c | tr -d ' ')

            brace_count=$((brace_count + open_braces - close_braces))

            # Mark that we've found the opening brace
            if [[ $open_braces -gt 0 ]]; then
                found_start=1
            fi

            # If we've closed all braces after opening, we're done
            if [[ $found_start -eq 1 && $brace_count -le 0 ]]; then
                echo $current_line
                return
            fi
        fi

        current_line=$((current_line + 1))
    done

    # If we reach end of file, return last line
    echo $total_lines
}

# =============================================================================
# NESTING DEPTH CALCULATION
# =============================================================================

# Calculate maximum nesting depth in a code block
# Usage: _calculate_nesting_depth "content"
_calculate_nesting_depth() {
    local content="$1"
    local max_depth=0
    local current_depth=0

    while IFS= read -r line; do
        # Count opening and closing braces/indentation markers
        local opens closes
        opens=$(echo "$line" | tr -cd '{(' | wc -c | tr -d ' ')
        closes=$(echo "$line" | tr -cd '})' | wc -c | tr -d ' ')

        current_depth=$((current_depth + opens))
        if [[ $current_depth -gt $max_depth ]]; then
            max_depth=$current_depth
        fi
        current_depth=$((current_depth - closes))
        if [[ $current_depth -lt 0 ]]; then
            current_depth=0
        fi
    done <<< "$content"

    echo $max_depth
}

# =============================================================================
# DEPENDENCY EXTRACTION
# =============================================================================

# Extract dependencies (function/class references) from content
# Usage: _extract_dependencies "content" "language"
_extract_dependencies() {
    local content="$1"
    local lang="$2"

    local deps=""

    case "$lang" in
        python)
            # Look for function calls and class instantiations
            deps=$(echo "$content" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\(' 2>/dev/null | \
                   sed 's/($//' | sort -u | tr '\n' ',' | sed 's/,$//')
            ;;
        javascript|typescript)
            # Look for function calls, imports references
            deps=$(echo "$content" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\(' 2>/dev/null | \
                   sed 's/($//' | sort -u | tr '\n' ',' | sed 's/,$//')
            ;;
        go)
            # Look for function calls and type references
            deps=$(echo "$content" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\(' 2>/dev/null | \
                   sed 's/($//' | sort -u | tr '\n' ',' | sed 's/,$//')
            ;;
        *)
            # Generic function call detection
            deps=$(echo "$content" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\(' 2>/dev/null | \
                   sed 's/($//' | sort -u | tr '\n' ',' | sed 's/,$//')
            ;;
    esac

    echo "$deps"
}

# =============================================================================
# PRIORITY SCORING
# =============================================================================

# Calculate priority score for a chunk
# Usage: _calculate_priority "content" "chunk_type" "query_keywords"
_calculate_priority() {
    local content="$1"
    local chunk_type="$2"
    local query_keywords="${3:-}"

    local score=50  # Base score

    # Boost for entry points
    if echo "$content" | grep -qiE '(^|\s)(main|__main__|export\s+default|module\.exports)' 2>/dev/null; then
        score=$((score + 20))
    fi

    # Boost for public/exported items
    if echo "$content" | grep -qiE '(^|\s)(public|export|pub\s+fn)' 2>/dev/null; then
        score=$((score + 15))
    fi

    # Boost for API handlers
    if echo "$content" | grep -qiE '(handler|controller|endpoint|route|api)' 2>/dev/null; then
        score=$((score + 10))
    fi

    # Check against configured priority keywords
    local IFS=','
    local keywords
    read -ra keywords <<< "$CHUNK_PRIORITY_KEYWORDS"
    for keyword in "${keywords[@]}"; do
        keyword=$(echo "$keyword" | tr -d ' ')
        if [[ -n "$keyword" ]] && echo "$content" | grep -qi "$keyword" 2>/dev/null; then
            score=$((score + 5))
        fi
    done

    # Check against query-specific keywords
    if [[ -n "$query_keywords" ]]; then
        read -ra keywords <<< "$query_keywords"
        for keyword in "${keywords[@]}"; do
            keyword=$(echo "$keyword" | tr -d ' ')
            if [[ -n "$keyword" ]] && echo "$content" | grep -qi "$keyword" 2>/dev/null; then
                score=$((score + 10))
            fi
        done
    fi

    # Adjust based on complexity (moderate complexity is good)
    local lines nesting
    lines=$(echo "$content" | wc -l | tr -d ' ')
    nesting=$(_calculate_nesting_depth "$content")

    # Penalize very short chunks
    if [[ $lines -lt 5 ]]; then
        score=$((score - 10))
    fi

    # Penalize very complex chunks
    if [[ $nesting -gt 5 ]]; then
        score=$((score - 5))
    fi

    # Cap score between 0 and 100
    if [[ $score -lt 0 ]]; then
        score=0
    elif [[ $score -gt 100 ]]; then
        score=100
    fi

    echo $score
}

# =============================================================================
# CHUNK GENERATION
# =============================================================================

# Generate a unique chunk ID
# Usage: _generate_chunk_id "file_path" chunk_number
_generate_chunk_id() {
    local file_path="$1"
    local chunk_num="$2"

    local file_hash
    file_hash=$(echo -n "$file_path" | _calculate_checksum "$(cat)")

    echo "chunk_${file_hash:0:8}_${chunk_num}"
}

# Create a chunk JSON object
# Usage: _create_chunk_json id content start_line end_line type priority deps checksum
_create_chunk_json() {
    local chunk_id="$1"
    local content="$2"
    local start_line="$3"
    local end_line="$4"
    local chunk_type="$5"
    local priority="$6"
    local dependencies="$7"
    local checksum="$8"

    local lines token_estimate
    lines=$((end_line - start_line + 1))
    token_estimate=$(estimate_tokens "$content")

    # Build dependencies array
    local deps_array="[]"
    if [[ -n "$dependencies" ]]; then
        deps_array=$(echo "$dependencies" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    jq -n \
        --arg id "$chunk_id" \
        --arg content "$content" \
        --argjson start "$start_line" \
        --argjson end "$end_line" \
        --arg type "$chunk_type" \
        --argjson lines "$lines" \
        --argjson tokens "$token_estimate" \
        --argjson priority "$priority" \
        --argjson deps "$deps_array" \
        --arg checksum "$checksum" \
        '{
            id: $id,
            content: $content,
            metadata: {
                start_line: $start,
                end_line: $end,
                type: $type,
                lines: $lines,
                estimated_tokens: $tokens,
                priority: $priority,
                dependencies: $deps,
                checksum: $checksum
            }
        }'
}

# =============================================================================
# MAIN CHUNKING FUNCTION
# =============================================================================

# Split a file into semantic chunks
# Usage: chunk_file_semantically "file_path" [query_keywords]
# Output: JSON array of chunks
chunk_file_semantically() {
    local file_path="$1"
    local query_keywords="${2:-}"

    # Basic path validation (bash 3.2 compatible)
    if [[ -z "$file_path" ]]; then
        log_error "Empty file path provided"
        echo "[]"
        return 1
    fi

    # Check for path traversal
    if [[ "$file_path" == *".."* ]]; then
        log_error "Path traversal detected in: $file_path"
        echo "[]"
        return 1
    fi

    if [[ ! -f "$file_path" ]]; then
        log_error "File not found: $file_path"
        echo "[]"
        return 1
    fi

    # Initialize session
    _CHUNK_CURRENT_FILE="$file_path"
    _CHUNK_COUNTER=0
    _CHUNK_SESSION_ID=$(date +%Y%m%d_%H%M%S)_$$

    local lang
    lang=$(_detect_language "$file_path")
    log_debug "Detected language: $lang for file: $file_path"

    # Find semantic boundaries
    local boundaries
    boundaries=$(_find_semantic_boundaries "$file_path" "$lang")

    if [[ -z "$boundaries" ]]; then
        log_warn "No semantic boundaries found, chunking by token limit"
        _chunk_by_tokens "$file_path" "$query_keywords"
        return
    fi

    local total_lines
    total_lines=$(_count_lines "$file_path")

    local chunks="[]"
    local prev_end=0
    local max_chars=$((CHUNK_MAX_TOKENS * 4))  # Approximate chars from tokens

    # Process each boundary
    while IFS= read -r boundary; do
        [[ -z "$boundary" ]] && continue

        local line_num unit_type
        line_num=$(echo "$boundary" | cut -d: -f1)
        unit_type=$(echo "$boundary" | cut -d: -f2)

        # Handle gap before this boundary (if significant)
        if [[ $((line_num - 1)) -gt $((prev_end + CHUNK_OVERLAP_LINES)) ]]; then
            local gap_start=$((prev_end + 1))
            local gap_end=$((line_num - 1))

            # Only create chunk if gap has content
            local gap_content
            gap_content=$(_extract_lines "$file_path" "$gap_start" "$gap_end")

            if [[ -n "${gap_content// /}" ]]; then
                local gap_tokens
                gap_tokens=$(estimate_tokens "$gap_content")

                if [[ $gap_tokens -gt 10 ]]; then
                    _CHUNK_COUNTER=$((_CHUNK_COUNTER + 1))
                    local gap_chunk
                    gap_chunk=$(_create_chunk_for_content "$file_path" "$gap_content" "$gap_start" "$gap_end" "gap" "$lang" "$query_keywords")
                    chunks=$(echo "$chunks" | jq --argjson chunk "$gap_chunk" '. + [$chunk]')
                fi
            fi
        fi

        # Find end of this semantic unit
        local unit_end
        unit_end=$(_find_unit_end "$file_path" "$line_num" "$unit_type" "$lang")

        # Extract content with overlap
        local overlap_start=$((line_num - CHUNK_OVERLAP_LINES))
        if [[ $overlap_start -lt 1 ]]; then
            overlap_start=1
        fi

        local content
        content=$(_extract_lines "$file_path" "$overlap_start" "$unit_end")

        # Check if chunk exceeds token limit
        local token_count
        token_count=$(estimate_tokens "$content")

        if [[ $token_count -gt $CHUNK_MAX_TOKENS ]]; then
            # Split large unit into sub-chunks
            local sub_chunks
            sub_chunks=$(_split_large_unit "$file_path" "$overlap_start" "$unit_end" "$unit_type" "$lang" "$query_keywords")
            chunks=$(echo "$chunks" | jq --argjson sub "$sub_chunks" '. + $sub')
        else
            _CHUNK_COUNTER=$((_CHUNK_COUNTER + 1))
            local chunk
            chunk=$(_create_chunk_for_content "$file_path" "$content" "$overlap_start" "$unit_end" "$unit_type" "$lang" "$query_keywords")
            chunks=$(echo "$chunks" | jq --argjson chunk "$chunk" '. + [$chunk]')
        fi

        prev_end=$unit_end
    done <<< "$boundaries"

    # Handle remaining content after last boundary
    if [[ $prev_end -lt $total_lines ]]; then
        local remaining_start=$((prev_end + 1))
        local remaining_content
        remaining_content=$(_extract_lines "$file_path" "$remaining_start" "$total_lines")

        if [[ -n "${remaining_content// /}" ]]; then
            local remaining_tokens
            remaining_tokens=$(estimate_tokens "$remaining_content")

            if [[ $remaining_tokens -gt 10 ]]; then
                _CHUNK_COUNTER=$((_CHUNK_COUNTER + 1))
                local remaining_chunk
                remaining_chunk=$(_create_chunk_for_content "$file_path" "$remaining_content" "$remaining_start" "$total_lines" "trailing" "$lang" "$query_keywords")
                chunks=$(echo "$chunks" | jq --argjson chunk "$remaining_chunk" '. + [$chunk]')
            fi
        fi
    fi

    # Save chunks to session file
    local session_file="$CHUNK_TEMP_DIR/${_CHUNK_SESSION_ID}_chunks.json"
    echo "$chunks" > "$session_file"
    chmod 600 "$session_file" 2>/dev/null || true

    log_info "Created $_CHUNK_COUNTER chunks for: $file_path"
    echo "$chunks"
}

# Helper to create chunk for extracted content
# Usage: _create_chunk_for_content file content start end type lang query_keywords
_create_chunk_for_content() {
    local file_path="$1"
    local content="$2"
    local start_line="$3"
    local end_line="$4"
    local chunk_type="$5"
    local lang="$6"
    local query_keywords="$7"

    local chunk_id priority deps checksum
    chunk_id=$(_generate_chunk_id "$file_path" "$_CHUNK_COUNTER")
    priority=$(_calculate_priority "$content" "$chunk_type" "$query_keywords")
    deps=$(_extract_dependencies "$content" "$lang")
    checksum=$(_calculate_checksum "$content")

    _create_chunk_json "$chunk_id" "$content" "$start_line" "$end_line" "$chunk_type" "$priority" "$deps" "$checksum"
}

# Split a large semantic unit into smaller chunks
# Usage: _split_large_unit file start end type lang query_keywords
_split_large_unit() {
    local file_path="$1"
    local start_line="$2"
    local end_line="$3"
    local unit_type="$4"
    local lang="$5"
    local query_keywords="$6"

    local chunks="[]"
    local max_lines=$((CHUNK_MAX_TOKENS / 10))  # Rough estimate: 10 tokens per line
    local current_start=$start_line

    while [[ $current_start -le $end_line ]]; do
        local current_end=$((current_start + max_lines - 1))
        if [[ $current_end -gt $end_line ]]; then
            current_end=$end_line
        fi

        # Add overlap for non-first chunks
        local overlap_start=$current_start
        if [[ $current_start -gt $start_line ]]; then
            overlap_start=$((current_start - CHUNK_OVERLAP_LINES))
            if [[ $overlap_start -lt $start_line ]]; then
                overlap_start=$start_line
            fi
        fi

        local content
        content=$(_extract_lines "$file_path" "$overlap_start" "$current_end")

        _CHUNK_COUNTER=$((_CHUNK_COUNTER + 1))
        local chunk
        chunk=$(_create_chunk_for_content "$file_path" "$content" "$overlap_start" "$current_end" "${unit_type}_part" "$lang" "$query_keywords")
        chunks=$(echo "$chunks" | jq --argjson chunk "$chunk" '. + [$chunk]')

        current_start=$((current_end + 1))
    done

    echo "$chunks"
}

# Fallback chunking by token limit when no semantic boundaries found
# Usage: _chunk_by_tokens file query_keywords
_chunk_by_tokens() {
    local file_path="$1"
    local query_keywords="$2"

    local lang
    lang=$(_detect_language "$file_path")

    local total_lines
    total_lines=$(_count_lines "$file_path")

    local chunks="[]"
    local max_lines=$((CHUNK_MAX_TOKENS / 10))
    local current_start=1

    while [[ $current_start -le $total_lines ]]; do
        local current_end=$((current_start + max_lines - 1))
        if [[ $current_end -gt $total_lines ]]; then
            current_end=$total_lines
        fi

        # Add overlap for non-first chunks
        local overlap_start=$current_start
        if [[ $current_start -gt 1 ]]; then
            overlap_start=$((current_start - CHUNK_OVERLAP_LINES))
            if [[ $overlap_start -lt 1 ]]; then
                overlap_start=1
            fi
        fi

        local content
        content=$(_extract_lines "$file_path" "$overlap_start" "$current_end")

        _CHUNK_COUNTER=$((_CHUNK_COUNTER + 1))
        local chunk
        chunk=$(_create_chunk_for_content "$file_path" "$content" "$overlap_start" "$current_end" "token_based" "$lang" "$query_keywords")
        chunks=$(echo "$chunks" | jq --argjson chunk "$chunk" '. + [$chunk]')

        current_start=$((current_end + 1))
    done

    # Save to session file
    local session_file="$CHUNK_TEMP_DIR/${_CHUNK_SESSION_ID}_chunks.json"
    echo "$chunks" > "$session_file"
    chmod 600 "$session_file" 2>/dev/null || true

    log_info "Created $_CHUNK_COUNTER token-based chunks for: $file_path"
    echo "$chunks"
}

