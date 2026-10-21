#!/bin/sh
# provide-names.sh -- no provide list names a %-private.
#
# A module's provide list is its public surface, and a %-prefixed name says
# "not API": the two cannot both be true of one name.  The scan reads every
# (provide M ...) and (doc (provide M ...) ...) form in the files it is
# given, tracking parentheses from the provide's own open paren, and reports
# a name at the list's depth that starts with '%'.  A (global NAME) mark sits
# one level deeper and is skipped with its group; the strings and notes a doc
# form carries follow the close of the provide form and are never reached.
#
# Part of the lang kit, so a bundle is held to it by tools/lang-kit/lint.sh
# from an installed tree; tools/check/provide-names.sh runs it over lib/.
#
# Usage: sh tools/lang-kit/provide-names.sh FILE...
set -u
fail=0
[ $# -gt 0 ] || { echo "usage: sh tools/lang-kit/provide-names.sh FILE..." >&2; exit 2; }
files=$*
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
