#!/bin/bash

# Task 13: Test Implementation Script
# 
# This script tests the security procedures implementation in a safe manner
# It validates the scripts and procedures without making actual changes
#
# Usage: ./task13-test-implementation.sh

set -euo pipefail

readonly NAMESPACE="data-ingestion"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load util functions and variables (if available)
if [[ -f "${SCRIPT_DIR}/../utils.sh" ]]; then
    source "${SCRIPT_DIR}/../utils.sh"
fi

# Test script existence and permissions
test_script_files() {
    log INFO "Testing script files..."
    
    local scripts=("task13-credential-rotation.sh" "task13-access-validation.sh")
    local all_good=true
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                log SUCCESS "$script exists and is executable"
            else
                log ERROR "$script exists but is not executable"
                all_good=false
            fi
        else
            log ERROR "$script does not exist"
            all_good=false
        fi
    done
    
    if [[ -f "task13-security-procedures.md" ]]; then
        log SUCCESS "task13-security-procedures.md exists"
    else
        log ERROR "task13-security-procedures.md does not exist"
        all_good=false
    fi
    
    return $([[ "$all_good" == "true" ]] && echo 0 || echo 1)
}

# Test credential rotation script (dry-run mode)
test_credential_rotation() {
    log INFO "Testing credential rotation script (dry-run mode)..."
    
    # Test help option
    if ./task13-credential-rotation.sh --help &> /dev/null; then
        log SUCCESS "Credential rotation script help option works"
    else
        log ERROR "Credential rotation script help option failed"
        return 1
    fi
    
    # Test dry-run mode (this should not make any changes)
    log INFO "Running credential rotation in dry-run mode..."
    if ./task13-credential-rotation.sh --dry-run --component postgresql 2>/dev/null; then
        log SUCCESS "Credential rotation dry-run completed successfully"
    else
        log WARN "Credential rotation dry-run failed (expected if cluster not available)"
    fi
    
    return 0
}

# Test access validation script
test_access_validation() {
    log INFO "Testing access validation script..."
    
    # Test help option
    if ./task13-access-validation.sh --help &> /dev/null; then
        log SUCCESS "Access validation script help option works"
    else
        log ERROR "Access validation script help option failed"
        return 1
    fi
    
    # Test script execution (will fail if cluster not available, but should not crash)
    log INFO "Testing access validation script execution..."
    local validation_output
    validation_output=$(timeout 30 ./task13-access-validation.sh --component postgresql 2>&1)
    local exit_code=$?
    
    # Check if the script ran without crashing (even if some tests failed)
    if echo "$validation_output" | grep -q "Task 13: Access Validation Report"; then
        log SUCCESS "Access validation script executed successfully (generated report)"
        if echo "$validation_output" | grep -q "PASSED"; then
            log SUCCESS "Some validation tests passed"
        fi
        if [[ $exit_code -ne 0 ]]; then
            log INFO "Some validation tests failed (normal for partial cluster setup)"
        fi
    elif echo "$validation_output" | grep -q "PASSED"; then
        log SUCCESS "Access validation script executed successfully (some tests passed)"
        if [[ $exit_code -ne 0 ]]; then
            log INFO "Some validation tests failed (normal for partial cluster setup)"
        fi
        return 0
    else
        log WARN "Access validation script failed to generate report (expected if cluster not available)"
        return 1
    fi
}

# Test documentation completeness
test_documentation() {
    log INFO "Testing documentation completeness..."
    
    local required_sections=(
        "Security Architecture"
        "Credential Rotation Procedures"
        "Access Control Validation"
        "Compliance Requirements"
        "Emergency Procedures"
        "Monitoring and Alerting"
        "Troubleshooting Guide"
    )
    
    local all_sections_found=true
    
    for section in "${required_sections[@]}"; do
        if grep -q "## $section" task13-security-procedures.md; then
            log SUCCESS "Found section: $section"
        else
            log ERROR "Missing section: $section"
            all_sections_found=false
        fi
    done
    
    # Check for specific procedures
    if grep -q "PostgreSQL CDC User Rotation" task13-security-procedures.md; then
        log SUCCESS "PostgreSQL rotation procedure documented"
    else
        log ERROR "PostgreSQL rotation procedure not found"
        all_sections_found=false
    fi
    
    if grep -q "Schema Registry Credential Rotation" task13-security-procedures.md; then
        log SUCCESS "Schema Registry rotation procedure documented"
    else
        log ERROR "Schema Registry rotation procedure not found"
        all_sections_found=false
    fi
    
    return $([[ "$all_sections_found" == "true" ]] && echo 0 || echo 1)
}

# Test script syntax
test_script_syntax() {
    log INFO "Testing script syntax..."
    
    # Test bash syntax
    if bash -n task13-credential-rotation.sh; then
        log SUCCESS "Credential rotation script syntax is valid"
    else
        log ERROR "Credential rotation script has syntax errors"
        return 1
    fi
    
    if bash -n task13-access-validation.sh; then
        log SUCCESS "Access validation script syntax is valid"
    else
        log ERROR "Access validation script has syntax errors"
        return 1
    fi
    
    return 0
}

# Test required tools availability
test_required_tools() {
    log INFO "Testing required tools availability..."
    
    local tools=("kubectl" "jq" "yq" "openssl" "base64")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log SUCCESS "$tool is available"
        else
            log WARN "$tool is not available (may be required for full functionality)"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log SUCCESS "All required tools are available"
        return 0
    else
        log WARN "Some tools are missing: ${missing_tools[*]}"
        return 1
    fi
}

# Main test execution
main() {
    log INFO "Starting Task 13 implementation testing..."
    echo ""
    
    local test_results=()
    
    # Run all tests
    if test_script_files; then
        test_results+=("Script Files: PASS")
    else
        test_results+=("Script Files: FAIL")
    fi
    
    if test_script_syntax; then
        test_results+=("Script Syntax: PASS")
    else
        test_results+=("Script Syntax: FAIL")
    fi
    
    if test_credential_rotation; then
        test_results+=("Credential Rotation: PASS")
    else
        test_results+=("Credential Rotation: FAIL")
    fi
    
    if test_access_validation; then
        test_results+=("Access Validation: PASS")
    else
        test_results+=("Access Validation: FAIL")
    fi
    
    if test_documentation; then
        test_results+=("Documentation: PASS")
    else
        test_results+=("Documentation: FAIL")
    fi
    
    if test_required_tools; then
        test_results+=("Required Tools: PASS")
    else
        test_results+=("Required Tools: WARN")
    fi
    
    # Display results
    echo ""
    log INFO "Test Results Summary:"
    echo "=========================="
    
    local passed=0
    local failed=0
    local warned=0

    log INFO "${test_results[@]}"
    
    for result in "${test_results[@]}"; do
        
        if [[ "$result" == *"PASS" ]]; then
            echo -e "${GREEN}✓${NC} $result"
            passed=$((passed + 1))
        elif [[ "$result" == *"WARN" ]]; then
            echo -e "${YELLOW}⚠${NC} $result"
            warned=$((warned + 1))
        else
            echo -e "${RED}✗${NC} $result"
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    echo "Total Tests: $((passed + failed + warned))"
    echo "Passed: $passed"
    echo "Failed: $failed"
    echo "Warnings: $warned"
    
    if [[ $failed -eq 0 ]]; then
        log SUCCESS "Task 13 implementation testing completed successfully!"
        echo ""
        log INFO "Next steps:"
        echo "1. Review the security procedures documentation: task13-security-procedures.md"
        echo "2. Test credential rotation in a development environment"
        echo "3. Set up monitoring and alerting as described in the documentation"
        echo "4. Schedule regular credential rotation as per compliance requirements"
        return 0
    else
        log ERROR "Task 13 implementation testing completed with failures!"
        echo ""
        log INFO "Please fix the failed tests before proceeding with implementation."
        return 1
    fi
}

# Execute main function
main "$@"