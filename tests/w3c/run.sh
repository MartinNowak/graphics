#!/usr/bin/env bash
# W3C SVG 1.1 Second Edition compliance harness.
#
# Renders every test in suite/svg/ (fetched by fetch.sh) with the
# graphics:svg CLI at zoom 1 and compares each rendering against the
# reference image suite/png/NAME.png (480x360 for all SVG 1.1 SE tests).
#
# Nothing is excluded and nothing is curated: all 526 tests are rendered,
# including animate-*, interact-* and *-dom-* - the renderer ignores SMIL
# and scripting, so every test has a deterministic static-frame rendering,
# and its AE number is simply tracked against the committed baseline in
# status.txt. (The reference PNGs of animation tests show timeline states,
# so their absolute verdict hardly matters; their AE trend over time does.)
#
# usage:
#   run.sh                render all tests, gate against status.txt
#   run.sh --update       rebase status.txt (after engine changes land)
#   run.sh [NAME ...]     restrict to tests whose name matches the given
#                         glob patterns (no .svg suffix, prefix match);
#                         combinable with --update to refresh single lines
#
# Per test the verdict is:
#   ERROR  the renderer crashed / timed out / produced no image, or the
#          compare failed; AE is recorded as "-"
#   OK     the test rendered and compared; AE (fuzz 10 %, channel-weighted,
#          rounded) is the tracked number
# out/NAME.diff.png is the side-by-side + highlighted-diff triage artifact;
# out/NAME.err holds the engine's stderr.
#
# The committed status.txt (`NAME.svg OK|ERROR <AE>`) is the baseline.
# Plain run.sh is a CI gate that fails only on regressions:
#   - a test that was OK in the baseline now errors,
#   - an OK test whose AE grew beyond the baseline value,
#   - tests appearing in / vanishing from the suite without a rebase.
# Improvements (ERROR -> OK, shrinking AE) never fail the gate; rebase to
# lock them in and to ratchet the numbers down.
set -u
export LC_ALL=C
cd "$(dirname "$0")/../.."

SUITE=tests/w3c/suite
OUT=tests/w3c/out
STATUS=tests/w3c/status.txt
BIN=svg/graphics_svg
FUZZ=10%
TIMEOUT=10

update=
declare -a patterns=()
for arg in "$@"; do
    case "$arg" in
        --update) update=1 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) patterns+=("$arg") ;;
    esac
done

[ -d "$SUITE/svg" ] || { echo "suite missing - run tests/w3c/fetch.sh" >&2; exit 1; }
[ -x "$BIN" ] || { echo "binary missing - run: dub build :svg" >&2; exit 1; }
mkdir -p "$OUT"

# The workhorse, one test file: prints "NAME.svg OK <AE>" or "NAME.svg ERROR -".
run_one() {
    local f=$1 stem=$2 ae
    cp -f "$f" "$OUT/$stem.svg"
    if ! timeout "$TIMEOUT" "$BIN" -z 1 "$OUT/$stem.svg" >"$OUT/$stem.err" 2>&1 || [ ! -s "$OUT/$stem.png" ]; then
        printf '%s.svg ERROR -\n' "$stem"
        return
    fi
    ae=$(magick compare -metric AE -fuzz "$FUZZ" "$SUITE/png/$stem.png" "$OUT/$stem.png" "$OUT/$stem.diff.png" 2>&1)
    case $? in
        0|1) ae=${ae%% *} ;;                       # "AE (fraction)" printed on stderr
        *) printf '%s.svg ERROR -\n' "$stem"; return ;;
    esac
    case $ae in ""|*[!0-9.e+]*) printf '%s.svg ERROR -\n' "$stem"; return ;; esac
    printf '%s.svg OK %.0f\n' "$stem" "$ae"
}

# Test list: full suite, or the NAME glob subset. Each entry is "STEM PATH".
declare -a tests=()
for f in "$SUITE"/svg/*.svg; do
    stem=${f##*/}; stem=${stem%.svg}
    if [ ${#patterns[@]} -eq 0 ]; then
        tests+=("$stem $f")
    else
        for p in "${patterns[@]}"; do
            [[ $stem == $p || $stem == $p* ]] && { tests+=("$stem $f"); break; }
        done
    fi
done
[ ${#tests[@]} -gt 0 ] || { echo "no tests match: ${patterns[*]}" >&2; exit 1; }

export BIN SUITE OUT FUZZ TIMEOUT
export -f run_one
printf '%s\n' "${tests[@]}" | sort | xargs -P "$(nproc)" -n 2 bash -c 'run_one "$2" "$1"' _ >"$OUT/results.txt"

# Merge fresh results into the baseline (lines of untouched tests are kept).
declare -A baseline=()
[ -f "$STATUS" ] && while read -r name verdict ae; do baseline[$name]="$verdict $ae"; done <"$STATUS"
declare -A cur=()
while read -r name verdict ae; do cur[$name]="$verdict $ae"; done <"$OUT/results.txt"

# Per-category summary: category = first two hyphen-separated name segments
# (masking-path-01-b.svg -> masking-path); display only, no gating input.
print_table() {
    printf '%-24s %6s %6s %6s %10s\n' category tests OK ERROR "AE sum"
    awk '
    {
        stem = $1; sub(/\.svg$/, "", stem);
        split(stem, p, "-");
        cat = length(p) > 1 ? p[1] "-" p[2] : p[1];
        n[cat]++;
        if ($2 == "OK") { ok[cat]++; ae[cat] += $3 } else err[cat]++;
    }
    END { for (c in n) printf "%-24s %6d %6d %6d %10d\n", c, n[c], ok[c], err[c], ae[c] }
    ' "$OUT/results.txt" | sort
}

if [ -n "$update" ]; then
    for name in "${!cur[@]}"; do baseline[$name]=${cur[$name]}; done
    { for name in "${!baseline[@]}"; do printf '%s %s\n' "$name" "${baseline[$name]}"; done; } |
        sort >"$STATUS"
    echo "rebased: $(wc -l <"$STATUS") lines in $STATUS"
    print_table
    exit 0
fi

# CI gate against the baseline.
fails=0
for name in "${!cur[@]}"; do
    if [ -z "${baseline[$name]:-}" ]; then
        echo "regression: $name is not in $STATUS (stale baseline - run --update)"
        fails=$((fails + 1))
        continue
    fi
    read -r bv ba <<<"${baseline[$name]}"
    read -r cv ca <<<"${cur[$name]}"
    if [ $cv = ERROR ] && [ $bv = OK ]; then
        echo "regression: $name OK -> ERROR"
        fails=$((fails + 1))
    elif [ $cv = OK ] && [ $ba != - ] && [ $ca -gt $ba ]; then
        echo "regression: $name AE $ba -> $ca (+$((ca - ba)))"
        fails=$((fails + 1))
    fi
done
if [ ${#patterns[@]} -eq 0 ]; then  # only a full run sees every baseline line
    for name in "${!baseline[@]}"; do
        [ -n "${cur[$name]:-}" ] || { echo "regression: $name vanished from suite/ (stale baseline - run --update)"; fails=$((fails + 1)); }
    done
fi

print_table
if [ "$fails" -gt 0 ]; then echo "FAIL: $fails regression(s)"; exit 1; fi
echo "OK: ${#cur[@]} test(s), no regressions against $STATUS"
