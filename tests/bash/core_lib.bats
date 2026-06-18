#!/usr/bin/env bats
#
# Tests for scripts/lib/core_lib.sh
# Covers: normalize_version_for_comparison, compare_versions

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    # Suppress color output so assertions match plain text
    export NO_COLOR=1
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/core_lib.sh"
}

# ---------------------------------------------------------------------------
# normalize_version_for_comparison
# ---------------------------------------------------------------------------

@test "normalize_version: strips leading v" {
    run normalize_version_for_comparison "v1.2.3"
    [ "$status" -eq 0 ]
    [ "$output" = "1.2.3" ]
}

@test "normalize_version: strips single trailing zero" {
    run normalize_version_for_comparison "1.2.0"
    [ "$output" = "1.2" ]
}

@test "normalize_version: strips multiple trailing zeros" {
    run normalize_version_for_comparison "1.0.0"
    [ "$output" = "1" ]
}

@test "normalize_version: keeps non-trailing zeros" {
    run normalize_version_for_comparison "1.2.3"
    [ "$output" = "1.2.3" ]
}

@test "normalize_version: keeps internal zeros" {
    run normalize_version_for_comparison "1.0.1"
    [ "$output" = "1.0.1" ]
}

@test "normalize_version: single zero stays as zero" {
    run normalize_version_for_comparison "0"
    [ "$output" = "0" ]
}

@test "normalize_version: non-numeric version returned as-is" {
    run normalize_version_for_comparison "1.2.3-ea"
    [ "$output" = "1.2.3-ea" ]
}

@test "normalize_version: strips leading whitespace" {
    run normalize_version_for_comparison "  1.2.3"
    [ "$output" = "1.2.3" ]
}

# ---------------------------------------------------------------------------
# compare_versions
# ---------------------------------------------------------------------------

@test "compare_versions: equal versions returns 0" {
    run compare_versions "1.2.3" "1.2.3"
    [ "$status" -eq 0 ]
}

@test "compare_versions: v1 greater returns 1" {
    run compare_versions "2.0.0" "1.9.9"
    [ "$status" -eq 1 ]
}

@test "compare_versions: v1 lesser returns 2" {
    run compare_versions "1.9.9" "2.0.0"
    [ "$status" -eq 2 ]
}

@test "compare_versions: minor segment correctly ordered (1.10 > 1.9)" {
    run compare_versions "1.10.0" "1.9.0"
    [ "$status" -eq 1 ]
}

@test "compare_versions: patch-level update detected (26.3.0 < 26.3.1)" {
    run compare_versions "26.3.0" "26.3.1"
    [ "$status" -eq 2 ]
}

@test "compare_versions: leading v stripped before comparing" {
    run compare_versions "v1.2.3" "1.2.3"
    [ "$status" -eq 0 ]
}

@test "compare_versions: trailing zeros normalized (1.2.0 == 1.2)" {
    run compare_versions "1.2.0" "1.2"
    [ "$status" -eq 0 ]
}

@test "compare_versions: stable release newer than alpha-suffixed pre-release" {
    run compare_versions "3.6" "3.6a"
    [ "$status" -eq 1 ]
}

@test "compare_versions: pre-release older than stable release" {
    run compare_versions "3.6a" "3.6"
    [ "$status" -eq 2 ]
}

@test "compare_versions: identical alpha-suffixed versions are equal" {
    run compare_versions "3.6a" "3.6a"
    [ "$status" -eq 0 ]
}

@test "compare_versions: major version bump detected" {
    run compare_versions "0.42.0" "1.0.0"
    [ "$status" -eq 2 ]
}
