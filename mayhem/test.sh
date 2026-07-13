#!/usr/bin/env bash
#
# pacparser/mayhem/test.sh — RUN pacparser's OWN test suite (already built by
# mayhem/build.sh with normal flags) and emit a CTRF summary. exit 0 iff nothing
# failed.
#
# This is a BEHAVIORAL oracle: tests/runtests.sh drives the built pactester
# against tests/proxy.pac + tests/testdata and diffs the ACTUAL proxy string
# against the expected golden result for every case (plus a logging.pac stdout/
# stderr golden check). A no-op / exit(0) patch to the engine makes pactester
# emit the wrong (empty) result and the golden diff FAILS — so this cannot be
# reward-hacked by neutering the program. The four tests/*.c programs are
# upstream's resolve_host unit tests (run verbatim, as upstream CI does).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASSED=0; FAILED=0; SKIPPED=0

# ── 1) Functional golden suite: pactester over tests/proxy.pac + testdata, plus
#       the logging.pac stdout/stderr golden check. NO_INTERNET=1 skips the one
#       INTERNET_REQUIRED case (www.google.com isResolvable) so the oracle is
#       deterministic + air-gapped. ─────────────────────────────────────────────
if [ ! -x "$SRC/src/pactester" ] || [ ! -f "$SRC/src/libpacparser.so.1" ]; then
  echo "pactester / libpacparser.so.1 missing — mayhem/build.sh did not build the suite" >&2
  emit_ctrf "pacparser" 0 1 0; exit 2
fi
echo "=== tests/runtests.sh (pactester golden functional suite) ==="
if NO_INTERNET=1 bash "$SRC/tests/runtests.sh"; then
  echo "PASS  runtests.sh (pactester functional golden suite)"
  PASSED=$((PASSED+1))
else
  echo "FAIL  runtests.sh (pactester functional golden suite)"
  FAILED=$((FAILED+1))
fi
# One golden case (INTERNET_REQUIRED) is deliberately skipped offline.
SKIPPED=$((SKIPPED+1))

# ── 2) Upstream resolve_host unit programs (tests/*.c), run as upstream CI does.
echo "=== resolve_host unit tests (tests/*.c) ==="
for t in test_resolve_host test_multi_ip test_buffer_safety test_edge_cases; do
  bin="$SRC/mayhem-build/tests/$t"
  if [ ! -x "$bin" ]; then
    echo "FAIL  $t (binary missing — build.sh did not compile it)"
    FAILED=$((FAILED+1)); continue
  fi
  if "$bin" >/dev/null 2>&1; then
    echo "PASS  $t"
    PASSED=$((PASSED+1))
  else
    echo "FAIL  $t (exit $?)"
    FAILED=$((FAILED+1))
  fi
done

echo "=== pacparser: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="
emit_ctrf "pacparser" "$PASSED" "$FAILED" "$SKIPPED"
