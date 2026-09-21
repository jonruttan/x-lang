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
# The module a file is headed with, or "": its first line that is neither
# blank nor a comment, when that line is (module NAME).
function header_of(path,  line, name) {
	name = ""
	while ((getline line < path) > 0) {
		if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*;/) continue
		if (match(line, /^\(module[ \t]+[^ \t()]+\)/)) {
			name = substr(line, RSTART, RLENGTH)
			sub(/^\(module[ \t]+/, "", name)
			sub(/\)$/, "", name)
		}
		break
	}
	close(path)
	return name
}
# The module a top-level import names, or "" when the line is not one.  An
# import is bare, (import NAME), or selective, (import NAME sym (sym alias)
# ...), and sits on one line at column 0 either way.
# The character class is the whole match.  A class that omits a character
# real module names use does not fail, it under-matches: without `_`,
# x/platform/data/syscalls-x86_64 is skipped and keeps loading from the
# platform while its siblings are inlined.
function import_mod(line,  mod) {
	if (line !~ /^\(import[[:space:]]+[a-z0-9][a-z0-9_\/@.-]*([[:space:]]+([^()[:space:]]+|\([^()]*\)))*[[:space:]]*\)[[:space:]]*(;.*)?$/)
		return ""
	mod = line
	sub(/^\(import[[:space:]]+/, "", mod)
	sub(/[[:space:])].*$/, "", mod)
	return mod
}
# Whether a top-level import names exports to bind.  Such a line is kept
# where it stands once its module is spliced: the load is a no-op by then,
# since the splice marks the module loaded, and binding the names in the
# importer is the other half of what the line does.
function import_selective(line) {
	return line ~ /^\(import[[:space:]]+[^[:space:]()]+[[:space:]]+[^[:space:])]/
}
# The files a scoped file includes once or imports at top level, spliced
# ahead of it in the order they appear.  The header of a scoped module reads
# every form after it into the module, so a file spliced in place would load
# into the module instead of the root.  Spliced first, each is loaded by the
# time the module runs, and its line inside the module becomes the comment a
# repeat already becomes.
function hoist(path,  line, inc, mod, file) {
	if (path in hoisting) {
		printf "amalgamate: %s imports itself, directly or through another file\n", path > "/dev/stderr"
		bad = 1; exit 1
	}
	hoisting[path] = 1
	while ((getline line < path) > 0) {
		if (line ~ /^\(include-once[[:space:]]+"(lib|tools|apps|ext|engine)\/[^"]*"\)[[:space:]]*(;.*)?$/) {
			inc = line
			sub(/^\(include-once[[:space:]]+"/, "", inc)
			sub(/".*$/, "", inc)
			if (!(inc in seen) && (getline junk < inc) >= 0) {
				close(inc)
				splice(inc)
			}
		} else if ((mod = import_mod(line)) != "") {
			file = resolve(mod)
			if (file != "" && !(mod in seeded) && !(file in seen)) {
				printf "(%%module-loaded! (lit %s))\n", mod
				splice(file)
			}
		}
	}
	close(path)
	delete hoisting[path]
}
function splice(path,  line, n, mod, file, name) {
	# The includes and imports of a scoped file are hoisted ahead of it, so
	# the only splice that can reach here from inside one is a plain include,
	# which has no place to go: its text would load into the module.
	if (scoped != "") {
		printf "amalgamate: %s includes %s, which would splice it inside the scoped module; include it once or import it, and it is spliced ahead of the module\n", scoped, path > "/dev/stderr"
		bad = 1; exit 1
	}
	if (path in seen) {
		printf "amalgamate: %s spliced twice\n", path > "/dev/stderr"
		bad = 1; exit 1
	}
	name = header_of(path)
	if (name != "") hoist(path)
	seen[path] = 1
	printf "; ---- begin %s ----\n", path
	if (name != "") {
		printf "(%%module-expecting! (lit %s))\n", name
		scoped = path
	}
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
		} else if ((mod = import_mod(line)) != "") {
			# A top-level import is a boot-time load, and an amalgam that leaves
			# one unresolved is not self-contained: it reaches into whatever
			# library the platform has when it boots (#467).  The module is
			# spliced in the position the import occupied, so load order is
			# unchanged.  A selective import is kept after it (import_selective).
			file = resolve(mod)
			if (file == "") {
				printf "amalgamate: %s:%d: cannot resolve (import %s)\n", path, n, mod > "/dev/stderr"
				bad = 1; exit 1
			}
			if (mod in seeded) {
				# Already loaded at runtime.  x-core.x pre-seeds the loaded set
				# with every module it raw-includes, so this import is a no-op
				# there and stays one here: splicing it would inline a module
				# the boot already contains.  The line is kept as it stands.
				print line
			} else if (file in seen) {
				if (import_selective(line)) print line
				else printf "; (import %s) -- inlined above\n", mod
			} else {
				# Mark it loaded, because `provide` does not: provide fills the
				# exports registry, while `import` consults the loaded set and
				# is the only thing that writes it.  Splicing the text without
				# this leaves the module inlined and re-imported from the
				# platform.
				printf "(%%module-loaded! (lit %s))\n", mod
				splice(file)
				if (import_selective(line)) print line
			}
		} else if (line ~ /\((include|include-once|require-once)[[:space:]]+"(lib|tools|apps|ext|engine)\//) {
			printf "amalgamate: %s:%d: root-relative include not alone at column 0\n", path, n > "/dev/stderr"
			bad = 1; exit 1
		} else print line
	}
	close(path)
	if (name != "") {
		printf "(%%module-end)\n"
		scoped = ""
	}
	printf "; ---- end %s ----\n", path
}
BEGIN {
	# The pre-seeded set, read from the boot entry that owns it.  x-core.x marks
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
