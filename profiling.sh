#!/usr/bin/env bash
# Profile the SVG renderer: one `perf record` over a single renderer
# execution that renders the W3C suite (without ImageMagick compares).
#
# Extra arguments filter the suite the way tests/w3c/run.sh does (test
# name prefixes, no .svg suffix). PNGs land in prof/work/, recreated on
# every run; prof/ holds all artifacts and is git-ignored.
#
#   perf record (cycles, dwarf call graphs) -> prof/perf.data
#   flamegraph                              -> prof/folded.txt, flame.svg
#   leaf samples per function               -> prof/top-self.txt
#   self share per module (from perf report) -> prof/top-self.txt, rollup.txt
#
# Needs perf_event_paranoid <= 1 (or root) for the dwarf stack dumps.
#
# Subject: the PGO/LTO gate binary itself (pgo.sh, svg/graphics_svg). LTO
# inlining shows up merged into callers - that is the code users run, and a
# leaf that survives it (a shift-and-mask accessor, say) is really there.
# .eh_frame CFI carries the dwarf call graphs and .symtab the symbol
# attribution; without -g there are no line or inlined frames by design.
#
# GDC's old-style D mangling (_D8graphics3svg6filter...) is what binutils'
# c++filt decodes, so function names come out fully demangled. A few old
# template forms (__T with S_ back-references) and thunks are refused;
# dfold.awk's segfold() folds those from the <len><name> segment runs.
#
# env: CPUMASK  taskset cpu list for the workload; default: auto-detect the
#              fast (highest max-khz) cores on hybrid CPUs, else unpinned.
#              CPUMASK='' disables pinning.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
profdir="$root/prof"
bin="$root/svg/graphics_svg"
cd "$root"

# ---- pin the workload to performance cores (hybrid CPUs) ---------------------
# Cycles burned on E-cores skew every percentage and their PMU events are
# commonly denied. Default detection: cpus sharing the highest
# cpuinfo_max_freq are the P-cores. Non-hybrid machines stay unpinned.
if [[ -z ${CPUMASK+set} ]]; then
    CPUMASK=$(awk '
        { f[NR] = $1; if ($1 > max) max = $1 }
        END {
            hyb = 0
            for (i = 1; i <= NR; i++) if (f[i] < max) { hyb = 1; break }
            if (!hyb) exit
            mask = ""
            for (i = 1; i <= NR; i++) if (f[i] == max) mask = mask (mask ? "," : "") (i - 1)
            print mask
        }' <(for ((c = 0; c < $(nproc); c++)); do
                 cat "/sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq" 2>/dev/null || break
             done)) || true
fi
CPUMASK=${CPUMASK:-}
runon() {
    if [[ -n $CPUMASK ]]; then taskset --cpu-list "$CPUMASK" "$@"
    else "$@"; fi
}

# Only work/ is wiped (prof/ may hold scratch you want to keep, e.g. A/B
# binaries), and every artifact is overwritten anyway.
rm --recursive --force "$profdir/work"
mkdir --parents "$profdir/work"

# ---- workload ----------------------------------------------------------------
mapfile -t files < <(
    find "$root/tests/w3c/suite/svg" -name '*.svg' | sort |
    if (($#)); then
        pat=$(printf '%s|' "$@" | sed 's/|$//')
        grep -E "/($pat)[^/]*\.svg$"
    else
        cat
    fi
)
((${#files[@]})) || { echo 'no suite files selected' >&2; exit 1; }
cp "${files[@]}" "$profdir/work/"
work=("$profdir"/work/*.svg)
echo "==> workload: ${#work[@]} suite files in one execution${CPUMASK:+, pinned to cpus $CPUMASK}"

# ---- dfold: fallback fold of symbols c++filt refuses -------------------------
cat >"$profdir/dfold.awk" <<'AWK'
# segfold(sym) folds one mangled D symbol into module.path.function.
# Segments are <len><name> runs after _D, ending at the F that starts the
# argument mangling. Substitution back-references (Qx) and template headers
# (__T) carry no new names, so they are skipped; anything else unparseable
# ends the walk, and a symbol whose first token is not a segment (thunks
# _DTi..) is passed through unchanged.
function segfold(sym,    s, n, i, m, len, name, out) {
    if (sym !~ /^_D[A-Za-z0-9]/) return sym
    s = substr(sym, 3); n = 0
    while (1) {
        if (s ~ /^__T/) { s = substr(s, 4); continue }
        if (s ~ /^Q[a-z]/) { s = substr(s, 3); continue }
        if (!match(s, /^[0-9]+/)) break
        len = substr(s, RSTART, RLENGTH) + 0
        s = substr(s, RLENGTH + 1)
        if (len == 0 || length(s) < len) break
        name = substr(s, 1, len); s = substr(s, len + 1)
        segs[++n] = name
        if (s ~ /^F/) break
    }
    if (n == 0) return sym
    if (n == 1) return segs[1]
    m = n - 1 < 3 ? n - 1 : 3
    out = segs[1]
    for (i = 2; i <= m; i++) out = out "." segs[i]
    return out "." segs[n]
}
AWK

# ---- perf record ---------------------------------------------------------------
echo '==> perf record (cycles, dwarf call graphs)'
[[ -x $bin ]] || { echo "gate binary missing - run: bash pgo.sh" >&2; exit 1; }
runon perf record -F 10000 --call-graph dwarf,32768 -o "$profdir/perf.data" \
    -- "$bin" "${work[@]}" >"$profdir/perf-record.log" 2>&1
tail -1 "$profdir/perf-record.log"

# Self profile straight from perf report: its symbol resolution is exact for
# app and kernel leaves alike. (stackcollapse-perf.pl on the other hand
# prefixes every stack with the comm column and collapses samples without
# user frames to comm-only lines, so it is used for the flamegraph only.)
# Pipeline: 'pct symbol' -> c++filt -> fold the few it refuses -> sum
# identical names (@plt aliases, folded fallbacks).
perf report -i "$profdir/perf.data" --stdio --sort symbol -g none \
        --percent-limit 0.005 2>/dev/null |
    awk '{for (i = 1; i < NF; i++)
             if (($i == "[.]" || $i == "[k]") && $(i + 1) != "") { print $1, $(i + 1); break }}' |
    tr -d '%' | c++filt |
    awk -f "$profdir/dfold.awk" -e '{
        pct = $1; sub(/^[0-9.]+[[:space:]]+/, "")
        name = ($0 ~ /^_D/) ? segfold($0) : $0
        total[name] += pct
    }
    END {for (s in total) printf "%.2f %s\n", total[s], s}' |
    sort -k1,1nr >"$profdir/top-self.full"
head -50 "$profdir/top-self.full" >"$profdir/top-self.txt"

# Per-module rollup: leading dotted path of the (demangled) symbol name,
# minus its last segment (Beziota!(float, 2uL).BezIota.findT() groups under
# graphics.bezier.cartesian; C and kernel leaves stay their own group).
awk '{pct = $1; sub(/^[0-9.]+[[:space:]]+/, ""); name = $0
      key = name
      if (match(key, /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+/))
          key = substr(key, RSTART, RLENGTH)
      sub(/\.[^.]*$/, "", key)
      if (key == "") key = name
      mod[key] += pct}
     END {for (g in mod) printf "%6.2f %s\n", mod[g], g}' \
    "$profdir/top-self.full" | sort -k1,1nr >"$profdir/rollup.full"
# head from a file: sorting into the head directly races a SIGPIPE through
# pipefail once the sort output outgrows the pipe buffer.
head -40 "$profdir/rollup.full" >"$profdir/rollup.txt"

# Flamegraph from the stacks: strip the comm prefix stackcollapse-perf.pl
# adds, drop comm-only (no user frames) lines, then c++filt demangles in
# place. Dwarf unwind holes in the GDC binary leave [unknown] frames,
# cosmetic here.
perf script -i "$profdir/perf.data" | stackcollapse-perf.pl |
    awk '{cnt = $NF; stack = $0; sub(/ [0-9]+$/, "", stack)
         if (stack !~ ";") next          # comm-only: no user frames
         sub(/^[^;]*;/, "", stack)       # drop the comm element
         print stack, cnt}' |
    c++filt >"$profdir/folded.txt"
flamegraph.pl --title 'graphics:svg - W3C suite render' \
    "$profdir/folded.txt" >"$profdir/flame.svg"

echo "==> artifacts in $profdir:"
ls "$profdir" | sed 's/^/    /'
echo "done. Read top-self.txt and rollup.txt first, flame.svg for context."
