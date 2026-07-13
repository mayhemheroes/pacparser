#!/usr/bin/env bash
#
# pacparser/mayhem/build.sh — build pacparser's in-process libFuzzer harness
# (+ a standalone run-once reproducer) AND the project's own test suite.
#
# The fuzzed surface is the whole PAC engine: the harness feeds raw bytes as a
# PAC script to pacparser_parse_pac_string -> pacparser_find_proxy, which runs
# the embedded QuickJS interpreter (src/quickjs/quickjs.c) plus pacparser's PAC
# helpers (src/pacparser.c). We compile BOTH the engine and the harness with
# $SANITIZER_FLAGS + a coverage-instrumented engine ($COV) so ASan/UBSan and the
# fuzzer see the library, not just the harness file.
#
# Build contract comes from the org base ENV (CC/SANITIZER_FLAGS/DEBUG_FLAGS/
# LIB_FUZZING_ENGINE/SRC).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with
# NO sanitizers (natural crash / full backtrace). Other knobs default on empty.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default (no effect on the test/oracle build); set via
# --build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping" to
# instrument the TEST build only.
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

VERSION="$(git -C "$SRC" describe --always --tags 2>/dev/null || echo v0.0.0)"

# Instrument the ENGINE itself with libFuzzer coverage (SanitizerCoverage), not
# just the harness — otherwise the fuzzer can't explore quickjs/pacparser.
COV="-fsanitize=fuzzer-no-link"

# Build the sanitized fuzz objects into a SEPARATE dir so src/ stays clean for
# the independent, normal-flags test build in step 3 (no sanitizer bleed-through
# into the oracle).
FZ="$SRC/mayhem-build"
rm -rf "$FZ"
mkdir -p "$FZ"

# ── 1) Compile the engine (QuickJS + pacparser) with sanitizers + coverage ────
$CC $SANITIZER_FLAGS $COV $DEBUG_FLAGS -fPIC -Isrc/quickjs \
    -c src/quickjs/quickjs.c -o "$FZ/quickjs.o"
$CC $SANITIZER_FLAGS $COV $DEBUG_FLAGS -fPIC -Isrc/quickjs -DVERSION="$VERSION" \
    -c src/pacparser.c -o "$FZ/pacparser.o"

# ── 2) Link the harness twice: libFuzzer target + standalone reproducer ───────
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -Isrc -Isrc/quickjs \
    "$SRC/mayhem/pacparser_fuzz.c" "$FZ/pacparser.o" "$FZ/quickjs.o" \
    $LIB_FUZZING_ENGINE -lm -o /mayhem/pacparser

$CC $SANITIZER_FLAGS $DEBUG_FLAGS -Isrc -Isrc/quickjs \
    "$SRC/mayhem/pacparser_fuzz.c" "$SRC/mayhem/harnesses/pacparser_standalone.c" \
    "$FZ/pacparser.o" "$FZ/quickjs.o" -lm -o /mayhem/pacparser-standalone

echo "built /mayhem/pacparser (+ standalone)"
ls -la /mayhem/pacparser /mayhem/pacparser-standalone

# ── 3) Build the project's OWN test suite with NORMAL flags (clean, independent
#       of the sanitized build above) so mayhem/test.sh only RUNS it. This is
#       exactly what upstream CI builds: pactester + libpacparser.so.1 (driving
#       tests/runtests.sh) and the four tests/*.c resolve_host unit programs. ──
make -C "$SRC/src" clean >/dev/null 2>&1 || true
make -C "$SRC/src" CFLAGS="$COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" \
     pactester libpacparser.so -j"$MAYHEM_JOBS"

# Unit-test binaries go under mayhem-build/ (NOT tests/ — upstream tracks a
# stale tests/test_resolve_host blob; keep the checkout clean).
mkdir -p "$FZ/tests"
for t in test_resolve_host test_multi_ip test_buffer_safety test_edge_cases; do
  $CC -g -Wall $COVERAGE_FLAGS -o "$FZ/tests/$t" "$SRC/tests/$t.c"
done

echo "build.sh complete:"
ls -la "$SRC/src/pactester" "$SRC/src/libpacparser.so.1" 2>&1 || true
