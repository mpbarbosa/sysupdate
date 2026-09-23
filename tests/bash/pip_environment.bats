#!/usr/bin/env bats
#
# Tests for scripts/lib/upgrade_utils.sh pip-environment helpers
# Covers: pip_output_is_externally_managed, pip_failure_reason

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export NO_COLOR=1
    # upgrade_utils.sh sources core_lib.sh internally
    # shellcheck disable=SC1091
    source "$REPO_ROOT/scripts/lib/upgrade_utils.sh"
}

# ---------------------------------------------------------------------------
# pip_output_is_externally_managed
# ---------------------------------------------------------------------------

@test "pip externally managed: detects the PEP 668 refusal from real pip output" {
    run pip_output_is_externally_managed "error: externally-managed-environment

× This environment is externally managed
╰─> To install Python packages system-wide, try apt install python3-xyz"
    [ "$status" -eq 0 ]
}

@test "pip externally managed: detects the signature regardless of surrounding noise" {
    run pip_output_is_externally_managed "Collecting reportlab
error: externally-managed-environment
hint: See PEP 668 for the detailed specification."
    [ "$status" -eq 0 ]
}

@test "pip externally managed: a successful install is not flagged" {
    run pip_output_is_externally_managed "Successfully installed reportlab-5.0.1"
    [ "$status" -ne 0 ]
}

@test "pip externally managed: an unrelated pip error is not flagged" {
    run pip_output_is_externally_managed "ERROR: No matching distribution found for reportlab"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# pip_failure_reason
# ---------------------------------------------------------------------------

@test "pip failure reason: PEP 668 refusal is never reported as a build problem" {
    run pip_failure_reason "error: externally-managed-environment

× This environment is externally managed
note: If you believe this is a mistake ... --break-system-packages"
    [ "$status" -eq 0 ]
    [ "$output" = "externally-managed environment (PEP 668)" ]
}

@test "pip failure reason: a compiler failure asks for build tooling" {
    run pip_failure_reason "building 'x' extension
    fatal error: Python.h: No such file or directory
    error: command '/usr/bin/gcc' failed with exit code 1"
    [ "$output" = "build failed — needs compiler/headers" ]
}

@test "pip failure reason: a failed wheel build counts as a build failure" {
    run pip_failure_reason "  ERROR: Failed building wheel for cryptography"
    [ "$output" = "build failed — needs compiler/headers" ]
}

@test "pip failure reason: an unreachable index is reported as a network error" {
    run pip_failure_reason "WARNING: Retrying after connection broken by ProxyError
ERROR: Max retries exceeded with url: /simple/reportlab/"
    [ "$output" = "network error reaching the package index" ]
}

@test "pip failure reason: an unresolvable dependency set is reported as a conflict" {
    run pip_failure_reason "ERROR: ResolutionImpossible: for help visit https://pip.pypa.io/"
    [ "$output" = "dependency conflict" ]
}

@test "pip failure reason: a missing release is reported as no matching distribution" {
    run pip_failure_reason "ERROR: Could not find a version that satisfies the requirement svglib"
    [ "$output" = "no matching distribution for this Python" ]
}

@test "pip failure reason: an unwritable target is reported as permission denied" {
    run pip_failure_reason "ERROR: Could not install packages due to an OSError: [Errno 13] Permission denied"
    [ "$output" = "permission denied writing the target directory" ]
}

@test "pip failure reason: unrecognized output echoes pip's own last line, not a guess" {
    run pip_failure_reason "Collecting pyHanko
ERROR: Something entirely new went wrong
"
    [ "$output" = "ERROR: Something entirely new went wrong" ]
}

@test "pip failure reason: silent failure says so instead of inventing a cause" {
    run pip_failure_reason ""
    [ "$output" = "pip exited non-zero with no output" ]
}

@test "pip failure reason: a very long line is truncated to stay printable" {
    long_line="ERROR: $(printf 'x%.0s' {1..400})"
    run pip_failure_reason "$long_line"
    [ "${#output}" -le 160 ]
}

# ---------------------------------------------------------------------------
# pip_environment_is_externally_managed / pip_supports_break_system_packages
# ---------------------------------------------------------------------------

# The probe asks python3 for its own stdlib path rather than globbing
# /usr/lib/python3*, so a stub interpreter pointing anywhere is enough to
# drive both branches without touching the real system.
stub_python3_with_stdlib() {
    local stdlib="$1"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/python3" <<STUB
#!/bin/sh
printf '%s\\n' "$stdlib"
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/python3"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "pip probes: a marker in the interpreter's stdlib is detected" {
    fake_stdlib="$BATS_TEST_TMPDIR/stdlib"
    mkdir -p "$fake_stdlib"
    touch "$fake_stdlib/EXTERNALLY-MANAGED"
    stub_python3_with_stdlib "$fake_stdlib"

    run pip_environment_is_externally_managed
    [ "$status" -eq 0 ]
}

@test "pip probes: an interpreter without the marker is not flagged" {
    fake_stdlib="$BATS_TEST_TMPDIR/stdlib"
    mkdir -p "$fake_stdlib"
    stub_python3_with_stdlib "$fake_stdlib"

    run pip_environment_is_externally_managed
    [ "$status" -ne 0 ]
}

@test "pip probes: an unusable python3 is not mistaken for an unmanaged host" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/python3"
    chmod +x "$BATS_TEST_TMPDIR/bin/python3"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    run pip_environment_is_externally_managed
    [ "$status" -ne 0 ]
}

@test "pip probes: a pip that cannot run is reported as not supporting the flag" {
    run pip_supports_break_system_packages "/nonexistent/pip3"
    [ "$status" -ne 0 ]
}
