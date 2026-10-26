#!/usr/bin/env bash
# W3C SVG 1.1 Second Edition compliance harness.
#
# Renders every test in suite/svg/ (fetched by fetch.sh) with the
# graphics:svg CLI at zoom 1 and compares each rendering against the
# reference image suite/png/NAME.png (480x360 for all SVG 1.1 SE tests).
#
# usage:
#   run.sh                  render all tests, validate against status.txt
#   run.sh --update         rebase status.txt (baseline mode)
#   run.sh [NAME ...]       restrict to tests whose name matches the given
#                           glob patterns (no .svg suffix, prefix match);
#                           combinable with --update to refresh single
#                           baseline lines
#
# Per test the verdict is:
#   ERROR  the renderer crashed / produced no image / compare failed
#   PASS   AE (fuzz 10%) within the tier tolerance (see TOL_* below)
#   DIFF   rendered, but off by more than the tolerance
# out/NAME.diff.png is the side-by-side + highlighted-diff triage artifact
# (the W3C "overlay" workflow, used to judge the text/font categories).
#
# The committed status.txt is the baseline. Validation fails on: a verdict
# worse than the baseline, a tier pass-count regression, or tests appearing
# in / disappearing from the suite without a baseline rebase. Plain
# `run.sh` is thus a CI gate that only trips on regressions.
set -u
cd "$(dirname "$0")/../.."

SUITE=tests/w3c/suite
OUT=tests/w3c/out
TIERS=tests/w3c/tiers
STATUS=tests/w3c/status.txt
BIN=svg/graphics_svg
FUZZ=10%
TIMEOUT=10

# Initial per-tier tolerances in differing pixels (AE at fuzz 10 % on the
# 480x360 = 172800 px canvas):
#   geometry  0.5 % of the canvas
#   servers   1 %
#   text      25 % - effectively review-only: font hinting and AA never
#             match across rasterizers, so verdicts here are advisory and
#             the diff images are what gets reviewed
#   skip      0 (expected to stay DIFF forever)
#   other     0.5 % (uncategorized: filters-*, painting-marker-*, ...)
# Ratchet these down as features land, then re-record with run.sh --update.
TOL_geometry=1200
TOL_servers=1728
TOL_text=43200
TOL_skip=0
TOL_other=1200

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

# Tier of a test name (with .svg suffix); "other" if no tier manifest lists it.
tier_of() {
    local name=$1 t
    for t in geometry servers text skip; do
        grep -qxF "$name" "$TIERS/$t.txt" 2>/dev/null && { echo $t; return; }
    done
    echo other
}

# The workhorse, one test file: prints "NAME.svg TIER VERDICT AE TOLERANCE".
run_one() {
    local f=$1 stem=$2 tier tol verdict ae ref
    cp -f "$f" "$OUT/$stem.svg"
    if ! timeout "$TIMEOUT" "$BIN" -z 1 "$OUT/$stem.svg" >"$OUT/$stem.err" 2>&1 || [ ! -s "$OUT/$stem.png" ]; then
        printf '%s.svg other ERROR - -\n' "$stem"
        return
    fi
    ae=$(magick compare -metric AE -fuzz "$FUZZ" "$SUITE/png/$stem.png" "$OUT/$stem.png" "$OUT/$stem.diff.png" 2>&1)
    case $? in
        0|1) ae=${ae%% *} ;;                       # "AE (fraction)" printed on stderr
        *) printf '%s.svg other ERROR - -\n' "$stem"; return ;;
    esac
    case $ae in *[!0-9.e+]*|"") printf '%s.svg other ERROR - -\n' "$stem"; return ;; esac
    ae=$(printf '%.0f' "$ae")                     # IM can print a weighted/decimal AE
    tier=$(tier_of "$stem.svg")
    ref=TOL_$tier; tol=${!ref}
    if [ "$ae" -le "$tol" ]; then verdict=PASS; else verdict=DIFF; fi
    printf '%s.svg %s %s %s %s\n' "$stem" "$tier" "$verdict" "$ae" "$tol"
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

export BIN SUITE OUT TIERS FUZZ TIMEOUT
export TOL_geometry TOL_servers TOL_text TOL_skip TOL_other
export -f tier_of run_one
printf '%s\n' "${tests[@]}" | LC_ALL=C sort |
    xargs -P "$(nproc)" -n 2 bash -c 'run_one "$2" "$1"' _ >"$OUT/results.txt"

# Merge fresh results into the baseline (lines of untouched tests are kept).
declare -A baseline=()
[ -f "$STATUS" ] && while read -r name verdict rest; do baseline[$name]="$verdict $rest"; done <"$STATUS"
declare -A cur=()
while read -r name tier verdict ae tol; do cur[$name]="$verdict $ae $tol"; done <"$OUT/results.txt"

print_table() {
    local name tier verdict t
    local -A ntot npass ndiff nerr
    for name in "${!cur[@]}"; do
        tier=$(tier_of "$name"); verdict=${cur[$name]%% *}
        ntot[$tier]=$(( ${ntot[$tier]:-0} + 1 ))
        case $verdict in
            PASS)  npass[$tier]=$(( ${npass[$tier]:-0} + 1 )) ;;
            DIFF)  ndiff[$tier]=$(( ${ndiff[$tier]:-0} + 1 )) ;;
            ERROR) nerr[$tier]=$(( ${nerr[$tier]:-0} + 1 )) ;;
        esac
    done
    printf '%-9s %6s %6s %6s %6s\n' tier tests PASS DIFF ERROR
    for t in geometry servers text skip other; do
        [ ${ntot[$t]:-0} -gt 0 ] || continue
        printf '%-9s %6s %6s %6s %6s\n' "$t" "${ntot[$t]}" "${npass[$t]:-0}" "${ndiff[$t]:-0}" "${nerr[$t]:-0}"
    done
}

if [ -n "$update" ]; then
    for name in "${!cur[@]}"; do baseline[$name]=${cur[$name]}; done
    { for name in "${!baseline[@]}"; do printf '%s %s\n' "$name" "${baseline[$name]}"; done; } |
        LC_ALL=C sort >"$STATUS"
    echo "rebased: $(wc -l <"$STATUS") lines in $STATUS"
    print_table
    exit 0
fi

# CI gate: fail on verdict regressions against the baseline and on tier
# pass-count drops. Improvements (ERROR -> DIFF -> PASS) never fail.
declare -A rank=([PASS]=0 [DIFF]=1 [ERROR]=2)
declare -A npass=() ppass=()
fails=0
for name in "${!cur[@]}"; do
    tier=$(tier_of "$name"); verdict=${cur[$name]%% *}
    [ $verdict = PASS ] && npass[$tier]=$(( ${npass[$tier]:-0} + 1 ))
    if [ -z "${baseline[$name]:-}" ]; then
        echo "regression: $name is not in $STATUS (stale baseline - run --update)"
        fails=$((fails + 1))
        continue
    fi
    base=${baseline[$name]%% *}
    [ $base = PASS ] && ppass[$tier]=$(( ${ppass[$tier]:-0} + 1 ))
    if [ ${rank[$verdict]} -gt ${rank[$base]} ]; then
        echo "regression: $name $base -> $verdict"
        fails=$((fails + 1))
    fi
done
if [ ${#patterns[@]} -eq 0 ]; then  # only a full run sees every baseline line
    for name in "${!baseline[@]}"; do
        [ -n "${cur[$name]:-}" ] || { echo "regression: $name vanished from suite/ (stale baseline - run --update)"; fails=$((fails + 1)); }
    done
fi
for t in geometry servers text skip other; do
    if [ ${npass[$t]:-0} -lt ${ppass[$t]:-0} ]; then
        echo "regression: tier $t lost $(( ${ppass[$t]} - ${npass[$t]} )) passing tests"
        fails=$((fails + 1))
    fi
done

print_table
if [ "$fails" -gt 0 ]; then echo "FAIL: $fails regression(s)"; exit 1; fi
echo "OK: ${#cur[@]} test(s), no regressions against $STATUS"
