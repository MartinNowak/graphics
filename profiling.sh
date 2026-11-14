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
# Attribution build: a non-LTO '-O2 -g' release build (app-perf): LTO hoists
# callees into callers and smears per-function attribution. The PGO/LTO
# binary (pgo.sh, svg/graphics_svg) is stashed and restored around the build
# so tests/w3c/run.sh keeps seeing it.
#
# D symbols are mangled (_D7graphics3svg6render...) and binutils does not
# demangle them, but the mangling carries the full module path, so dfold.awk
# (written by this script) rewrites them to graphics.svg.render.functionName.
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

# Rebuild outputs in place: only work/ is wiped (prof/ may hold scratch you
# want to keep, e.g. A/B binaries), and every artifact is overwritten anyway.
rm --recursive --force "$profdir/work"
mkdir --parents "$profdir/work"

# ---- build -------------------------------------------------------------------
echo '==> building (release -g)'
had_prev=0
if [[ -f $bin ]]; then
    cp "$bin" "$profdir/app-prev"
    had_prev=1
fi
# dub appends DFLAGS after its own switches; -g on release costs no codegen
# quality and gives symbols + line info without enabling LTO.
DFLAGS='-g' dub build :svg --build=release
cp "$bin" "$profdir/app-perf"
if (( had_prev )); then
    cp "$profdir/app-prev" "$bin"    # run.sh must see the binary it saw before
fi

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

# ---- dfold: fold mangled D symbols --------------------------------------------
cat >"$profdir/dfold.awk" <<'AWK'
# Functions: segfold(sym) folds one mangled D symbol. Segments are
# <len><name> runs after _D, ending at the F that starts the argument
# mangling. Substitution back-references (Qx) and template headers (__T)
# carry no new names, so they are skipped; anything else unparseable ends
# the walk, and a symbol whose first token is not a segment (thunks _DTi..,
# inlined notes) is passed through unchanged.
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
function foldline(s,    out, sym, f) {
    out = ""
    while (match(s, /_D[A-Za-z0-9_]+/)) {
        sym = substr(s, RSTART, RLENGTH)
        f = segfold(sym)
        out = out substr(s, 1, RSTART - 1) f
        if (f == sym) out = out substr(s, RSTART, RLENGTH)  # advance past raw token
        s = substr(s, RSTART + RLENGTH)
    }
    return out s
}
AWK

# ---- perf record ---------------------------------------------------------------
echo '==> perf record (cycles, dwarf call graphs)'
runon perf record --call-graph dwarf,32768 -o "$profdir/perf.data" \
    -- "$profdir/app-perf" "${work[@]}" >"$profdir/perf-record.log" 2>&1
tail -1 "$profdir/perf-record.log"

# Self profile straight from perf report: its symbol resolution is exact for
# app and kernel leaves alike. (stackcollapse-perf.pl on the other hand
# prefixes every stack with the comm column and collapses samples without
# user frames to comm-only lines, so it is used for the flamegraph only.)
perf report -i "$profdir/perf.data" --stdio --sort symbol -g none \
        --percent-limit 0.02 2>/dev/null |
    awk -f "$profdir/dfold.awk" -e '{
        if (match($0, /\[[^]]*\] /)) {
            pct = $1; sub(/%$/, "", pct)
            sym = substr($0, RSTART + RLENGTH); sub(/[[:space:]]+$/, "", sym)
            total[segfold(sym)] += pct + 0    # merge instantiations folded alike
        }
    }
    END {for (s in total) printf "%.2f %s\n", total[s], s}' |
    sort -k1,1nr >"$profdir/top-self.full"
head -50 "$profdir/top-self.full" >"$profdir/top-self.txt"

# per-module rollup from the self profile (module = symbol name minus its
# last dotted segment; D names folded by dfold.awk above)
awk '{n = split($2, a, "."); m = a[1]
      for (i = 2; i < n; i++) m = m "." a[i]
      mod[m] += $1}
     END {for (g in mod) printf "%6.2f %s\n", mod[g], g}' \
    "$profdir/top-self.full" | sort -k1,1nr | head -40 >"$profdir/rollup.txt"

# flamegraph from the stacks: strip the comm prefix stackcollapse-perf.pl
# adds, drop comm-only (no user frames) lines; dwarf unwind holes in the
# GDC binary leave [unknown] frames, cosmetic here.
perf script -i "$profdir/perf.data" | stackcollapse-perf.pl |
    awk -f "$profdir/dfold.awk" -e '{
        cnt = $NF; stack = $0; sub(/ [0-9]+$/, "", stack)
        sub(/^app-perf;/, "", stack)
        if (stack == "app-perf" || stack == "") next
        nf = split(stack, a, ";")
        out = segfold(a[1])
        for (i = 2; i <= nf; i++) out = out ";" segfold(a[i])
        print out, cnt
    }' >"$profdir/folded.txt"
flamegraph.pl --title 'graphics:svg - W3C suite render' \
    "$profdir/folded.txt" >"$profdir/flame.svg"

echo "==> artifacts in $profdir:"
ls "$profdir" | sed 's/^/    /'
echo "done. Read top-self.txt and rollup.txt first, flame.svg for context."
echo "Verify with: bash tests/w3c/run.sh   (the gate must stay at its committed AE)"
