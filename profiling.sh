#!/usr/bin/env bash
# Profile the SVG renderer against the W3C suite and collect hotspots.
#
# The workload is tests/w3c/suite/svg rendered *without* the ImageMagick
# compare that dominates tests/w3c/run.sh wall time: this script renders,
# nothing else. Extra arguments filter the suite the way run.sh does (test
# name prefixes, no .svg suffix). PNGs land in prof/work/, which is
# recreated on every run; prof/ holds all artifacts and is git-ignored.
#
# Passes (all against the same file list):
#   0  per-file render times -> prof/times.txt (sorted, ms; includes
#      process and fontconfig startup, a roughly constant ~50 ms offset).
#      Sizes the callgrind budget and shows which fixture classes are slow.
#   B  perf record (cycles) over PASSES suite passes in one process ->
#      prof/perf.data, prof/folded.txt, prof/flame.svg, prof/top-self.txt
#      (leaf samples per function), prof/rollup.txt (self + inclusive
#      sample share per module). The script first tries dwarf call graphs;
#      kernels with perf_event_paranoid=2 plus SELinux deny stack-dumping
#      events ("Failure to open any events"), and the pass then falls back
#      to leaf-only sampling - self profiles stay exact, the flamegraph
#      degenerates to a flat bar, and pass A carries the call tree.
#   C  perf stat -d over one pass -> prof/perf-stat.txt (IPC, cache and
#      branch misses: compute-bound vs memory-bound). On hybrid CPUs the
#      e-core PMU lines may read <not counted>; read the cpu_core ones.
#   A  callgrind over the worst files from pass 0, up to CG_BUDGET ms of
#      recorded render time (0 = the whole workload, the default) ->
#      prof/callgrind-top.txt (self cost) and prof/callgrind-inclusive.txt.
#      Instruction counts are machine- and cache-independent, so they show
#      the algorithmic work even where perf cycles are dominated by cache
#      effects; and callgrind needs no kernel event access at all, so it
#      is the call-tree source whenever pass B fell back to leaf-only.
#
# Attribution build: perf/callgrind run a non-LTO '-O2 -g' release build
# (app-perf). The PGO/LTO binary (pgo.sh, svg/graphics_svg) is stashed and
# restored here and deliberately not profiled: LTO hoists callees into
# callers, which smears the per-function attribution this script is for.
# app-release (plain release) drives the timing pass, whose numbers should
# reflect the shipped binary's speed.
#
# D symbols are mangled (_D7graphics3svg6render...); perf, callgrind and
# c++filt do not demangle them, but the mangling carries the full module
# path, so dfold.awk (written by this script) rewrites them to
# graphics.svg.render.functionName - enough for function tops and module
# rollups.
#
# env: PASSES     perf record suite passes, default 3
#      CG_BUDGET  recorded ms of rendering for callgrind, default 2000.
#                 0 = every file: heavy — valgrind has been OOM-killed by the
#                 full suite on modest machines; keep the budget unless the
#                 box has memory to spare.
#      CPUMASK    taskset cpu list for the workload; default: auto-detect the
#                 fast (highest max-khz) cores on hybrid CPUs, else unpinned
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
profdir="$root/prof"
bin="$root/svg/graphics_svg"
PASSES=${PASSES:-3}
CG_BUDGET=${CG_BUDGET:-2000}
cd "$root"

# ---- pin the workload to performance cores (hybrid CPUs) ---------------------
# The scheduler spreads the workload over both PMU classes: atom PMU events are
# commonly denied (SELinux/paranoid), perf stat lines for them read
# <not counted>, and cycles burned on E-cores skew every percentage. Default
# detection: cpus sharing the highest cpuinfo_max_freq are the P-cores; pin
# there. Non-hybrid machines (all freqs equal) and missing cpufreq stay
# unpinned. CPUMASK= overrides (empty string disables pinning).
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

rm --recursive --force "$profdir"
mkdir --parents "$profdir/work"

# ---- builds ----------------------------------------------------------------
echo '==> building (release for timing, release -g for perf/callgrind)'
had_prev=0
if [[ -f $bin ]]; then
    cp "$bin" "$profdir/app-prev"
    had_prev=1
fi
dub build :svg --build=release
cp "$bin" "$profdir/app-release"
# dub appends DFLAGS after its own switches; -g on release costs no codegen
# quality and gives symbols + line info without enabling LTO.
DFLAGS='-g' dub build :svg --build=release
cp "$bin" "$profdir/app-perf"
if (( had_prev )); then
    cp "$profdir/app-prev" "$bin"    # run.sh must see the binary it saw before
fi

# ---- workload --------------------------------------------------------------
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
echo "==> workload: ${#work[@]} suite files x $PASSES passes${CPUMASK:+, pinned to cpus $CPUMASK}"

# ---- dfold: fold mangled D symbols ------------------------------------------
cat >"$profdir/dfold.awk" <<'AWK'
# Functions: segfold(sym) folds one mangled D symbol; foldline() rewrites
# every _D... token on a line. Segments are <len><name> runs after _D,
# ending at the F that starts the argument mangling; anything unparseable
# is passed through unchanged.
function segfold(sym,    s, n, i, m, len, name, out) {
    if (sym !~ /^_D[A-Za-z0-9]/) return sym
    s = substr(sym, 3); n = 0
    while (match(s, /^[0-9]+/)) {
        len = substr(s, RSTART, RLENGTH) + 0
        s = substr(s, RLENGTH + 1)
        if (len == 0 || length(s) < len) return sym
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

# ---- pass 0: per-file render time -------------------------------------------
echo '==> pass 0: per-file render times'
{
    for f in "${work[@]}"; do
        t0=$(date +%s%N)
        runon "$profdir/app-release" "$f" >/dev/null 2>/dev/null
        t1=$(date +%s%N)
        printf '%d %s\n' $(((t1 - t0) / 1000000)) "$f"
    done
} | sort -nr >"$profdir/times.txt"
awk '{t += $1} END {printf "    total %d ms over %d files\n", t, NR}' "$profdir/times.txt"

# ---- pass B: perf record + flamegraph + tops ---------------------------------
echo '==> pass B: perf record (cycles)'
args=()
for ((i = 0; i < PASSES; i++)); do args+=("${work[@]}"); done
rm --force "$profdir/perf.data"    # perf record -f does not exist; just remove first
have_cg=1
if runon perf record --call-graph dwarf,32768 -o "$profdir/perf.data" \
        -- "$profdir/app-perf" "${args[@]}" >"$profdir/perf-record.log" 2>&1; then
    echo '    dwarf call graphs recorded'
else
    # perf_event_paranoid > 0 or SELinux deny stack-dumping events;
    # leaf samples (and thus self profiles) still record exactly.
    have_cg=0
    echo '    call-graph events denied; recording leaf-only instead'
    rm --force "$profdir/perf.data"
    runon perf record -e cycles -o "$profdir/perf.data" \
        -- "$profdir/app-perf" "${args[@]}" >>"$profdir/perf-record.log" 2>&1
fi
tail -1 "$profdir/perf-record.log"

if (( have_cg )); then
    perf script -i "$profdir/perf.data" | stackcollapse-perf.pl |
        awk -f "$profdir/dfold.awk" -e '{
            cnt = $NF
            stack = $0; sub(/ [0-9]+$/, "", stack)
            nf = split(stack, a, ";")
            out = segfold(a[1])
            for (i = 2; i <= nf; i++) out = out ";" segfold(a[i])
            print out, cnt
        }' >"$profdir/folded.txt"
    flamegraph.pl --title 'graphics:svg - W3C suite render' \
        "$profdir/folded.txt" >"$profdir/flame.svg"
else
    # stackcollapse-perf.pl rejects stack-less samples; on a leaf-only
    # record the per-symbol counts already *are* the folded input.
    # (This perf build's `-F sym` prints nothing at all, so take the
    # default output and cut the "addr symbol (dso)" tail.)
    perf script -i "$profdir/perf.data" |
        sed -E 's/.*: +[0-9a-f]+ +([^ ]+)(\+0x[0-9a-f]+)? \([^)]*\)$/\1/; /^[[:space:]]*$/d' |
        sort | uniq -c |
        awk -f "$profdir/dfold.awk" -e '{print segfold($2), $1}' >"$profdir/folded.txt"
    flamegraph.pl --title 'graphics:svg - W3C suite render (leaf-only)' \
        "$profdir/folded.txt" >"$profdir/flame.svg" || rm -f "$profdir/flame.svg"
fi

# leaf (self) samples per function.  sort|head is a pipefail trap (head exits
# early, sort dies of SIGPIPE, the pipeline reports failure): sort to a full
# file first, then head from disk.
awk '{cnt = $NF; stack = $0; sub(/ [0-9]+$/, "", stack)
      n = split(stack, a, ";"); self[a[n]] += cnt; tot += cnt}
     END {for (s in self) printf "%.2f %d %s\n", 100 * self[s] / tot, self[s], s}' \
    "$profdir/folded.txt" | sort -nr >"$profdir/top-self.full"
head -50 "$profdir/top-self.full" >"$profdir/top-self.txt"

# per-module rollup: self = leaf group; incl = unique modules per stack
awk '{cnt = $NF; stack = $0; sub(/ [0-9]+$/, "", stack)
      nf = split(stack, a, ";")
      self[mod(a[nf])] += cnt; tot += cnt
      delete seen
      for (i = 1; i <= nf; i++) {
          m = mod(a[i])
          if (!(m in seen)) { seen[m] = 1; incl[m] += cnt }
      }}
     function mod(s,   t) { t = s; sub(/\.[^.]*$/, "", t); return t == s ? s : t }
     END {for (g in self) printf "%6.2f %6.2f %d %s\n", 100 * incl[g] / tot, 100 * self[g] / tot, self[g], g}' \
    "$profdir/folded.txt" | sort -k1,1nr >"$profdir/rollup.full"
head -40 "$profdir/rollup.full" >"$profdir/rollup.txt"

echo '==> pass C: perf stat -d (one pass)'
runon perf stat -d -- "$profdir/app-perf" "${work[@]}" >/dev/null 2>"$profdir/perf-stat.txt"

# ---- pass D: instruction census -----------------------------------------------
# Instruction shares, not cycles: cycles sampling on hybrid CPUs was proven
# misleading (E-core/idle-GC-thread samples distort every percentage; see the
# GC profile check below). Retired instructions are a workload constant, and
# perf report symbolizes the app binary's leaves correctly (unlike the dwarf
# call chains, which truncate at the main binary's CFI gaps).
echo '==> pass D: instruction census (perf record, leaf samples)'
rm -f "$profdir/instr.data"
ev_ok=
for ev in instructions cpu_core/instructions/; do
    # No call-graph flag: on this hybrid PMU *any* call-graph mode makes the
    # event open fail outright (the fp/dwarf unwind needs registers the PMU
    # rejects), and leaf-only is exactly what this pass wants.
    if runon perf record -e "$ev" \
            -o "$profdir/instr.data" -- "$profdir/app-perf" "${work[@]}" \
            >>"$profdir/perf-instr.log" 2>&1; then
        ev_ok=$ev
        break
    fi
    rm -f "$profdir/instr.data"
done
if [[ -n $ev_ok ]]; then
    echo "    recorded with -e $ev_ok"
    perf report -i "$profdir/instr.data" --stdio --sort symbol -G -g none \
            --percent-limit 0.02 2>/dev/null |
        grep -vE '^#' >"$profdir/top-instructions.txt"
    echo '    wrote top-instructions.txt (self instruction share per symbol)'
else
    echo '    instructions event unavailable; skipping pass D' >&2
fi
# GC cost belongs in the record too: --DRT-gcopt=profile:1 prints druntime's
# own accounting (collections, mark/sweep ms, max pause) on stdout at exit.
echo '==> GC accounting (druntime profile:1)'
runon "$profdir/app-perf" --DRT-gcopt=profile:1 "${work[@]}" 2>/dev/null |
    grep -E 'Number of collections|Grand total GC|GC summary' \
    >"$profdir/gc-profile.txt" || true
[[ -s $profdir/gc-profile.txt ]] && sed 's/^/    /' "$profdir/gc-profile.txt"

# ---- pass A: callgrind over the worst files + one non-worst-class file --------
echo '==> pass A: callgrind (budget '"${CG_BUDGET}"' ms of rendering, 0 = all)'
mapfile -t cg < <(
    awk -v b="$CG_BUDGET" 'b == 0 || acc < b {print $2; acc += $1}' "$profdir/times.txt")
((${#cg[@]})) || { echo 'callgrind: times.txt produced no files' >&2; exit 1; }
# worst-first within budget is all filter-class on this suite; add the slowest
# file outside the worst file's name class so encoding/text/GC ratios also get
# a call-tree view.
base=$(basename "${cg[0]}" | cut -d- -f1)
extra=$(awk -v c="$base" 'index($2, c "-") == 0 {print $2; exit}' "$profdir/times.txt")
[[ -n $extra ]] && cg+=("$extra")
echo "    files: ${#cg[@]}"
runon valgrind -q --tool=callgrind --callgrind-out-file="$profdir/callgrind.out.%p" \
    -- "$profdir/app-perf" "${cg[@]}" >"$profdir/callgrind-stdout.txt" 2>&1
cgout=("$profdir"/callgrind.out.*)
[[ -e ${cgout[0]} ]] || { echo 'callgrind produced no data' >&2; exit 1; }
# Raw annotate output: callgrind_annotate already prints file:function with
# demangled C++/druntime names; D app symbols stay mangled (no demangler in
# binutils) but match in any text editor against the _D... spelling.
callgrind_annotate --threshold=99 "${cgout[@]}" 2>&1 \
    >"$profdir/callgrind-top.txt"
callgrind_annotate --inclusive=yes --threshold=99 "${cgout[@]}" 2>&1 \
    >"$profdir/callgrind-inclusive.txt"

echo "==> artifacts in $profdir:"
ls "$profdir" | sed 's/^/    /'
echo "done. Read prof/top-instructions.txt and prof/gc-profile.txt first,"
echo "then callgrind-top.txt (worst files) and times.txt; flame.svg is only a"
echo "leaf picture (dwarf stacks truncate at the app binary's CFI gaps)."
echo "Verify with: bash tests/w3c/run.sh   (the gate must stay at its committed AE)"
