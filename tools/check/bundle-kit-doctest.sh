#!/bin/sh
# bundle-kit-doctest.sh -- the bundle kit's doctest runs a bundle's
# documentation examples.
#
# tools/bundle-kit/doctest.sh extracts the (example ...) forms from a bundle's
# modules and runs them.  Held here, on fixture bundles:
#
#   - an example that prints what it says passes, and is counted;
#   - an example that prints something else fails the run;
#   - a listed entry is not imported, so its main never runs and nothing it
#     sets at its top level reaches the walk;
#   - a file of another module, and constructs.x, are not imported;
#   - a bundle with no example passes and says so;
#   - a tree with no bundle.xon is refused.
#
# The fixtures boot this tree's x, once or twice a case.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1
X="$PROJECT_DIR/x.sh"
KIT="$PROJECT_DIR/tools/bundle-kit/doctest.sh"

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fails=0

# run DIR -- the kit's output in $out and its status in $st
run() {
	out=$(BUNDLE="$1" X="$X" sh "$KIT" 2>&1) && st=0 || st=$?
}

# A library: one module with two examples that hold, a second file of that
# module, a data file, and a listed entry whose top level would end the walk
# if it were imported.
B="$TMP/good"
mkdir -p "$B/lib/dt"
printf '(name "dt")\n(dialect he)\n(entry run)\n' > "$B/bundle.xon"
cat > "$B/lib/dt/m.x" <<'EOF'
(module dt/m)
(def twice (fn (_ n) (+ n n)))
(doc twice
  (param n INTEGER "A number")
  (returns INTEGER "n added to itself")
  (example "(twice 21)" "42")
  (example "(twice 0)" "0")
  "n added to itself.")
(include-once "./m-more.x")
(provide dt/m (global twice) (global thrice))
EOF
cat > "$B/lib/dt/m-more.x" <<'EOF'
(module dt/m)
(def thrice (fn (_ n) (+ n (+ n n))))
(doc thrice
  (param n INTEGER "A number")
  (returns INTEGER "n three times over")
  (example "(thrice 3)" "9")
  "n three times over.")
EOF
printf '((my-form (fmt . head-1)))\n' > "$B/lib/dt/constructs.x"
cat > "$B/lib/dt/run.x" <<'EOF'
(module dt/run)
(Sys exit 7)
(def main (fn (_) ()))
(provide dt/run main)
EOF

run "$B"
case "$st:$out" in
	0:*"3 tests, 0 failed"*) printf '  examples that print what they say pass, each counted: ok\n' ;;
	*) printf 'bundle-kit-doctest: three true examples did not pass as three:\n%s\n' "$out" >&2
	   fails=$((fails + 1)) ;;
esac
if [ -f "$B/tests/lib/doctest/doctests.spec.md" ]; then
	printf '  the spec is written under tests/lib/doctest: ok\n'
else
	printf 'bundle-kit-doctest: no spec was written under tests/lib/doctest\n' >&2
	fails=$((fails + 1))
fi

# The same bundle with an example that does not hold.
C="$TMP/bad"
cp -R "$B" "$C"
rm -rf "$C/tests"
sed 's/(example "(twice 0)" "0")/(example "(twice 0)" "1")/' "$B/lib/dt/m.x" > "$C/lib/dt/m.x"
run "$C"
case "$st:$out" in
	0:*) printf 'bundle-kit-doctest: an example that prints something else passed:\n%s\n' "$out" >&2
	     fails=$((fails + 1)) ;;
	*"1 failed"*) printf '  an example that prints something else fails the run: ok\n' ;;
	*) printf 'bundle-kit-doctest: the run failed without counting the false example:\n%s\n' "$out" >&2
	   fails=$((fails + 1)) ;;
esac

# A bundle whose documentation carries no example.
D="$TMP/none"
mkdir -p "$D/lib/dn"
printf '(name "dn")\n' > "$D/bundle.xon"
printf '(module dn/m)\n(def one (fn (_) 1))\n(provide dn/m one)\n' > "$D/lib/dn/m.x"
run "$D"
case "$st:$out" in
	0:*"ok (no examples)"*) printf '  a bundle with no example passes and says so: ok\n' ;;
	*) printf 'bundle-kit-doctest: a bundle with no example did not pass plainly:\n%s\n' "$out" >&2
	   fails=$((fails + 1)) ;;
esac

# A tree that is not a bundle.
mkdir -p "$TMP/notone/lib"
run "$TMP/notone"
case "$st:$out" in
	0:*) printf 'bundle-kit-doctest: a tree with no bundle.xon was accepted\n' >&2; fails=$((fails + 1)) ;;
	*"no bundle.xon"*) printf '  a tree with no bundle.xon is refused: ok\n' ;;
	*) printf 'bundle-kit-doctest: the refusal did not name the missing bundle.xon:\n%s\n' "$out" >&2
	   fails=$((fails + 1)) ;;
esac

[ "$fails" = 0 ] || { echo "bundle-kit-doctest: $fails failed" >&2; exit 1; }
echo "bundle-kit-doctest: ok"
