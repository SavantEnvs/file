#!/usr/bin/env bash
# Runs upstream's own tests/ suite (tests/*.testfile vs tests/*.result, what `make check` does) with
# the normal-flags libmagic built by build.sh. Each case asserts the exact detection string.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
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

T="$SRC/tests"
RUNNER="$SRC/bld-test/tests/test"
[ -x "$RUNNER" ] || { echo "test runner $RUNNER missing (mayhem/build.sh should have built it)" >&2; emit_ctrf "libmagic-tests" 0 1; exit 1; }

pass=0; fail=0; skip=0
for i in "$T"/*.testfile; do
  t="${i%.testfile}"
  # Upstream added the mcap-* tests (PR/186) without the magic/Magdir/mcap fragment they exercise;
  # skip them until the fragment exists rather than reporting a failure upstream itself has.
  case "$(basename "$t")" in mcap-*) if [ ! -f "$SRC/magic/Magdir/mcap" ]; then skip=$((skip+1)); continue; fi ;; esac
  m=""
  for j in "$t"*.magic; do
    [ -f "$j" ] || continue
    m="${m:+$m:}$j"
  done
  [ -n "$m" ] || m="$SRC/bld-test/magic/magic"
  f="-e"
  [ -f "$t.flags" ] && f="$f$(cat "$t.flags")"
  # expected string, with the single trailing newline stripped as test.c does
  expected="$(cat "$t.result")"
  err="$(mktemp)"
  out="$(TZ=UTC MAGIC="$m" "$RUNNER" "$f" "$i" "$t.result" 2>"$err")"; rc=$?
  # Behavioral assertion: the runner must exit 0 AND report exactly the expected detection string.
  if [ "$rc" -eq 0 ] && [ "$out" = "$i: [$expected]" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); echo "FAIL $(basename "$t") (rc=$rc): $out $(cat "$err")" >&2
  fi
  rm -f "$err"
done

emit_ctrf "libmagic-tests" "$pass" "$fail" "$skip"
