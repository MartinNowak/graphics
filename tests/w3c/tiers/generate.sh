#!/usr/bin/env bash
# Regenerate the tier manifests (geometry.txt, servers.txt, text.txt,
# skip.txt) from the fetched suite's file names.
#
# Membership is by category prefix (the W3C file naming convention
# <chapter>-<group>-<nn>-<type>.svg); the rules below already encode the
# one-time curation:
#   - *-dom-* (DOM/script API tests: struct-dom, text-dom, coords-dom,
#     paths-dom, ...) go to skip, even though their chapter prefix would
#     otherwise place them in a rendered tier;
#   - color-prop-* (CSS color keywords, currentColor) join geometry (step 3
#     work), color-prof-* (ICC profiles) go to skip;
#   - everything else keeps its chapter prefix.
#
# The remaining tests (filters-*, painting-marker-*, painting-render-*,
# types-basic-*, metadata-example-*, extend-namespace-*, imp-path-*) belong
# to no tier ("other" in run.sh): future work packages, see README.md.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d suite/svg ] || { echo "run tests/w3c/fetch.sh first" >&2; exit 1; }

rm -f tiers/geometry.txt tiers/servers.txt tiers/text.txt tiers/skip.txt
ls suite/svg | LC_ALL=C sort | awk '
{
    n = $0
    if      (n ~ /^(animate|interact|script|linking|types-dom|svgdom)-/ || n ~ /-dom-/ || n ~ /^color-prof-/) t = "skip"
    else if (n ~ /^(shapes|paths|coords|render|conform|styling-pres|color-prop)-/ || n ~ /^painting-(fill|stroke|control)-/) t = "geometry"
    else if (n ~ /^(struct|pservers|masking|styling)-/) t = "servers"
    else if (n ~ /^(text|fonts)-/) t = "text"
    else    t = "other"
    if (t != "other") print n > ("tiers/" t ".txt")
    count[t]++
}
END {
    for (t in count) printf "%-8s %3d\n", t, count[t] > "/dev/stderr"
}'

# Tier names carry the .svg suffix, matching status.txt.
wc -l tiers/geometry.txt tiers/servers.txt tiers/text.txt tiers/skip.txt
