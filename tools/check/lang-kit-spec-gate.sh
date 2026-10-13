#!/bin/sh
# lang-kit-spec-gate.sh -- the lang kit's spec gate judges output that is not text.
#
# tools/lang-kit/spec-gate.sh reads a bundle's spec-runner output with sed,
# grep and sort.  Held here, on a fixture bundle whose runner prints a raw
# 0xff byte inside a failing case, under a UTF-8 locale:
#
#   - a failure the contract does not record is red, and is named;
#   - the same failure, recorded, is green.
#
# The fixture's runner is a shell script; no x boots.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fails=0

# A bundle whose one failing case prints 0xff, as a case reading binary does.
mkdir -p "$TMP/b/tests/contract"
cat > "$TMP/b/tests/spec-runner.sh" <<'EOF'
printf 'case byte-out\n  got: \377\n'
printf 'FAIL: specs/bytes.spec.md: byte-out\n'
printf '2 tests, 1 failed, 0 pending\n'
exit 1
EOF
printf '# none\n' > "$TMP/b/tests/contract/known-failures.txt"

out=$(BUNDLE="$TMP/b" LC_ALL=en_US.UTF-8 sh tools/lang-kit/spec-gate.sh 2>&1) && st=0 || st=$?
case "$st:$out" in
	0:*) printf 'lang-kit-spec-gate: an unrecorded failure passed\n' >&2; fails=$((fails + 1)) ;;
	*"REGRESSION"*"specs/bytes.spec.md: byte-out"*)
	   printf '  an unrecorded failure beside a 0xff byte is named: ok\n' ;;
	*) printf 'lang-kit-spec-gate: the gate failed without naming the failure:\n%s\n' "$out" >&2
	   fails=$((fails + 1)) ;;
esac

printf 'specs/bytes.spec.md: byte-out\n' > "$TMP/b/tests/contract/known-failures.txt"
out=$(BUNDLE="$TMP/b" LC_ALL=en_US.UTF-8 sh tools/lang-kit/spec-gate.sh 2>&1) && st=0 || st=$?
if [ "$st" = 0 ]; then
	printf '  a recorded failure beside a 0xff byte is green: ok\n'
else
	printf 'lang-kit-spec-gate: a recorded failure read as red:\n%s\n' "$out" >&2
	fails=$((fails + 1))
fi

[ "$fails" = 0 ] || { echo "lang-kit-spec-gate: $fails failed" >&2; exit 1; }
echo "lang-kit-spec-gate: the gate judges a suite whose output holds raw bytes."
