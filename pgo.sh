#!/usr/bin/env bash
# Build the unit test binaries with gdc profile-guided optimization
# (-fprofile-generate / -fprofile-use) and run the same test suite as
# coverage.sh on the resulting PGO binaries: `dub test` for the main
# package and the svg sub-package (via test-suite.sh), plus the qcheck
# property tests as a validation gate at the end. qcheck itself is never
# instrumented; its profile counters would land in the qcheck module's
# own objects, not in the library's (see test-suite.sh).
#
# The awkward part: gcc/gdc keys each program's profile files to a mirror
# of the *absolute paths* of that build's object/output files, and dub's
# build directory name embeds a hash over all build flags. So a naive
# DFLAGS="-fprofile-generate" run leaves its .gcda files under the
# instrumented build's cache directory, while a DFLAGS="-fprofile-use"
# run looks inside its own, differently named, cache directory and finds
# nothing. GCC's own fix for build-directory churn, -fprofile-prefix-path,
# cannot help here because dub changes the directory between the two runs.
#
# This script works around it:
#  1. Both passes pass an explicit profile directory
#     (-fprofile-generate=DIR / -fprofile-use=DIR), so profile data
#     accumulates in one fixed place (DIR mirrors the absolute dub cache
#     paths, no matter what they are).
#  2. In between, the profile files are renamed from the train build's
#     dub cache directory name to the use build's. The expected names are
#     read from the use build's own -Wmissing-profile diagnostics (the
#     "probe" pass), so nothing about dub's hashing scheme is
#     reimplemented here.
#
# Profile quality follows the training workload: the instrumented pass
# runs both `dub test` binaries and the svg renderer app (built with the
# same flags via `dub build :svg`, then run over copies of the SVG files
# bundled in svg/), so every binary pass 3 produces has a matching
# profile. The renderer is part of passes 2 and 3 as well: the probe
# needs its -Wmissing-profile paths, and the final pass emits the
# optimized app.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
source "$root/test-suite.sh"
profdir="$root/pgo-profile"
probe_log=$(mktemp --tmpdir graphics-pgo-probe.XXXXXX.log)
final_log=$(mktemp --tmpdir graphics-pgo-final.XXXXXX.log)
train_scratch=$(mktemp --directory)
keep_logs() {
    local rc=$?
    rm --recursive --force "$train_scratch"
    if (( rc == 0 )); then
        rm --force "$probe_log" "$final_log"
    else
        echo "==> logs kept for inspection: $probe_log $final_log" >&2
    fi
}
trap keep_logs EXIT

# -Wno-error=missing-profile keeps the probe pass from aborting before
# all "profile ... not found" diagnostics are out. It must be part of
# BOTH profile-use passes: dub hashes every build flag into the cache
# directory name, so any DFLAGS difference between probe and final pass
# changes the very paths the probe told us to rename into. Missing
# profiles in the final pass are caught by the grep gate below instead.
# -Wno-error on top: dub drives gdc with -Wall -Werror by default, and
# once a profile is genuinely found GCC's IPA-IPFE emits option-less
# "Missing counts for called function ..." warnings for profile pieces
# that don't line up — with -Werror those are hard errors. dub appends
# DFLAGS after its own switches, so this overrides them; the grep gate
# keeps the run honest anyway.
commonflags='-flto=auto -march=native'
trainflags="$commonflags -fprofile-generate=$profdir -fprofile-update=prefer-atomic"
useflags="$commonflags -fprofile-use=$profdir -Wno-error=missing-profile -Wno-error"

# Identical dub invocation for all three passes; only DFLAGS differs.
# (--force everywhere: dub's up-to-date check only tracks sources and
# flags, and the .gcda files this pipeline feeds through pgo-profile/ are
# invisible to it. Without --force, dub reuses cached objects and skips
# the compiles whose side effects the passes depend on: pass 1's fresh
# counters and pass 2's -Wmissing-profile diagnostics would be missing,
# and pass 3 would keep the probe's objects instead of applying the
# profile.) Each pass runs in a subshell because a VAR=value prefix on a
# shell *function* call persists in bash, unlike on an external command.
run_pass() {
    local flags=$1; shift
    ( DFLAGS="$flags" run_dub_tests --build=release --force "$@" )
}

# The svg renderer application, built the same way in every pass (the
# app gets its own dub cache directory and therefore its own profile
# file; dub copies the finished binary to svg/graphics_svg).
build_app() {
    local flags=$1; shift
    ( DFLAGS="$flags" dub build :svg --build=release --force "$@")
}

echo '==> pass 1/3: instrumented build + training run'
rm --recursive --force "$profdir"
mkdir --parents "$profdir"
run_pass "$trainflags" "$@"
build_app "$trainflags" "$@"
./svg/graphics_svg svg/*.svg
# The app writes PNGs next to each input file, so train on throwaway
# copies; the reference PNGs committed in svg/ stay untouched. Run the
# *freshly built* binary (svg/graphics_svg is what dub build :svg
# produces — a stale svg/svg from an old build would produce no profile
# data at all for this build's objects).
cp svg/*.svg "$train_scratch"/
"$root/svg/graphics_svg" "$train_scratch"/*.svg
if ! find "$profdir" -name '*.gcda' | grep --quiet .; then
    echo "no .gcda files produced under $profdir" >&2
    exit 1
fi

echo '==> pass 2/3: probe for the PGO build'"'"'s profile paths'
run_pass "$useflags" "$@" > "$probe_log" 2>&1 || true
build_app "$useflags" "$@" >> "$probe_log" 2>&1 || true

# Diagnostics look like:
#   warning: ‘<path>.gcda’ profile count data file not found [-Wmissing-profile]
# GCC quotes with U+2018/U+2019, so the path is grabbed as the token after
# "warning: " rather than via ASCII quotes. The token is ‘ +
# <profdir>//<absolute gcda path> + ’: re-add a leading '/' after the
# quote's first byte, collapse '//' and the on-disk path is what remains.
# For each of those, the matching train-run file lives at the same path
# under $profdir except for the dub cache directory component
# (the .../build/<name>/ part right above the file): find one there and
# copy it into place. Main-package counters sit under
# ~/.dub/cache/graphics/<version>/build/, the svg sub-package's under
# ~/.dub/cache/graphics/<version>/+svg/build/; the loop handles both the
# same way because it only strips the <name> component.
#
# Copy, not move: `dub test` and `dub build` cache their *dependency*
# packages under different build-directory names even for identical
# flags, so one profile basename has several expected destinations per
# pass (e.g. libminiz.gcda under the test build's and the app build's
# copy of miniz); every one of them needs its own copy.
grep 'profile count data file not found' "$probe_log" |
    sed -n 's|.*warning: \([^[:space:]]*\.gcda\).*|\1|p' |
    sort -u |
while read -r token; do
    expected="/${token#*/}"
    expected=${expected//\/\//\/}
    [[ $expected == "$profdir"/* ]] || continue
    file=${expected##*/}
    parent=${expected%/*}                       # .../build/<use build dir>
    parent=${parent%/*}                         # .../build
    src=$(find "$parent" -mindepth 2 -maxdepth 2 -name "$file" 2>/dev/null | head --lines=1)
    if [[ -z $src ]]; then
        echo "no recorded profile data for $file (skipping)" >&2
        continue
    fi
    mkdir --parents "${expected%/*}"
    cp "$src" "$expected"
    echo "  profiled: $file"
done

echo '==> pass 3/3: PGO build (unit tests + optimized svg renderer)'
# Must use exactly the probe's DFLAGS (see note above); still finding a
# "profile ... not found" diagnostic means the profile data was not used.
# Expect plenty of per-function "-Wmissing-profile" notes in the build
# output ("profile for function '...' not found in profile data")
# whenever an instantiation was compiled here but never executed while
# training; those functions just keep the static heuristics. Only the
# file-level diagnostic ("'<path>.gcda' profile count data file not
# found") means profile data went unused, and that is what the gate
# below fails on.
run_pass "$useflags" "$@" 2>&1 | tee "$final_log"
build_app "$useflags" "$@" 2>&1 | tee -a "$final_log"
if grep --quiet 'profile count data file not found' "$final_log"; then
    echo "some profiles were not found during the PGO build" >&2
    exit 1
fi

# Validation gate, same as coverage.sh: the property tests in
# tests/qcheck recompile graphics from source in a plain debug build
# (asserts enabled) and check algebraic/differential properties.
echo '==> qcheck property tests'
run_qcheck_tests

echo "==> done; PGO binaries: $root/graphics-test-library, $root/svg/graphics-svg-test-library, renderer at $root/svg/graphics_svg"
