#!/bin/bash
# test_functions.sh - Unit tests for common functions
# This provides a simple test harness for bash functions without external dependencies

# Source the functions to test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Colors for output (match existing logging)
C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"

# Test assertion functions
assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    if [[ "$actual" != "$expected" ]]; then
        echo -e "${C_RED}FAIL${C_RESET}: $message"
        echo -e "  ${C_BLUE}Expected${C_RESET}: $expected"
        echo -e "  ${C_BLUE}Actual${C_RESET}: $actual"
        return 1
    fi
    echo -e "${C_GREEN}PASS${C_RESET}: $message"
    return 0
}

assert_not_equal() {
    local not_expected="$1"
    local actual="$2"
    local message="$3"
    
    if [[ "$actual" == "$not_expected" ]]; then
        echo -e "${C_RED}FAIL${C_RESET}: $message"
        echo -e "  ${C_BLUE}Should not be${C_RESET}: $not_expected"
        echo -e "  ${C_BLUE}But got${C_RESET}: $actual"
        return 1
    fi
    echo -e "${C_GREEN}PASS${C_RESET}: $message"
    return 0
}

assert_contains() {
    local expected_substring="$1"
    local actual="$2"
    local message="$3"
    
    if [[ "$actual" != *"$expected_substring"* ]]; then
        echo -e "${C_RED}FAIL${C_RESET}: $message"
        echo -e "  ${C_BLUE}Expected to contain${C_RESET}: $expected_substring"
        echo -e "  ${C_BLUE}Actual${C_RESET}: $actual"
        return 1
    fi
    echo -e "${C_GREEN}PASS${C_RESET}: $message"
    return 0
}

assert_success() {
    local command="$1"
    local message="$2"
    
    if ! eval "$command" >/dev/null 2>&1; then
        echo -e "${C_RED}FAIL${C_RESET}: $message"
        echo -e "  ${C_BLUE}Command failed${C_RESET}: $command"
        return 1
    fi
    echo -e "${C_GREEN}PASS${C_RESET}: $message"
    return 0
}

assert_failure() {
    local command="$1"
    local message="$2"
    
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${C_RED}FAIL${C_RESET}: $message"
        echo -e "  ${C_BLUE}Command should have failed${C_RESET}: $command"
        return 1
    fi
    echo -e "${C_GREEN}PASS${C_RESET}: $message"
    return 0
}

# Test functions from common.sh

test_validate_file_path() {
    echo -e "\n${C_YELLOW}Testing validate_file_path()${C_RESET}"
    
    # Test valid relative path
    assert_success "validate_file_path 'test.txt'" "Valid relative path accepted"
    
    # Test valid path with spaces
    assert_success "validate_file_path 'test file.txt'" "Path with spaces accepted"
    
    # Test path traversal detection
    assert_failure "validate_file_path '../test.txt'" "Path traversal detected and rejected"
    
    # Test absolute path rejection (default behavior)
    assert_failure "validate_file_path '/etc/passwd'" "Absolute path rejected by default"
    
    # Test absolute path allowed when flag is set
    assert_success "validate_file_path '/tmp/test.txt' true" "Absolute path allowed with flag"
    
    # Test sensitive path rejection
    assert_failure "validate_file_path '/etc/test'" "Sensitive path /etc rejected"
    
    # Test empty path rejection
    assert_failure "validate_file_path ''" "Empty path rejected"
}

test_sanitize_filename() {
    echo -e "\n${C_YELLOW}Testing sanitize_filename()${C_RESET}"
    
    # Test basic sanitization
    local result=$(sanitize_filename "Test File.txt")
    assert_equal "Test_File.txt" "$result" "Basic sanitization works"
    
    # Test special character removal
    result=$(sanitize_filename "test@#file!.txt")
    assert_equal "test_file_.txt" "$result" "Special characters removed"
    
    # Test length limiting
    long_name=$(printf 'a%.0s' {1..300})
    result=$(sanitize_filename "$long_name")
    local length=${#result}
    assert_equal 255 "$length" "Long filenames truncated to 255 chars"
    
    # Test control character removal
    result=$(sanitize_filename $'test\nfile\r.txt')
    assert_equal "testfile.txt" "$result" "Control characters removed"
}

test_case_conversion() {
    echo -e "\n${C_YELLOW}Testing case conversion functions${C_RESET}"
    
    # Test to_upper
    result=$(to_upper "hello world")
    assert_equal "HELLOWORLD" "$result" "to_upper converts to uppercase and removes spaces"
    
    # Test to_lower
    result=$(to_lower "HELLO WORLD")
    assert_equal "hello_world" "$result" "to_lower converts to lowercase and replaces spaces with underscores"
    
    # Test to_title
    result=$(to_title "HELLO")
    assert_equal "Hello" "$result" "to_title capitalizes first letter"
}

test_token_estimation() {
    echo -e "\n${C_YELLOW}Testing token estimation functions${C_RESET}"
    
    # Test basic token estimation
    result=$(estimate_tokens "Hello world")
    assert_equal 2 "$result" "Simple text token estimation"
    
    # Test empty string
    result=$(estimate_tokens "")
    assert_equal 0 "$result" "Empty string returns 0 tokens"
    
    # Test longer text (4 chars per token approximation)
    result=$(estimate_tokens "The quick brown fox jumps over the lazy dog")
    assert_equal 10 "$result" "Longer text token estimation (44 chars = 11 tokens)"
}

test_map_functions() {
    echo -e "\n${C_YELLOW}Testing map functions (Bash 3.2 compatible)${C_RESET}"
    
    # Clear any existing map
    map_clear "TESTMAP" 2>/dev/null || true
    
    # Test map_set and map_get
    map_set "TESTMAP" "key1" "value1"
    result=$(map_get "TESTMAP" "key1")
    assert_equal "value1" "$result" "Map set and get works"
    
    # Test map_has
    assert_success "map_has 'TESTMAP' 'key1'" "Map has key detection works"
    assert_failure "map_has 'TESTMAP' 'nonexistent'" "Map has returns false for missing key"
    
    # Test map_keys
    map_set "TESTMAP" "key2" "value2"
    keys=$(map_keys "TESTMAP")
    assert_contains "key1" "$keys" "Map keys contains first key"
    assert_contains "key2" "$keys" "Map keys contains second key"
    
    # Clean up
    map_clear "TESTMAP"
}

# Main test runner
run_tests() {
    echo -e "${C_BLUE}=== Running Unit Tests ===${C_RESET}"
    
    local passed=0
    local failed=0
    local start_time=$(date +%s)
    
    # Run all test functions
    for test_func in $(declare -F | grep '^declare -f test_' | cut -d' ' -f3 | sort); do
        if $test_func; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "\n${C_BLUE}=== Test Results ===${C_RESET}"
    echo -e "${C_GREEN}Passed${C_RESET}: $passed"
    echo -e "${C_RED}Failed${C_RESET}: $failed"
    echo -e "${C_BLUE}Duration${C_RESET}: ${duration}s"
    
    if [[ $failed -gt 0 ]]; then
        echo -e "\n${C_RED}Some tests failed!${C_RESET}"
        return 1
    else
        echo -e "\n${C_GREEN}All tests passed!${C_RESET}"
        return 0
    fi
}

# Execute tests
run_tests
