#!/usr/bin/env bash
#
# mayhem/test.sh — RUN vengi's own voxelformat gtest suite (built by mayhem/build.sh with normal
# flags in build-tests/). Parses gtest's summary lines, so a neutered binary (no output) fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

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

RUNNER="$SRC/build-tests/tests-voxelformat/vengi-tests-voxelformat"
if [ ! -x "$RUNNER" ]; then
  echo "missing $RUNNER - mayhem/build.sh must build it" >&2
  emit_ctrf gtest 0 1 0
  exit 1
fi

# The suite reads its fixtures relative to its own directory; it needs a writable HOME for the app dirs.
export HOME="${TMPDIR:-/tmp}/vengi-test-home"
mkdir -p "$HOME"
OUT="$(mktemp)"
(cd "$(dirname "$RUNNER")" && "$RUNNER" >"$OUT" 2>&1)
rc=$?
tail -n 30 "$OUT"

total=$(sed -n 's/^\[==========\] \([0-9][0-9]*\) tests\{0,1\} from .* ran\..*/\1/p' "$OUT" | tail -n1)
passed=$(sed -n 's/^\[  PASSED  \] \([0-9][0-9]*\) tests\{0,1\}\./\1/p' "$OUT" | tail -n1)
skipped=$(sed -n 's/^\[  SKIPPED \] \([0-9][0-9]*\) tests\{0,1\}, listed below:/\1/p' "$OUT" | tail -n1)
failed=$(sed -n 's/^\[  FAILED  \] \([0-9][0-9]*\) tests\{0,1\}, listed below:/\1/p' "$OUT" | tail -n1)
rm -f "$OUT"
: "${total:=0}" "${passed:=0}" "${skipped:=0}" "${failed:=0}"

# Known-answer floor: a run that executed far fewer cases than the suite has is a failure,
# whatever the exit code says (the suite ran 483 tests when this was written).
if [ "$total" -lt 400 ] || [ "$passed" -lt 400 ]; then
  echo "suite ran too few tests (total=$total passed=$passed)" >&2
  failed=$(( failed + 1 ))
fi
[ "$rc" -eq 0 ] || [ "$failed" -gt 0 ] || failed=1
emit_ctrf gtest "$passed" "$failed" "$skipped"
