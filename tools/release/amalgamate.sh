#!/bin/sh
# amalgamate.sh -- flatten a boot entry's raw-include chain into one
# self-ordered stream on stdout.
#
# Splice-only, line-oriented, top level only: each spliced file's forms land at
# stream top level, never wrapped in a grouping form.  The stream is parsed
# form-by-form as it evaluates, which preserves the tower's parse-before-eval
# ordering and keeps the (repl) launcher at the top level it requires.  Source
# text is copied verbatim -- a reader round-trip would lose reader-sugar and
# formatting -- so the interpreter sees byte-for-byte the same forms it sees
# under live includes, in the same effective order.
#
# Strict convention, machine-enforced here: a boot-closure raw include sits
# alone on its own line at column 0.  Any other root-relative include anywhere
# in the closure is a build error, not a silent skip.  (Runtime modules contain
# none at all -- tools/check/path-literals.sh.)
#
# The roots include ext/ and engine/.  A root the pattern does not list matches
# neither branch, falls through to `print line`, and travels into the amalgam
# unresolved; the installed tree has no ext/, so boot then fails with no
# diagnostic of its own.  engine/ is the symlink at the repo root naming
# whichever engine this tree builds against, and the boot's first two includes
# come from it.
#
# Usage: sh tools/release/amalgamate.sh lib/xe.x > build/boot/xe.x

cd "$(dirname "$0")/../.." || exit 1

[ -n "$1" ] || { echo "amalgamate: usage: amalgamate.sh <entry.x>" >&2; exit 1; }
[ -e "$1" ] || { echo "amalgamate: no such entry: $1" >&2; exit 1; }

awk -v entry="$1" '
# Module name -> file, the same two roots the runtime resolver uses: lib/ for
# the library, apps/ for an application tree (an app entry imports NAME/...
# through the root its own (import-path! ...) arms).
function resolve(mod,  f) {
	f = "lib/" mod ".x"
	if ((getline junk < f) >= 0) { close(f); return f }
	close(f)
	f = "apps/" mod ".x"
	if ((getline junk < f) >= 0) { close(f); return f }
	close(f)
	return ""
}
function splice(path,  line, n, mod, file) {
	if (path in seen) {
		printf "amalgamate: %s spliced twice\n", path > "/dev/stderr"
		bad = 1; exit 1
	}
	seen[path] = 1
	printf "; ---- begin %s ----\n", path
	n = 0
	while ((getline line < path) > 0) {
		n++
		if (line ~ /^[[:space:]]*;/) { print line; continue }
		# include-once splices exactly as include does, and is named here
		# explicitly: a pattern matching plain `include` alone sends every
		# include-once to the arm below, which recognises the spelling and
		# refuses it.
		#
		# The two differ in one place.  A file spliced twice is a hard error
		# for `include`, which would inline the same text twice, while for
		# include-once a repeat is the point of the form and the amalgam
		# already has the text, so it becomes a comment.  The one-shot
		# semantics survive either way: splicing is textual, and `seen`
		# guarantees a file lands once.
		if (line ~ /^\((include|include-once)[[:space:]]+"(lib|tools|apps|ext|engine)\/[^"]*"\)[[:space:]]*(;.*)?$/) {
			once = (line ~ /^\(include-once/)
			sub(/^\((include|include-once)[[:space:]]+"/, "", line)
			sub(/".*$/, "", line)
			if ((getline junk < line) < 0) {
				printf "amalgamate: %s:%d: cannot open %s\n", path, n, line > "/dev/stderr"
				bad = 1; exit 1
			}
			close(line)
			if (once && (line in seen))
				printf "; (include-once %s) -- inlined above\n", line
			else
				splice(line)
		# THE CHARACTER CLASS IS THE WHOLE MATCH.  Leaving `_` out of it silently
		# skipped x/platform/data/syscalls-x86_64 -- the one module name in the
		# boot closure that has an underscore -- so that table alone kept loading
		# from the platform while its two siblings were inlined.  A class that
		# omits a character real names use does not fail; it under-matches.
		} else if (line ~ /^\(import[[:space:]]+[a-z0-9][a-z0-9_\/@.-]*[[:space:]]*\)[[:space:]]*(;.*)?$/) {
			# A TOP-LEVEL IMPORT IS A BOOT-TIME LOAD, and an amalgam that leaves
			# it unresolved is not self-contained: it reaches into whatever
			# library the platform happens to have when it boots (#467).  Splice
			# the module here, in the position the import occupied, so load order
			# is exactly what it was.
			mod = line
			sub(/^\(import[[:space:]]+/, "", mod)
			sub(/[[:space:]]*\).*$/, "", mod)
			file = resolve(mod)
			if (file == "") {
				printf "amalgamate: %s:%d: cannot resolve (import %s)\n", path, n, mod > "/dev/stderr"
				bad = 1; exit 1
			}
			if (mod in seeded) {
				# ALREADY LOADED AT RUNTIME.  x-core.x pre-seeds the loaded set
				# with every module it raw-includes, so this import is a no-op
				# there and must stay one here: splicing it would inline a module
				# the boot already contains.  The line is kept as it stands.
				print line
			} else if (file in seen) {
				printf "; (import %s) -- inlined above\n", mod
			} else {
				# MARK IT LOADED, because `provide` does not.  provide fills the
				# EXPORTS registry; `import` consults the LOADED set, and only
				# `import` itself writes that.  Splicing the text without this
				# leaves the module inlined AND re-imported from the platform --
				# the bug wearing a bigger disguise.
				printf "(%%module-loaded! (lit %s))\n", mod
				splice(file)
			}
		} else if (line ~ /\((include|include-once|require-once)[[:space:]]+"(lib|tools|apps|ext|engine)\//) {
			printf "amalgamate: %s:%d: root-relative include not alone at column 0\n", path, n > "/dev/stderr"
			bad = 1; exit 1
		} else print line
	}
	close(path)
	printf "; ---- end %s ----\n", path
}
BEGIN {
	# THE PRE-SEEDED SET, read from the boot entry that owns it.  x-core.x marks
	# every module it raw-includes as loaded -- `include` does not register, so
	# without that a later import would reload the file mid-boot -- and
	# check-boot-order holds that invariant.  Reading the same list here is what
	# keeps this generator from splicing a module the boot already carries.
	while ((getline line < "lib/x-core.x") > 0)
		if (match(line, /\(pair \(lit [a-z0-9_\/.-]+\)/)) {
			m = substr(line, RSTART, RLENGTH)
			sub(/.*\(lit /, "", m); sub(/\).*/, "", m)
			seeded[m] = 1
		}
	close("lib/x-core.x")

	print "; GENERATED by tools/release/amalgamate.sh -- DO NOT EDIT"
	splice(entry)
	exit bad
}'
