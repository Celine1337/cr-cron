#!/usr/bin/env bash
# Self-contained test suite for cr-cron. Requires crystal (build) + coreutils.
# All schedule assertions use a fixed base-time so results are deterministic.
set -uo pipefail
cd "$(dirname "$0")"
export TC="$HOME/.local/toolchains"
export PATH="$TC/crystal/bin:$PATH"
./build.sh >/dev/null || { echo "FAIL: build failed"; exit 1; }
CRON="./bin/cr-cron"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); }
bad(){ fail=$((fail+1)); echo "FAIL: $1"; }
# assert exit code + stdout substring
check(){ # name expected_exit expected_substring actual_exit actual_out
  local name="$1" want_rc="$2" want="$3" rc="$4" out="$5"
  if [ "$rc" != "$want_rc" ]; then bad "$name (exit $rc, want $want_rc)"; return; fi
  if [ -n "$want" ] && ! printf '%s' "$out" | grep -qF -- "$want"; then
    bad "$name (output missing '$want')"; return
  fi
  ok
}
# assert exit code + exact full stdout (fixture file holds the expected text)
check_exact(){ # name expected_exit expected_file actual_exit actual_out
  local name="$1" want_rc="$2" wantf="$3" rc="$4" out="$5"
  if [ "$rc" != "$want_rc" ]; then bad "$name (exit $rc, want $want_rc)"; return; fi
  printf '%s\n' "$out" > "$TMP/actual.txt"
  if ! diff -u "$wantf" "$TMP/actual.txt" > "$TMP/diff.txt"; then
    bad "$name (output mismatch: $(head -3 "$TMP/diff.txt" | tr '\n' ' '))"; return
  fi
  ok
}

BASE="2026-11-12T10:00:00"   # a Thursday

cat > "$TMP/q15.txt" <<'EOF'
2026-11-12T10:15:00Z
2026-11-12T10:30:00Z
2026-11-12T10:45:00Z
2026-11-12T11:00:00Z
2026-11-12T11:15:00Z
EOF
out=$($CRON "*/15 * * * *" 5 "$BASE"); rc=$?
check_exact "every 15 minutes" 0 "$TMP/q15.txt" "$rc" "$out"

cat > "$TMP/noon.txt" <<'EOF'
2026-11-12T12:00:00Z
2026-11-13T12:00:00Z
2026-11-14T12:00:00Z
EOF
out=$($CRON "0 12 * * *" 3 "$BASE"); rc=$?
check_exact "daily at noon" 0 "$TMP/noon.txt" "$rc" "$out"

out=$($CRON "0 10 * * *" 1 "$BASE"); rc=$?
check "strictly after base (same time rolls to next day)" 0 "2026-11-13T10:00:00Z" "$rc" "$out"

cat > "$TMP/step.txt" <<'EOF'
2026-11-12T11:00:00Z
2026-11-12T13:00:00Z
2026-11-12T15:00:00Z
2026-11-12T17:00:00Z
EOF
out=$($CRON "0 9-17/2 * * *" 4 "$BASE"); rc=$?
check_exact "range with step 9-17/2" 0 "$TMP/step.txt" "$rc" "$out"

cat > "$TMP/or.txt" <<'EOF'
2026-11-13T00:00:00Z
2026-11-20T00:00:00Z
2026-11-27T00:00:00Z
2026-12-04T00:00:00Z
2026-12-11T00:00:00Z
EOF
out=$($CRON "0 0 13 * 5" 5 "$BASE"); rc=$?
check_exact "dom+dow restricted -> OR (Fridays and 13ths)" 0 "$TMP/or.txt" "$rc" "$out"

cat > "$TMP/and.txt" <<'EOF'
2026-11-13T00:00:00Z
2026-12-13T00:00:00Z
EOF
out=$($CRON "0 0 13 * *" 2 "$BASE"); rc=$?
check_exact "dom restricted, dow star -> AND (13ths only)" 0 "$TMP/and.txt" "$rc" "$out"

cat > "$TMP/sun.txt" <<'EOF'
2026-11-15T00:00:00Z
2026-11-22T00:00:00Z
2026-11-29T00:00:00Z
EOF
out=$($CRON "0 0 * * 7" 3 "$BASE"); rc=$?
check_exact "dow 7 means Sunday" 0 "$TMP/sun.txt" "$rc" "$out"
out=$($CRON "0 0 * * 0" 3 "$BASE"); rc=$?
check_exact "dow 0 also means Sunday" 0 "$TMP/sun.txt" "$rc" "$out"

cat > "$TMP/wk.txt" <<'EOF'
2026-11-13T08:00:00Z
2026-11-13T08:30:00Z
2026-11-16T08:00:00Z
2026-11-16T08:30:00Z
EOF
out=$($CRON "0,30 8 * * 1-5" 4 "$BASE"); rc=$?
check_exact "list + weekday range" 0 "$TMP/wk.txt" "$rc" "$out"

out=$($CRON "0 0 1 1 *" 2 "$BASE"); rc=$?
check "month restriction rolls year" 0 "2027-01-01T00:00:00Z" "$rc" "$out"
printf '%s' "$out" | grep -qF "2028-01-01T00:00:00Z" && ok || bad "second new year"

out=$($CRON "0 0 29 2 *" 1 "$BASE"); rc=$?
check "leap day Feb 29 found in 2028" 0 "2028-02-29T00:00:00Z" "$rc" "$out"

out=$($CRON "0 0 * * *" 5 "$BASE"); rc=$?
[ "$(printf '%s\n' "$out" | wc -l)" -eq 5 ] && ok || bad "default count is 5"
out=$($CRON "0 0 * * *" "$BASE" 2>/dev/null); rc=$?
check "base-time cannot be passed as count" 2 "" "$rc" "$out"

# --- invalid expressions: exit 1, message on stderr ---
for badexpr in "61 * * * *" "* 24 * * *" "* * 0 * *" "* * 32 * *" "* * * 13 *" "* * * * 8" \
               "* * * *" "* * * * * *" "*/0 * * * *" "5-3 * * * *" "a * * * *" "1,,2 * * * *" \
               "1-2-3 * * * *" "*/2/3 * * * *" "0 0 30 2 *"; do
  out=$($CRON "$badexpr" 1 "$BASE" 2>"$TMP/err.txt"); rc=$?
  if [ "$rc" = 1 ] && [ -s "$TMP/err.txt" ]; then ok; else bad "invalid expr '$badexpr' (rc=$rc)"; fi
done

# --- bad usage: exit 2 ---
out=$($CRON 2>/dev/null); rc=$?
check "no args exits 2" 2 "" "$rc" "$out"
out=$($CRON "* * * * *" 1 "$BASE" extra 2>/dev/null); rc=$?
check "too many args exits 2" 2 "" "$rc" "$out"
out=$($CRON "* * * * *" abc "$BASE" 2>/dev/null); rc=$?
check "non-numeric count exits 2" 2 "" "$rc" "$out"
out=$($CRON "* * * * *" 0 "$BASE" 2>/dev/null); rc=$?
check "zero count exits 2" 2 "" "$rc" "$out"
out=$($CRON "* * * * *" 1 "not-a-time" 2>/dev/null); rc=$?
check "bad base-time exits 2" 2 "" "$rc" "$out"
out=$($CRON "* * * * *" 1 "2026-02-30T00:00:00" 2>/dev/null); rc=$?
check "impossible base date exits 2" 2 "" "$rc" "$out"

echo "----------------------------------------"
echo "cr-cron: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || exit 1