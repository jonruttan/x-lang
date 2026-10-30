#!/bin/sh
# wrapper.sh -- x.sh's own entry points still evaluate what they are handed.
#
# The spec suite cannot see this surface.  Every spec runs
# `cat $LANG_LIB $tmpfile | $X_BIN`: the runner talks to the engine, so a spec
# measures the language rather than the shell around it, and x.sh's argument
# handling goes untested there.
#
# The rule held here: each way in must evaluate what it is handed and say so in
# the exit status.  A route that quietly does nothing is the failure being
# gated, so every case asserts on output rather than on status alone.
#
# One engine boot per case, helium, no tower, so it can sit in gates-fast.
# Every capture carries `|| true`: set -e does not spare a command
# substitution, so a wrapper that died would otherwise abort this script
# without a word.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fails=0

# want NAME EXPECTED ACTUAL
want() {
	if [ "$2" = "$3" ]; then
		printf '  %s: ok\n' "$1"
	else
		printf 'wrapper: %s -- expected [%s], got [%s]\n' "$1" "$2" "$3" >&2
		fails=$((fails + 1))
	fi
}

got=$(sh x.sh -q -c '(write (+ 1 2))' 2>/dev/null || true)
want "-c evaluates an expression" "3" "$got"

# Repeatable and ORDERED: the second expression must see the first's def, so
# this fails both if -c stops after one and if the two arrive out of order.
got=$(sh x.sh -q -c '(def n 7)' -c '(write (* n 6))' 2>/dev/null || true)
want "-c is repeatable, in order" "42" "$got"

got=$(printf '(write (+ 1 2))\n' | sh x.sh -q 2>/dev/null || true)
want "stdin is program text" "3" "$got"

printf '(write "from-file")\n' > "$TMP/p.x"
got=$(sh x.sh -q -f "$TMP/p.x" 2>/dev/null || true)
want "-f evaluates a file" '"from-file"' "$got"

# -F loads and continues, so its file must be evaluated BEFORE the -c
# expressions that follow; the concatenation is the ordering assertion.
got=$(sh x.sh -q -F "$TMP/p.x" -c '(write "then-eval")' 2>/dev/null || true)
want "-F runs before -c" '"from-file""then-eval"' "$got"

# The engine is started as `x-bin OPTION... -- ARG...`, so the program's
# arguments and the wrapper's options never mix: an argument spelled like one
# of the wrapper's options reaches the program as written, and the wrapper's
# options are read from their side of the "--" alone.
got=$(sh x.sh -q -c '(write (rest (Sys args (lit program))))' -- a --no-color --batch 2>/dev/null || true)
want "the program's arguments arrive as written" '("a" "--no-color" "--batch")' "$got"
got=$(sh x.sh -q -c '(write (Sys %launch-options))' -- --no-color 2>/dev/null || true)
want "a program's argument is not the wrapper's option" '("--quiet" "--batch")' "$got"
got=$(sh x.sh -q --no-color -c '(write (rest (Sys args (lit program))))' 2>/dev/null || true)
want "the wrapper's option is not the program's argument" '()' "$got"

# The status half of the rule.  A raise must reach the shell as a failure and
# the message must reach stderr, or a script cannot tell a broken run from an
# empty one -- which is exactly what the silent no-op looked like.
if sh x.sh -q -c '(no-such-binding)' >/dev/null 2>&1; then
	printf 'wrapper: a raised error exited 0\n' >&2
	fails=$((fails + 1))
else
	printf '  a raised error exits non-zero: ok\n'
fi

# `|| true`: this command is SUPPOSED to fail, and set -e does not spare a
# command substitution.
err=$(sh x.sh -q -c '(no-such-binding)' 2>&1 >/dev/null || true)
case "$err" in
	*no-such-binding*) printf '  the error reaches stderr: ok\n' ;;
	*)
		printf 'wrapper: error text not on stderr, got [%s]\n' "$err" >&2
		fails=$((fails + 1))
		;;
esac

# The location half: a raise in a -f file names the file and the line, in
# the library's wording (lib/x/repl/batch.x), and the file's forms before
# it ran.  A -c expression has no file, so its report starts bare.
printf '(write "one")\n\n(no-such-binding)\n(write "never")\n' > "$TMP/e.x"
got=$(sh x.sh -q -f "$TMP/e.x" 2>/dev/null || true)
want "-f runs up to the raise" '"one"' "$got"
err=$(sh x.sh -q -f "$TMP/e.x" 2>&1 >/dev/null || true)
want "a raise in -f names the file and line" "Error [$TMP/e.x:3]: Unbound SYMBOL 'no-such-binding'" "$err"
err=$(sh x.sh -q -c '(no-such-binding)' 2>&1 >/dev/null || true)
want "a raise in -c is reported bare" "Error: Unbound SYMBOL 'no-such-binding'" "$err"

# With a lang leading, the -f file reaches the lang's own reader as text on
# stdin (x-logo's batch reader, x-python's loop), so it is cat'd whole and
# not wrapped in an include form: a raise in it carries no file and line,
# which is the visible half of that.  seamprobe stands in for a lang.
err=$(X_LANG_DIR=tools/contract/bundles/ sh x.sh --no-pin -q -l seamprobe -f "$TMP/e.x" 2>&1 >/dev/null || true)
want "a lang's -f file is text for its reader, not an include form" "Error: Unbound SYMBOL 'no-such-binding'" "$err"

# An interactive session is no program, so its lang's entry runs with no guard
# around it, as the session it hands over to does.  A lang's REPL depends on
# that: the engine raises STOP on a ctrl-c only while a guard is active, so the
# lang's own handler for an interrupted read runs with the flag still set, and
# a batch loop's guard outside it would take the STOP and end the session.
# guardprobe's entry sets the flag and takes one step; a pty makes the session
# interactive, and the session reads back whether the entry got past it.
cat > "$TMP/session.x" <<'EOF'
(import x/sys/pty)
(import x/sys/file)
(def %drain
  (fn (_ fd)
    (def buf ((prim-ref 'str 'make) 256))
    (let go ((acc ""))
      (let ((n (File read fd buf 256)))
        (if (<= n 0) acc (go (Str8 append acc (Str8 sub 0 n buf))))))))
(def %line "(write (guard (_ 'unbound) guardprobe-unguarded)) (Sys exit 0)\n")
(def c (Pty spawn "/bin/sh" (list "-c" "X_LANG_DIR=tools/contract/bundles/ exec sh x.sh --no-pin -q -l guardprobe") 80 24))
(File write (rest c) %line (Str8 length %line))
(def out (%drain (rest c)))
(File close (rest c))
(write (list (Sys wait (first c)) (Str8 ends? "#t\r\n" out)))
EOF
got=$(sh x.sh -q -f "$TMP/session.x" 2>/dev/null || true)
want "an interactive lang session runs with no guard around it" '(0 #t)' "$got"

# The dialect flag still selects: helium has no tower, xenon does.  One case,
# because a wrong dialect is the other way a route silently answers wrong.
got=$(sh x.sh -q -l xe -c '(write (+ 1/3 1/6))' 2>/dev/null || true)
want "-l selects the dialect" "1/2" "$got"

# A further -l loads a bundle beside the first lang.  The fixture bundle the
# seam gate uses is enough: what is under test is the wrapper's arrangement
# -- the root armed, the entry read, and %lang-lead naming the first.
got=$(X_LANG_DIR=tools/contract/bundles/ sh x.sh --no-pin -q -l he -l seamprobe \
	-c '(write (list %lang-lead (Str8 ends? "seamprobe/run.x" (%module-resolve-file "run.x")) (guard (_ "no root") %lang-root)))' 2>/dev/null || true)
want "a further -l loads a bundle beside a dialect" '("he" #t "no root")' "$got"
got=$(X_LANG_DIR=tools/contract/bundles/ sh x.sh --no-pin -q -l seamprobe -c '(write %lang-lead)' 2>/dev/null || true)
want "the first -l is the lead" '"seamprobe"' "$got"
# X_LANG_DIR with no trailing slash finds the same bundles: the wrapper
# appends the slash, since every bundle README spells the checkout form
# `X_LANG_DIR=/path/to/x-NAME/..`.
got=$(X_LANG_DIR=tools/contract/bundles sh x.sh --no-pin -q -l seamprobe -c '(write %lang-lead)' 2>/dev/null || true)
want "X_LANG_DIR without a trailing slash finds a bundle" '"seamprobe"' "$got"
got=$(sh x.sh --no-pin -q -l he -c '(write (guard (_ "unbound") %lang-lead))' 2>/dev/null || true)
want "no bundle, no lead" '"unbound"' "$got"
if X_LANG_DIR=tools/contract/bundles/ sh x.sh --no-pin -q -l he -l xe -c '()' >/dev/null 2>&1; then
	printf 'wrapper: a further -l naming a dialect was accepted\n' >&2
	fails=$((fails + 1))
else
	printf '  a further -l must name a bundle: ok\n'
fi

if [ "$fails" -gt 0 ]; then
	printf 'wrapper: %d failure(s).\n' "$fails" >&2
	exit 1
fi
printf 'wrapper: every entry point evaluates what it is handed.\n'
