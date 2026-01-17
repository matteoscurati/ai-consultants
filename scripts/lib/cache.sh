#!/bin/bash
# cache.sh - Semantic caching for AI Consultants v2.3
#
# Caches consultation responses based on semantic fingerprints
# to avoid redundant API calls for similar queries.

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

CACHE_DIR="${CACHE_DIR:-/tmp/ai_consultants_cache}"
CACHE_TTL_HOURS="${CACHE_TTL_HOURS:-24}"

# =============================================================================
# CACHE INITIALIZATION
# =============================================================================

# Initialize cache directory
# Usage: init_cache
init_cache() {
    if [[ ! -d "$CACHE_DIR" ]]; then
        mkdir -p "$CACHE_DIR"
        chmod 700 "$CACHE_DIR"
    fi
}

# =============================================================================
# FINGERPRINT GENERATION
# =============================================================================

# Normalize query for consistent hashing
# Usage: _normalize_query <query>
_normalize_query() {
    local query="$1"
    # Lowercase, remove extra whitespace, trim
    echo "$query" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Calculate checksum for a file
# Usage: _file_checksum <file_path>
_file_checksum() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if command -v md5sum &>/dev/null; then
            md5sum "$file" 2>/dev/null | cut -d' ' -f1
        elif command -v md5 &>/dev/null; then
            md5 -q "$file" 2>/dev/null
        else
            # Fallback: use file size and mtime
            stat -f "%z%m" "$file" 2>/dev/null || stat -c "%s%Y" "$file" 2>/dev/null || echo "0"
        fi
    else
        echo ""
    fi
}

# Generate semantic fingerprint for a query + context
# Usage: generate_fingerprint <query> <category> [context_file]
generate_fingerprint() {
    local query="$1"
    local category="${2:-GENERAL}"
    local context_file="${3:-}"

    # Normalize query
    local normalized_query
    normalized_query=$(_normalize_query "$query")

    # Build fingerprint components
    local fingerprint_input="${normalized_query}|${category}"

    # Add context checksum if provided
    if [[ -n "$context_file" && -f "$context_file" ]]; then
        local context_checksum
        context_checksum=$(_file_checksum "$context_file")
        fingerprint_input+="|${context_checksum}"
    fi

    # Generate hash
    if command -v sha256sum &>/dev/null; then
        echo -n "$fingerprint_input" | sha256sum | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        echo -n "$fingerprint_input" | shasum -a 256 | cut -d' ' -f1
    else
        # Fallback to md5
        if command -v md5sum &>/dev/null; then
            echo -n "$fingerprint_input" | md5sum | cut -d' ' -f1
        elif command -v md5 &>/dev/null; then
            echo -n "$fingerprint_input" | md5
        else
            # Last resort: simple hash
            echo -n "$fingerprint_input" | cksum | cut -d' ' -f1
        fi
    fi
}

# =============================================================================
# CACHE OPERATIONS
# =============================================================================

# Check if semantic caching is enabled
# Usage: is_cache_enabled
is_cache_enabled() {
    [[ "${ENABLE_SEMANTIC_CACHE:-true}" == "true" ]]
}

# Get cache file path for a fingerprint
# Usage: _get_cache_path <fingerprint> <consultant>
_get_cache_path() {
    local fingerprint="$1"
    local consultant="${2:-all}"
    echo "${CACHE_DIR}/${consultant}_${fingerprint}.json"
}

# Get cache age in hours
# Usage: _get_cache_age_hours <cache_file>
_get_cache_age_hours() {
    local cache_file="$1"

    if [[ ! -f "$cache_file" ]]; then
        echo "999999"  # Very old
        return
    fi

    local now
    local file_time
    local age_seconds

    now=$(date +%s)

    # Get file modification time
    if stat -f %m "$cache_file" &>/dev/null; then
        # macOS
        file_time=$(stat -f %m "$cache_file")
    elif stat -c %Y "$cache_file" &>/dev/null; then
        # Linux
        file_time=$(stat -c %Y "$cache_file")
    else
        echo "999999"
        return
    fi

    age_seconds=$((now - file_time))
    echo $((age_seconds / 3600))
}

# Check cache for a response
# Usage: check_cache <query> <category> <consultant> [context_file]
# Returns: cached response JSON if found and valid, empty otherwise
check_cache() {
    local query="$1"
    local category="${2:-GENERAL}"
    local consultant="${3:-all}"
    local context_file="${4:-}"

    # Check if caching is enabled
    if ! is_cache_enabled; then
        return 1
    fi

    init_cache

    local fingerprint
    fingerprint=$(generate_fingerprint "$query" "$category" "$context_file")

    local cache_file
    cache_file=$(_get_cache_path "$fingerprint" "$consultant")

    # Check if cache file exists
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    # Check TTL
    local age_hours
    age_hours=$(_get_cache_age_hours "$cache_file")
    local ttl="${CACHE_TTL_HOURS:-24}"

    if [[ $age_hours -ge $ttl ]]; then
        # Cache expired
        rm -f "$cache_file" 2>/dev/null || true
        return 1
    fi

    # Return cached content
    cat "$cache_file"
    return 0
}

# Store response in cache
# Usage: store_cache <query> <category> <consultant> <response_json> [context_file]
store_cache() {
    local query="$1"
    local category="${2:-GENERAL}"
    local consultant="${3:-all}"
    local response="$4"
    local context_file="${5:-}"

    # Check if caching is enabled
    if ! is_cache_enabled; then
        return 0
    fi

    init_cache

    local fingerprint
    fingerprint=$(generate_fingerprint "$query" "$category" "$context_file")

    local cache_file
    cache_file=$(_get_cache_path "$fingerprint" "$consultant")

    # Store response with metadata
    local timestamp
    timestamp=$(date -Iseconds)

    # Add cache metadata to response
    local cached_response
    cached_response=$(echo "$response" | jq --arg ts "$timestamp" --arg fp "$fingerprint" \
        '. + {cache_metadata: {cached_at: $ts, fingerprint: $fp, from_cache: false}}' 2>/dev/null || echo "$response")

    echo "$cached_response" > "$cache_file"
    chmod 600 "$cache_file"
}

# Invalidate cache for a specific query
# Usage: invalidate_cache <query> <category> [consultant] [context_file]
invalidate_cache() {
    local query="$1"
    local category="${2:-GENERAL}"
    local consultant="${3:-}"
    local context_file="${4:-}"

    init_cache

    local fingerprint
    fingerprint=$(generate_fingerprint "$query" "$category" "$context_file")

    if [[ -n "$consultant" ]]; then
        # Invalidate specific consultant cache
        local cache_file
        cache_file=$(_get_cache_path "$fingerprint" "$consultant")
        rm -f "$cache_file" 2>/dev/null || true
    else
        # Invalidate all caches for this fingerprint
        rm -f "${CACHE_DIR}"/*_"${fingerprint}".json 2>/dev/null || true
    fi
}

# Clear all expired cache entries
# Usage: cleanup_cache
cleanup_cache() {
    init_cache

    local ttl="${CACHE_TTL_HOURS:-24}"
    local count=0

    for cache_file in "$CACHE_DIR"/*.json; do
        if [[ -f "$cache_file" ]]; then
            local age_hours
            age_hours=$(_get_cache_age_hours "$cache_file")

            if [[ $age_hours -ge $ttl ]]; then
                rm -f "$cache_file" 2>/dev/null || true
                ((count++)) || true
            fi
        fi
    done

    echo "$count"
}

# Clear all cache entries
# Usage: clear_cache
clear_cache() {
    init_cache
    rm -f "$CACHE_DIR"/*.json 2>/dev/null || true
}

# =============================================================================
# CACHE STATISTICS
# =============================================================================

# Get cache statistics
# Usage: get_cache_stats
get_cache_stats() {
    init_cache

    local total_files=0
    local total_size=0
    local expired_files=0
    local ttl="${CACHE_TTL_HOURS:-24}"

    for cache_file in "$CACHE_DIR"/*.json; do
        if [[ -f "$cache_file" ]]; then
            ((total_files++)) || true

            local file_size
            if stat -f %z "$cache_file" &>/dev/null; then
                file_size=$(stat -f %z "$cache_file")
            else
                file_size=$(stat -c %s "$cache_file" 2>/dev/null || echo 0)
            fi
            total_size=$((total_size + file_size))

            local age_hours
            age_hours=$(_get_cache_age_hours "$cache_file")
            if [[ $age_hours -ge $ttl ]]; then
                ((expired_files++)) || true
            fi
        fi
    done

    local size_kb=$((total_size / 1024))

    cat << EOF
{
  "total_entries": $total_files,
  "expired_entries": $expired_files,
  "total_size_kb": $size_kb,
  "cache_dir": "$CACHE_DIR",
  "ttl_hours": $ttl,
  "enabled": $(is_cache_enabled && echo "true" || echo "false")
}
EOF
}

# Mark response as from cache (for logging/metrics)
# Usage: mark_from_cache <response_json>
mark_from_cache() {
    local response="$1"
    echo "$response" | jq '.cache_metadata.from_cache = true' 2>/dev/null || echo "$response"
}
