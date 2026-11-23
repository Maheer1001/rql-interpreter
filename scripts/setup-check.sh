#!/usr/bin/env sh
# Setup check for the RQL interpreter.
#
# Verifies that your toolchain can build the project and that the built
# plc-exe binary produces the expected output for every bundled example
# program, then runs the cabal test suite.
#
# Usage (from anywhere):   sh scripts/setup-check.sh [--no-test-suite]
# Exit status: 0 if every check passed, 1 otherwise.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLC="$ROOT/plc"
RUN_SUITE=1
[ "${1:-}" = "--no-test-suite" ] && RUN_SUITE=0

PASSES=0
FAILS=0
FAILED_NAMES=""
pass() { PASSES=$((PASSES + 1)); printf '  PASS %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1)); FAILED_NAMES="$FAILED_NAMES
  - $1"; printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
finish() {
  echo
  if [ "$FAILS" -eq 0 ]; then
    echo "SETUP CHECK PASSED ($PASSES checks)"
    exit 0
  fi
  echo "SETUP CHECK FAILED ($FAILS of $((PASSES + FAILS)) checks failed):$FAILED_NAMES"
  exit 1
}

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t rqlcheck)
trap 'rm -rf "$TMP"' EXIT

# Strip ANSI colour codes, CRs and blank lines so output compares cleanly.
ESC=$(printf '\033')
clean() { sed "s/${ESC}\[[0-9;]*m//g" | tr -d '\r' | grep -v '^[[:space:]]*$'; }

echo "== Toolchain"
if command -v ghc >/dev/null 2>&1; then
  GHC_VER=$(ghc --numeric-version)
  case "$GHC_VER" in
    9.6.*) pass "ghc $GHC_VER (9.6.x required)" ;;
    *) fail "ghc $GHC_VER found, 9.6.x required (tested with 9.6.7; ghcup install ghc 9.6.7)" ;;
  esac
else
  fail "ghc not found on PATH (install GHC 9.6.7, e.g. with GHCup)"
fi
if command -v cabal >/dev/null 2>&1; then
  CABAL_VER=$(cabal --numeric-version)
  case "$CABAL_VER" in
    3.*) pass "cabal $CABAL_VER (3.x required)" ;;
    *) fail "cabal $CABAL_VER found, 3.x required (tested with 3.12.1.0)" ;;
  esac
else
  fail "cabal not found on PATH (install cabal-install 3.x, e.g. with GHCup)"
  finish
fi

echo
echo "== Build"
if (cd "$PLC" && cabal build -v1 exe:plc-exe) >"$TMP/build.log" 2>&1; then
  pass "cabal build exe:plc-exe"
else
  fail "cabal build exe:plc-exe (if it mentions a missing package index, run 'cabal update' first)" "$(tail -n 25 "$TMP/build.log")"
  finish
fi
EXE=$(cd "$PLC" && cabal list-bin -v0 exe:plc-exe)
if [ -x "$EXE" ]; then pass "plc-exe built at $EXE"; else fail "plc-exe binary not found (cabal list-bin gave '$EXE')"; finish; fi

echo
echo "== Example programs (plc/test/golden.txt)"
while read -r dir rql expected rest; do
  case "$dir" in ''|'#'*) continue ;; esac
  name="$rql (from data/$dir)"
  (cd "$PLC/data/$dir" && "$EXE" "$rql") >"$TMP/out" 2>"$TMP/err"
  clean <"$PLC/test/expected/$expected" >"$TMP/want"
  clean <"$TMP/out" >"$TMP/got"
  if [ -s "$TMP/err" ]; then
    fail "$name" "unexpected stderr: $(clean <"$TMP/err")"
  elif cmp -s "$TMP/want" "$TMP/got"; then
    pass "$name"
  else
    fail "$name" "$(diff "$TMP/want" "$TMP/got" 2>&1 || true)"
  fi
done <"$PLC/test/golden.txt"

echo
echo "== Error reporting"
# plc-exe reports errors on stderr (its exit status is 0 either way), so the
# check is: nothing on stdout, and the expected error heading on stderr.
check_error() { # <rql relative to plc/data> <expected stderr text>
  (cd "$PLC/data" && "$EXE" "$1") >"$TMP/out" 2>"$TMP/err"
  if [ ! -s "$TMP/out" ] && clean <"$TMP/err" | grep -qF "$2"; then
    pass "$1 -> $2"
  else
    fail "$1 -> $2" "stdout: $(cat "$TMP/out")
stderr: $(clean <"$TMP/err")"
  fi
}
check_error test/parseError.rql "[Syntax Error]"
check_error test/type-checker/typeError.rql "[Type Error]"
check_error test/evalError.rql "[Evaluation Error]"

if [ "$RUN_SUITE" -eq 1 ]; then
  echo
  echo "== Test suite"
  if (cd "$PLC" && cabal test) >"$TMP/test.log" 2>&1; then
    pass "cabal test ($(grep -o 'All tests passed ([0-9]*)' "$TMP/test.log" | head -n 1))"
  else
    fail "cabal test" "$(grep -E 'FAIL|Error|error' "$TMP/test.log" | head -n 30)"
  fi
fi

finish
