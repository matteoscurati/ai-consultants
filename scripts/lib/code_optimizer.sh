#!/bin/bash
# code_optimizer.sh - AST-based code extraction to reduce token usage
# Part of AI Consultants v2.1

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

# =============================================================================
# CONFIGURATION
# =============================================================================

# Enable/disable AST-based extraction (default: true)
ENABLE_AST_EXTRACTION="${ENABLE_AST_EXTRACTION:-true}"

# Maximum lines to include in body summary
MAX_BODY_SUMMARY_LINES="${MAX_BODY_SUMMARY_LINES:-3}"

# Include docstrings in extraction
INCLUDE_DOCSTRINGS="${INCLUDE_DOCSTRINGS:-true}"

# Include critical comments (TODO, FIXME, HACK, NOTE)
INCLUDE_CRITICAL_COMMENTS="${INCLUDE_CRITICAL_COMMENTS:-true}"

# =============================================================================
# LANGUAGE DETECTION
# =============================================================================

# Detect programming language from file extension
# Usage: detect_language "/path/to/file.py"
# Returns: python, javascript, typescript, bash, go, or unknown
detect_language() {
    local file_path="$1"
    local extension=""

    # Extract extension (handle files with multiple dots)
    extension="${file_path##*.}"

    # Convert to lowercase using tr (Bash 3.2 compatible)
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')

    case "$extension" in
        py|pyw)
            echo "python"
            ;;
        js|mjs|cjs)
            echo "javascript"
            ;;
        ts|tsx|mts|cts)
            echo "typescript"
            ;;
        jsx)
            echo "javascript"
            ;;
        sh|bash|zsh)
            echo "bash"
            ;;
        go)
            echo "go"
            ;;
        rb)
            echo "ruby"
            ;;
        rs)
            echo "rust"
            ;;
        java)
            echo "java"
            ;;
        c|h)
            echo "c"
            ;;
        cpp|cc|cxx|hpp|hxx)
            echo "cpp"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# =============================================================================
# PYTHON EXTRACTOR (AST-based)
# =============================================================================

# Extract code skeleton from Python file using ast module
# Usage: _extract_python "/path/to/file.py"
_extract_python() {
    local file_path="$1"

    # Check if python3 is available
    if ! command -v python3 &>/dev/null; then
        log_warn "python3 not available, falling back to generic extractor"
        _extract_generic "$file_path"
        return
    fi

    # Convert shell booleans to Python booleans
    local py_include_docstrings="True"
    local py_include_comments="True"
    if [ "$INCLUDE_DOCSTRINGS" = "false" ]; then
        py_include_docstrings="False"
    fi
    if [ "$INCLUDE_CRITICAL_COMMENTS" = "false" ]; then
        py_include_comments="False"
    fi

    python3 -c "
import ast
import sys

def get_docstring(node):
    '''Extract docstring from a node if present'''
    try:
        return ast.get_docstring(node) or ''
    except:
        return ''

def format_args(args):
    '''Format function arguments'''
    parts = []

    # Regular args
    for arg in args.args:
        annotation = ''
        if arg.annotation:
            try:
                annotation = ': ' + ast.unparse(arg.annotation)
            except:
                pass
        parts.append(arg.arg + annotation)

    # *args
    if args.vararg:
        parts.append('*' + args.vararg.arg)

    # **kwargs
    if args.kwarg:
        parts.append('**' + args.kwarg.arg)

    return ', '.join(parts)

def get_return_annotation(node):
    '''Get return type annotation'''
    if node.returns:
        try:
            return ' -> ' + ast.unparse(node.returns)
        except:
            pass
    return ''

def extract_critical_comments(source):
    '''Extract TODO, FIXME, HACK, NOTE comments'''
    comments = []
    for i, line in enumerate(source.split('\n'), 1):
        line_stripped = line.strip()
        if line_stripped.startswith('#'):
            upper = line_stripped.upper()
            if any(marker in upper for marker in ['TODO', 'FIXME', 'HACK', 'NOTE', 'XXX', 'BUG']):
                comments.append(f'  # Line {i}: {line_stripped}')
    return comments

try:
    with open('$file_path', 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()

    tree = ast.parse(source)

    output = []
    output.append('# FILE: $file_path')
    output.append('# LANGUAGE: python')
    output.append('')

    # Extract imports
    imports = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(f'import {alias.name}')
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ''
            names = ', '.join(alias.name for alias in node.names)
            imports.append(f'from {module} import {names}')

    if imports:
        output.append('# IMPORTS:')
        for imp in imports[:20]:  # Limit to 20 imports
            output.append(imp)
        if len(imports) > 20:
            output.append(f'# ... and {len(imports) - 20} more imports')
        output.append('')

    # Extract classes and functions
    for node in ast.iter_child_nodes(tree):
        if isinstance(node, ast.ClassDef):
            output.append(f'class {node.name}:')
            docstring = get_docstring(node)
            if docstring and $py_include_docstrings:
                first_line = docstring.split('\n')[0][:100]
                output.append(f'    \"\"\"{ first_line }...\"\"\"')

            # Extract methods
            methods = []
            for item in node.body:
                if isinstance(item, ast.FunctionDef) or isinstance(item, ast.AsyncFunctionDef):
                    async_prefix = 'async ' if isinstance(item, ast.AsyncFunctionDef) else ''
                    signature = f'{async_prefix}def {item.name}({format_args(item.args)}){get_return_annotation(item)}'
                    methods.append(signature)

            if methods:
                output.append('    # Methods:')
                for m in methods:
                    output.append(f'    {m}: ...')
            output.append('')

        elif isinstance(node, ast.FunctionDef) or isinstance(node, ast.AsyncFunctionDef):
            async_prefix = 'async ' if isinstance(node, ast.AsyncFunctionDef) else ''
            signature = f'{async_prefix}def {node.name}({format_args(node.args)}){get_return_annotation(node)}:'
            output.append(signature)

            docstring = get_docstring(node)
            if docstring and $py_include_docstrings:
                first_line = docstring.split('\n')[0][:100]
                output.append(f'    \"\"\"{ first_line }...\"\"\"')
            output.append('    ...')
            output.append('')

    # Extract critical comments
    if $py_include_comments:
        comments = extract_critical_comments(source)
        if comments:
            output.append('# CRITICAL COMMENTS:')
            for c in comments[:10]:  # Limit to 10
                output.append(c)
            output.append('')

    print('\n'.join(output))

except SyntaxError as e:
    print(f'# FILE: $file_path')
    print(f'# LANGUAGE: python')
    print(f'# ERROR: Syntax error at line {e.lineno}: {e.msg}')
    print('# Falling back to basic extraction')
    sys.exit(1)
except Exception as e:
    print(f'# FILE: $file_path')
    print(f'# LANGUAGE: python')
    print(f'# ERROR: {str(e)}')
    sys.exit(1)
" 2>/dev/null

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_debug "Python AST extraction failed, using generic extractor"
        _extract_generic "$file_path"
    fi
}

# =============================================================================
# JAVASCRIPT/TYPESCRIPT EXTRACTOR (Regex-based, ctags-style)
# =============================================================================

# Extract code skeleton from JavaScript/TypeScript file
# Usage: _extract_javascript "/path/to/file.js"
_extract_javascript() {
    local file_path="$1"
    local lang="$2"

    if [ -z "$lang" ]; then
        lang=$(detect_language "$file_path")
    fi

    echo "// FILE: $file_path"
    echo "// LANGUAGE: $lang"
    echo ""

    # Extract imports/requires
    echo "// IMPORTS:"
    grep -E "^(import |const .* = require\(|export .* from )" "$file_path" 2>/dev/null | head -20
    echo ""

    # Extract interfaces (TypeScript)
    if [ "$lang" = "typescript" ]; then
        local interfaces
        interfaces=$(grep -E "^(export )?(interface|type) [A-Z]" "$file_path" 2>/dev/null)
        if [ -n "$interfaces" ]; then
            echo "// INTERFACES/TYPES:"
            echo "$interfaces" | while IFS= read -r line; do
                # Get interface name and first few properties
                echo "$line"
            done
            echo ""
        fi
    fi

    # Extract class definitions
    echo "// CLASSES:"
    grep -n "^[[:space:]]*\(export \)\?class [A-Za-z]" "$file_path" 2>/dev/null | while IFS= read -r line; do
        local line_num="${line%%:*}"
        local class_line="${line#*:}"
        echo "$class_line"

        # Extract method signatures from the class (simplified)
        # Look for methods in the next 100 lines after class declaration
        local end_line=$((line_num + 100))
        sed -n "${line_num},${end_line}p" "$file_path" 2>/dev/null | \
            grep -E "^[[:space:]]+(async )?(public |private |protected )?(static )?[a-zA-Z_][a-zA-Z0-9_]*\(" | \
            head -10 | while IFS= read -r method; do
                echo "  $method"
            done
    done
    echo ""

    # Extract function declarations
    echo "// FUNCTIONS:"
    grep -E "^(export )?(async )?(function [a-zA-Z_]|const [a-zA-Z_][a-zA-Z0-9_]* = (async )?\(|const [a-zA-Z_][a-zA-Z0-9_]* = (async )?function)" "$file_path" 2>/dev/null | head -30
    echo ""

    # Extract arrow function exports
    grep -E "^export (const|let) [a-zA-Z_][a-zA-Z0-9_]* = " "$file_path" 2>/dev/null | head -20

    # Extract critical comments
    if [ "$INCLUDE_CRITICAL_COMMENTS" = "true" ]; then
        local comments
        comments=$(grep -n -E "(//|/\*).*(TODO|FIXME|HACK|NOTE|XXX|BUG)" "$file_path" 2>/dev/null | head -10)
        if [ -n "$comments" ]; then
            echo ""
            echo "// CRITICAL COMMENTS:"
            echo "$comments"
        fi
    fi
}

# =============================================================================
# BASH EXTRACTOR
# =============================================================================

# Extract code skeleton from Bash script
# Usage: _extract_bash "/path/to/script.sh"
_extract_bash() {
    local file_path="$1"

    echo "# FILE: $file_path"
    echo "# LANGUAGE: bash"
    echo ""

    # Extract shebang
    local shebang
    shebang=$(head -1 "$file_path" 2>/dev/null)
    if [ "${shebang:0:2}" = "#!" ]; then
        echo "# SHEBANG: $shebang"
        echo ""
    fi

    # Extract source/. includes (must start with source or . followed by space and path)
    echo "# SOURCED FILES:"
    grep -E "^[[:space:]]*(source [\"'\$]|\. [\"'\$])" "$file_path" 2>/dev/null | head -10
    echo ""

    # Extract global variable assignments (uppercase variables)
    echo "# CONFIGURATION VARIABLES:"
    grep -E "^[A-Z_][A-Z0-9_]*=" "$file_path" 2>/dev/null | head -20
    echo ""

    # Extract function definitions
    echo "# FUNCTIONS:"
    grep -n -E "^[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{?" "$file_path" 2>/dev/null | while IFS= read -r line; do
        local _line_num="${line%%:*}"
        local _func_line="${line#*:}"
        local _func_name
        _func_name=$(echo "$_func_line" | sed 's/().*//')

        # Look for function comment (line before)
        local _prev_line=$((_line_num - 1))
        if [ "$_prev_line" -gt 0 ]; then
            local _comment
            _comment=$(sed -n "${_prev_line}p" "$file_path" 2>/dev/null)
            if [ "${_comment:0:1}" = "#" ]; then
                echo "$_comment"
            fi
        fi
        echo "${_func_name}()"
    done
    echo ""

    # Also check for function keyword style
    grep -E "^function [a-zA-Z_]" "$file_path" 2>/dev/null | while IFS= read -r line; do
        local _func_name
        _func_name=$(echo "$line" | sed 's/function //; s/[({].*//')
        echo "${_func_name}()"
    done

    # Extract critical comments
    if [ "$INCLUDE_CRITICAL_COMMENTS" = "true" ]; then
        local comments
        comments=$(grep -n -E "^[[:space:]]*#.*(TODO|FIXME|HACK|NOTE|XXX|BUG)" "$file_path" 2>/dev/null | head -10)
        if [ -n "$comments" ]; then
            echo ""
            echo "# CRITICAL COMMENTS:"
            echo "$comments"
        fi
    fi
}

# =============================================================================
# GO EXTRACTOR
# =============================================================================

# Extract code skeleton from Go file
# Usage: _extract_go "/path/to/file.go"
_extract_go() {
    local file_path="$1"

    echo "// FILE: $file_path"
    echo "// LANGUAGE: go"
    echo ""

    # Extract package declaration
    echo "// PACKAGE:"
    grep -E "^package " "$file_path" 2>/dev/null | head -1
    echo ""

    # Extract imports
    echo "// IMPORTS:"
    # Handle both single and multi-line imports
    local in_import_block=false
    while IFS= read -r line; do
        if echo "$line" | grep -qE "^import \("; then
            in_import_block=true
            continue
        fi
        if [ "$in_import_block" = true ]; then
            if echo "$line" | grep -qE "^\)"; then
                in_import_block=false
                continue
            fi
            echo "$line"
        fi
        if echo "$line" | grep -qE "^import \""; then
            echo "$line"
        fi
    done < "$file_path"
    echo ""

    # Extract type definitions (struct, interface)
    echo "// TYPES:"
    grep -n -E "^type [A-Z][a-zA-Z0-9_]* (struct|interface)" "$file_path" 2>/dev/null | while IFS= read -r line; do
        local line_num="${line%%:*}"
        local type_line="${line#*:}"
        echo "$type_line"

        # Get struct/interface fields (simplified)
        local end_line=$((line_num + 20))
        sed -n "$((line_num + 1)),${end_line}p" "$file_path" 2>/dev/null | while IFS= read -r field_line; do
            if echo "$field_line" | grep -qE "^\}"; then
                break
            fi
            # Print field if it starts with a capital letter (exported)
            if echo "$field_line" | grep -qE "^[[:space:]]+[A-Z]"; then
                echo "  $field_line"
            fi
        done
    done
    echo ""

    # Extract function and method definitions
    echo "// FUNCTIONS:"
    grep -E "^func " "$file_path" 2>/dev/null | while IFS= read -r line; do
        # Extract just the signature (up to opening brace)
        local signature
        signature=$(echo "$line" | sed 's/ {$//')
        echo "$signature"
    done
    echo ""

    # Extract critical comments
    if [ "$INCLUDE_CRITICAL_COMMENTS" = "true" ]; then
        local comments
        comments=$(grep -n -E "//.*( TODO| FIXME| HACK| NOTE| XXX| BUG)" "$file_path" 2>/dev/null | head -10)
        if [ -n "$comments" ]; then
            echo ""
            echo "// CRITICAL COMMENTS:"
            echo "$comments"
        fi
    fi
}

# =============================================================================
# GENERIC EXTRACTOR (Fallback)
# =============================================================================

# Generic fallback extractor using common keywords
# Usage: _extract_generic "/path/to/file"
_extract_generic() {
    local file_path="$1"
    local lang
    lang=$(detect_language "$file_path")

    echo "# FILE: $file_path"
    echo "# LANGUAGE: $lang (generic extraction)"
    echo ""

    # Extract lines with common keywords
    echo "# DEFINITIONS:"
    grep -n -E "^[[:space:]]*(public |private |protected )?(static )?(async )?(function |def |class |interface |type |struct |enum |const |let |var |import |from |require|export |module )" "$file_path" 2>/dev/null | head -50
    echo ""

    # Extract critical comments
    if [ "$INCLUDE_CRITICAL_COMMENTS" = "true" ]; then
        local comments
        comments=$(grep -n -E "(#|//|/\*).*(TODO|FIXME|HACK|NOTE|XXX|BUG)" "$file_path" 2>/dev/null | head -10)
        if [ -n "$comments" ]; then
            echo "# CRITICAL COMMENTS:"
            echo "$comments"
        fi
    fi
}

# =============================================================================
# MAIN OPTIMIZATION FUNCTION
# =============================================================================

# Optimize a code file by extracting semantic skeleton
# Usage: optimize_code_file "/path/to/file.py"
# Returns: Optimized code skeleton on stdout
optimize_code_file() {
    local file_path="$1"

    # Validate input
    if [ -z "$file_path" ]; then
        log_error "No file path provided to optimize_code_file"
        return 1
    fi

    if [ ! -f "$file_path" ]; then
        log_error "File not found: $file_path"
        return 1
    fi

    # Check if extraction is enabled
    if [ "$ENABLE_AST_EXTRACTION" != "true" ]; then
        log_debug "AST extraction disabled, returning raw file"
        cat "$file_path"
        return 0
    fi

    # Detect language
    local lang
    lang=$(detect_language "$file_path")
    log_debug "Detected language: $lang for file: $file_path"

    # Route to appropriate extractor
    case "$lang" in
        python)
            _extract_python "$file_path"
            ;;
        javascript)
            _extract_javascript "$file_path" "javascript"
            ;;
        typescript)
            _extract_javascript "$file_path" "typescript"
            ;;
        bash)
            _extract_bash "$file_path"
            ;;
        go)
            _extract_go "$file_path"
            ;;
        *)
            log_debug "Using generic extractor for: $lang"
            _extract_generic "$file_path"
            ;;
    esac
}

# =============================================================================
# BATCH OPTIMIZATION
# =============================================================================

# Optimize multiple files and combine output
# Usage: optimize_code_files file1.py file2.js ...
# Returns: Combined optimized skeletons
optimize_code_files() {
    local files=("$@")
    local total_files="${#files[@]}"
    local processed=0

    if [ "$total_files" -eq 0 ]; then
        log_warn "No files provided to optimize_code_files"
        return 1
    fi

    log_info "Optimizing $total_files code file(s)..."

    for file_path in "${files[@]}"; do
        if [ -f "$file_path" ]; then
            echo "# =============================================="
            optimize_code_file "$file_path"
            echo ""
            processed=$((processed + 1))
        else
            log_warn "Skipping non-existent file: $file_path"
        fi
    done

    log_success "Optimized $processed of $total_files files"
}

# =============================================================================
# TOKEN ESTIMATION
# =============================================================================

# Estimate token savings from optimization
# Usage: estimate_token_savings "/path/to/file.py"
# Returns: JSON with original_tokens, optimized_tokens, savings_percent
estimate_token_savings() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        log_error "File not found: $file_path"
        return 1
    fi

    # Get original size
    local original_chars
    original_chars=$(wc -c < "$file_path" | tr -d ' ')
    local original_tokens=$((original_chars / 4))

    # Get optimized size
    local optimized_content
    optimized_content=$(optimize_code_file "$file_path")
    local optimized_chars
    optimized_chars=$(echo -n "$optimized_content" | wc -c | tr -d ' ')
    local optimized_tokens=$((optimized_chars / 4))

    # Calculate savings
    local savings_percent=0
    if [ "$original_tokens" -gt 0 ]; then
        savings_percent=$(( (original_tokens - optimized_tokens) * 100 / original_tokens ))
    fi

    # Output JSON
    cat <<EOF
{
  "file": "$file_path",
  "original_tokens": $original_tokens,
  "optimized_tokens": $optimized_tokens,
  "savings_tokens": $((original_tokens - optimized_tokens)),
  "savings_percent": $savings_percent
}
EOF
}

# Check if a file should be optimized based on extension
# Usage: is_optimizable_file "/path/to/file.py"
is_optimizable_file() {
    local lang
    lang=$(detect_language "$1")
    [ "$lang" != "unknown" ]
}

