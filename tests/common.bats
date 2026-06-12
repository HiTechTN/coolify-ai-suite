#!/usr/bin/env bats
# Tests unitaires pour lib/common.sh
# Utilisation: bats tests/common.bats

setup() {
    load '../lib/common.sh'
    TEST_TEMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

@test "generate_password returns non-empty string" {
    result=$(generate_password 16)
    [ -n "$result" ]
}

@test "generate_password respects length" {
    # base64 encoded, so actual length varies, but should be > 16
    result=$(generate_password 32)
    [ "${#result}" -ge 16 ]
}

@test "generate_secret returns hex string" {
    result=$(generate_secret 32)
    [[ "$result" =~ ^[0-9a-f]+$ ]]
}

@test "generate_secret returns correct length" {
    result=$(generate_secret 16)
    [ "${#result}" -eq 32 ]  # 16 bytes = 32 hex chars
}

@test "get_local_ip returns an IP" {
    result=$(get_local_ip)
    [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "log functions exist" {
    run log_info "test"
    [ "$status" -eq 0 ]
    run log_success "test"
    [ "$status" -eq 0 ]
    run log_warning "test"
    [ "$status" -eq 0 ]
    run log_error "test"
    [ "$status" -eq 0 ]
}

@test "require_root fails when not root" {
    if [ "$EUID" -eq 0 ]; then
        skip "Ne peut pas tester require_root en tant que root"
    fi
    run require_root
    [ "$status" -eq 1 ]
}
