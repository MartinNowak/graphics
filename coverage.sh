#!/usr/bin/env bash
# Run the unit tests with coverage instrumentation and the property-based
# tests in tests/qcheck, and print a per-file coverage summary.
#
# gcno/gcda files land in dub's build cache directories for each coverage
# build. gcov runs from a scratch directory in JSON intermediate mode
# (gcov --json-format, requires gcov >= 14 for format version 2), and the
# report merges template instantiations: a source line counts as covered
# when *any* instantiation executed it. (Plain gcov text output prints one
# block per instantiation and collides on identical base file names, which
# badly understates coverage for e.g. math/poly.d.)
#
# Note: only the main test binary's coverage is reported. On GDC the
# property tests in tests/qcheck exercise graphics through templates and
# header-inlined calls, so their gcov counters land in the qcheck test
# module's own objects and the linked libgraphics.gcda stays at 0%. The
# qcheck suite is therefore a validation gate (differential matrix tests,
# algebraic properties, library debug asserts), not a coverage source.
#
# The graphics:svg sub-package is covered by its own `dub test` run. dub
# caches sub-package builds under the parent's cache directory
# (~/.dub/cache/graphics/<version>/+svg/), so the single find below picks
# up both test binaries' counters.
#
# The test suite itself (main package + :svg sub-package + qcheck gate) is
# defined once in test-suite.sh and shared with pgo.sh.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
source "$root/test-suite.sh"

# Drop stale coverage counters so gcov only sees this run's data; afterwards
# every .gcda under dub's cache belongs to this run. (The cache path embeds
# the package version, so glob over it instead of hardcoding ~master.)
find "$HOME/.dub/cache/graphics" -name '*.gcda' -delete 2>/dev/null || true

cd "$root"
run_dub_tests --coverage

scratch=$(mktemp --directory)
trap 'rm --recursive --force "$scratch"' EXIT

# Run gcov over every gcda the test run produced. gcov writes one
# <data-file>.gcov.json.gz per gcda into the current directory.
cd "$scratch"
find "$HOME/.dub/cache/graphics" -name '*.gcda' -exec gcov --json-format {} + >/dev/null 2>&1 || true
jsons=(*.gcov.json.gz)
[[ -e ${jsons[0]} ]] || { echo "no coverage data found in dub's cache" >&2; exit 1; }

# gcov's format-version-2 JSON is one long line per document:
#
#   {"format_version": "2", ..., "files": [
#     {"file": "src/graphics/poly.d", "functions": [...], "lines": [
#        {"line_number": 12, "function_name": "_D...", "count": 0,
#         "unexecuted_block": true, "block_ids": [], ...}, ...
#
# The awk below keeps just the current file and each line entry's number
# and "count". A line whose count is > 0 in *any* instantiation counts as
# covered, so first impressions per (file, line) give the union totals.
#
# Regex notes:
#  - RS splits records right after the two keys that matter: file headers
#    ("file") and per-line entries ("line_number"). The document's own
#    "data_file"/"files" keys and function keys like "start_line" cannot
#    match them. (Regex RS is a gawk feature; the whole script assumes the
#    GNU toolchain that the gdc/dub setup already implies.)
#  - ^[ ]*[0-9]+,[^{]*...: an entry's body before "count" holds only the
#    (optional) mangled function name, so [^{] cannot escape the entry.
#  - "count": N, "unexecuted_block": we never pass --branch-*, so
#    "branches"/"conditions" stay empty and this adjacency is guaranteed.
gzip --decompress --stdout "${jsons[@]}" |
awk -v RS='\\{"(file|line_number)": ' '
# Each record starts immediately after one of the two keys:
#   after "file":          -> `"src/graphics/paint.d", "functions": [...`
#   after "line_number":   -> ` 12, "function_name": "_D...", "count": 3, ...`
# A leading quote therefore means "here is a new file", a leading digit
# means "one instantiation of one source line".
/^"/ {
    match($0, /^"[^"]*"/)
    curfile = substr($0, 2, RLENGTH - 2)
    next
}
/^[ ]*[0-9]/ {
    entry = $0
    sub(/^[ ]+/, "", entry)
    if (!match(entry, /^[0-9]+,[^{]*"count": -?[0-9]+, "unexecuted_block"/)) next
    lineno = substr(entry, 1, index(entry, ",") - 1)
    match(entry, /"count": -?[0-9]+/)
    count = substr(entry, RSTART + 8, RLENGTH - 8) + 0

    f = curfile
    sub(/-mixin-[0-9]+$/, "", f)          # fold foo.d-mixin-42 into foo.d
    if (f !~ /^(src|svg)\/graphics\//) next  # skip phobos, druntime, guip, ...
    if (f ~ /\/testing\.d$/) next         # unittest-only helper module
    if (!((f, lineno) in seen)) { seen[f, lineno] = 1; tot[f]++ }
    if (count > 0 && !covseen[f, lineno]++) cov[f]++
}
END {
    for (f in tot)
        printf "%.10f %d %d %s\n", 100.0 * cov[f] / tot[f], cov[f], tot[f], f
}' |
sort --key=1,1nr --key=4,4r |
awk '{ printf "%6.1f%%  %s\n", $1, $4; c += $2; t += $3; n++ }
     END { printf "\n%d/%d lines over %d src files: %.1f%%\n", c, t, n, (t ? 100.0 * c / t : 0) }'

run_qcheck_tests
