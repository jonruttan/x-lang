#!/bin/sh
# provide-names.sh -- no provide list names a %-private (x-lang#719, step 4).
#
# A module's provide list is its public surface, and a %-prefixed name says
# "not API": the two cannot both be true of one name.  Fourteen exports
# carried the sigil when step 4 began, and each was renamed bare as its
# owner was scoped or, for the last two (type/class.x), by decision; this
# gate keeps the count at zero.
#
# The scan reads every (provide M ...) and (doc (provide M ...) ...) form
# under lib/, tracking parentheses from the provide's own open paren, and
# reports a name at the list's depth that starts with '%'.  A (global NAME)
# mark sits one level deeper and is skipped with its group; the strings and
# notes a doc form carries follow the close of the provide form and are
# never reached.
#
# Usage: sh tools/check/provide-names.sh [FILE...]; without arguments it
# scans every .x under lib/.
set -u
cd "$(dirname "$0")/../.."
fail=0
files=${*:-$(find lib -name '*.x' | sort)}
for f in $files; do
  awk -v file="$f" '
    # Strip a comment tail (a ; outside a string) before scanning.
    function strip(line,   i, c, instr, out) {
      out = ""; instr = 0
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (instr) { if (c == "\\") { out = out c substr(line, i+1, 1); i++; continue }
                     if (c == "\"") instr = 0; out = out c; continue }
        if (c == "\"") { instr = 1; out = out c; continue }
        if (c == ";") break
        out = out c
      }
      return out
    }
    { line = strip($0) }
    # Not inside a provide form: look for one starting on this line.
    !inprov {
      if (match(line, /\(provide[ \t]+/)) {
        inprov = 1; depth = 0
        rest = substr(line, RSTART)      # from the provide open paren onward
      } else next
    }
    inprov {
      if (rest == "") rest = line
      n = split(rest, ch, "")
      tok = ""
      for (i = 1; i <= n; i++) {
        c = ch[i]
        if (c == "(") { if (tok != "") { check(tok); tok = "" } depth++; continue }
        if (c == ")") { if (tok != "") { check(tok); tok = "" } depth--
                        if (depth == 0) { inprov = 0; rest = ""; next } continue }
        if (c == " " || c == "\t") { if (tok != "") { check(tok); tok = "" } continue }
        tok = tok c
      }
      if (tok != "") { check(tok); tok = "" }
      rest = ""
    }
    # depth 1 is the provide list itself: its first token is "provide", its
    # second the module name; every later token is an export.  Deeper
    # tokens belong to a (global NAME) mark.
    function check(t) {
      if (depth != 1) return
      seen++
      if (seen <= 2) return
      if (substr(t, 1, 1) == "%") { printf "provide-names: %s exports %s -- a provide list names no %%-private; rename it bare\n", file, t; bad = 1 }
    }
    inprov == 0 { seen = 0 }
    END { exit bad ? 1 : 0 }
  ' "$f" || fail=1
done
[ "$fail" -eq 0 ] && echo "provide-names: no provide list names a %-private."
exit $fail
