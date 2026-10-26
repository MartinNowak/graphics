#!/usr/bin/env bash
# The project's test suites, shared by coverage.sh and pgo.sh.
# Source this file, then call the functions below.

# Runs `dub test` for every package that has unittest blocks: the main
# package and the svg subpackage. Extra arguments (e.g. --coverage, or
# --build=release --force) are passed through to each dub invocation.
# dub copies the resulting test binaries next to each package directory
# (graphics-test-library, svg/graphics-svg-test-library) and leaves the
# coverage/profile data in its per-configuration cache directories.
run_dub_tests() {
    dub test --compiler=gdc "$@"
    dub test :svg --compiler=gdc "$@"
}

# Runs the property-based tests in tests/qcheck. They are deliberately
# *not* part of run_dub_tests: neither coverage nor PGO instrumentation
# helps them. On GDC, qcheck exercises graphics through templates and
# header-inlined calls, so its gcov/profile counters land in the qcheck
# test module's own objects, not in the library's. The qcheck suite is a
# validation gate (differential matrix tests, algebraic properties,
# library debug asserts), not a coverage or profile source. See the
# coverage.sh header for the same note.
run_qcheck_tests() {
    local here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    (cd "$here/tests/qcheck" && dub test --compiler=gdc)
}
