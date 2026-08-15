# defs.awk -- emit every TOP-LEVEL definition, one per line, as
#
#     FILE <TAB> NAME <TAB> BODY
#
# "Top-level" means "binds globally", which is not the same as "starts in
# column 0": a def directly inside a top-level (do ...) binds in the caller's
# env too, because %do-seq tail-evals its children there.  Descending that is
# what makes the tool scripts visible -- they wrap their whole body in one
# (do ...), so a column-0 line grep sees almost nothing.
#
# Recognized definers: (def NAME ...), (def-class NAME ...), and their
# (doc ...) wrappers.  Strings, #\X char literals and ; comments are tracked
# so their parens and semicolons cannot be miscounted.
#
# Consumers: tools/check/percent-globals.sh (counts %-names per file).
# dup-defs.sh still carries its own copy of this scan; migrating it onto this
# file is tracked in #304 -- it is a working gate with adjudicated allowlists,
# so it moves on its own change, not as a side effect of this one.

# Split the children of a top-level (do ...) body into kids[1..n], tracking
# strings and #\X char literals so their parens do not count.  Only
# list-shaped children are collected (an atom cannot define anything).
function split_children(f, kids,    s, i, n, c, depth, start, cnt, str) {
  s = f
  sub(/^\(do[ \t]*/, "", s)
  sub(/\)[ \t]*$/, "", s)
  n = length(s); depth = 0; str = 0; cnt = 0; start = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (str) {
      if (c == "\\") i++
      else if (c == "\"") str = 0
      continue
    }
    if (c == "#" && substr(s, i, 2) == "#\\") { i += 2; continue }
    if (c == "\"") { str = 1; continue }
    if (c == "(") {
      if (depth == 0) start = i
      depth++
    } else if (c == ")") {
      depth--
      if (depth == 0 && start > 0) {
        kids[++cnt] = substr(s, start, i - start + 1)
        start = 0
      }
    }
  }
  return cnt
}

function handle(f,    tmp, name, body, kids, nk, j) {
  if (f ~ /^\(do[ \t(]/) {
    nk = split_children(f, kids)
    for (j = 1; j <= nk; j++) handle(kids[j])
    return
  }
  tmp = f
  if (tmp ~ /^\(doc[ \t]*\(def(-class)?[ \t]/) sub(/^\(doc[ \t]*/, "", tmp)
  if (tmp ~ /^\(def(-class)?[ \t]/) {
    sub(/^\(def(-class)?[ \t]+/, "", tmp)
    name = tmp
    sub(/[ \t)].*$/, "", name)
    body = tmp
    sub(/^[^ \t]+[ \t]*/, "", body)
    if (name != "") printf "%s\t%s\t%s\n", FILENAME, name, body
  }
}

function flush_form() {
  if (form == "") return
  handle(form)
  form = ""
}

FNR == 1 { depth = 0; instr = 0; form = "" }

{
  line = $0
  n = length(line)
  out = ""
  i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (instr) {
      out = out c
      if (c == "\\") { i++; if (i <= n) out = out substr(line, i, 1) }
      else if (c == "\"") instr = 0
    } else if (c == ";") {
      break
    } else if (c == "#" && substr(line, i, 2) == "#\\") {
      out = out substr(line, i, 3)
      i += 2
    } else {
      out = out c
      if (c == "\"") instr = 1
      else if (c == "(") depth++
      else if (c == ")") depth--
    }
    i++
  }
  if (out != "") {
    gsub(/[ \t]+/, " ", out)
    sub(/^ /, "", out)
    sub(/ $/, "", out)
    if (out != "") form = (form == "" ? out : form " " out)
  }
  if (depth == 0 && form != "") flush_form()
}

END { flush_form() }
