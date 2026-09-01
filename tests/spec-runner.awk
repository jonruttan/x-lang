#!/usr/bin/awk -f
# # Computational Expressions in C
#
# ## tests/spec-runner.awk -- AWK Test Runner
#
# @description Batched test runner for .spec.md format
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# Variables (passed via -v):
#   X_BIN    -- path to interpreter binary
#   LANG_LIB -- default library file path
#   TMPDIR   -- temp directory for scratch files
#   SPEC_ID  -- unique integer for temp file namespacing
#
# Tests are collected during parsing, then run in a single interpreter
# invocation per library group (@lib changes split a group).  The runner
# accepts MULTIPLE spec files in one invocation (#319): the shell buckets
# same-@lib files together so one library boot serves the whole bucket --
# the boot (~0.7s for x-core) was ~61% of the suite when every file paid
# it alone.  `lib` deliberately persists across file boundaries, which is
# only sound because the shell never mixes libs in a bucket.
# A separator expression between tests delimits output sections.

BEGIN {
	state = 0
	fenced = 0
	tests = 0; fails = 0; pending = 0
	unit = ""; tname = ""; input_buf = ""; expect_buf = ""
	lib = LANG_LIB
	repl_cmd = REPL_CMD ? REPL_CMD : "(repl)"
	read_fn = READ_FN ? READ_FN : "Io read"
	unit_hdr = ""
	tmpfile = TMPDIR "/spec-" SPEC_ID ".tmp"
	tc = 0
	# Per-test opt-in: set when the expected block is fenced as ```output,
	# meaning "compare the FULL multi-line output", not just the last line.
	expect_full = 0

	# Derive lib_base directory from LANG_LIB
	n = split(LANG_LIB, _parts, "/")
	lib_base = ""
	for (i = 1; i < n; i++) {
		if (i > 1) lib_base = lib_base "/"
		lib_base = lib_base _parts[i]
	}

	RED = "\033[1;31m"; GREEN = "\033[1;32m"
	BLUE = "\033[1;34m"; RESET = "\033[0m"
}

function q(s,    _s) {
	_s = s
	gsub(/'/, "'\\''", _s)
	return "'" _s "'"
}

function strip(s) {
	if (substr(s, 1, 4) == "    ") return substr(s, 5)
	if (substr(s, 1, 1) == "\t") return substr(s, 2)
	return s
}

# Drop trailing newlines. Used only in full-output (```output) mode so a
# result's trailing newline (every %repl-print emits one) does not cause a
# spurious mismatch against the author's expected block.
function rtrim_blank(s) {
	while (length(s) > 0 && substr(s, length(s), 1) == "\n")
		s = substr(s, 1, length(s) - 1)
	return s
}

function collect() {
	if (tname == "") return

	tests++

	if (state < 2) {
		# Never saw --- separator: pending test
		pending++
		printf "%s%sp%s", unit_hdr, BLUE, RESET
		unit_hdr = ""
		tname = ""; input_buf = ""; expect_buf = ""
		expect_full = 0
		state = 0
		return
	}

	# Store test for batch execution
	tc++
	t_input[tc] = input_buf
	t_expect[tc] = expect_buf
	t_name[tc] = tname
	t_unit[tc] = unit
	t_unit_hdr[tc] = unit_hdr
	t_lib[tc] = lib
	t_full[tc] = expect_full

	unit_hdr = ""
	tname = ""; input_buf = ""; expect_buf = ""
	expect_full = 0
	state = 0
}

function run_batch(from, to, blib,    i, cmd, line, tidx, output, cmd_status, got, boundary_done, seen, want, _tn, _tp) {
	if (repl_cmd == " ") {
		# Direct mode: feed tests to the lang REPL without
		# %T harness or (begin ...) wrapper.  Used by Sweet where
		# indentation-based grouping must see raw newlines/tokens.
		# Each separator on its own line so sweet-read doesn't group them.
		printf "" > tmpfile
		for (i = from; i <= to; i++) {
			if (i > from) {
				# heap-collect = real GC between snippets (OOM guard).
				# No per-snippet heap dump here: a heap-count is an O(heap)
				# chain walk (~1.9s/call on the numeric-tower heap) whose
				# output went to discarded stderr -- pure waste.
				printf "(heap-collect)\n" > tmpfile
				printf "(display \"<<SEP>>\\n\")\n" > tmpfile
			}
			printf "%s\n", t_input[i] > tmpfile
		}
		close(tmpfile)
	} else {
		# Standard mode: %T harness with (begin ...) wrapping.
		# Snippets eval via eval! (current-env, REPL/standalone semantics),
		# NOT two-arg (eval %r %E): the latter's save/restore reverts the
		# global BST after each snippet, discarding top-level defs -- so a
		# self-referential def (e.g. a type whose converter calls
		# (make-instance %t)) can't resolve %t.  eval! is TCO-capable, so
		# deep tail-recursion specs still pass.
		printf "(def %%T (op () %%E (def %%r (%s)) (if (eq? %%r (lit %%END%%)) () (%%seq (guard (err (display \"Error: \") (display err) (newline)) (%%repl-print (eval! %%r))) (%%T)))))\n", read_fn > tmpfile
		printf "%s\n", "(%T)" > tmpfile
		for (i = from; i <= to; i++) {
			# A COLLECT AT EVERY SNIPPET SEAM.  With no auto-GC a batch
			# used to accumulate every snippet's garbage until the
			# process exited, so the alloc ceiling had to clear a whole
			# BATCH's sum; the seam collect reclaims each snippet's
			# garbage as it finishes, and the ceiling now covers one
			# snippet's peak (the bundles re-measured 250-275M down to
			# 75-150M -- see spec-runner.sh's calibration).
			#
			# This was long refused by a note citing the #283/#299
			# rooting family for "40 spec failures".  The bisect
			# (2026-08-31) split that into TWO families, and the old
			# note had one of them right:
			#
			#   - the meta-width specs (meta/base-paths, meta/
			#     obj-layout) changed obj-meta-extra over a live heap,
			#     so the collect freed their objects at the wrong
			#     width (the x-engine-c#21 ruling: the width is
			#     boot-time policy).  FIXED: both now test against the
			#     ambient width.  A future spec that diverges aborts
			#     its own batch at the next seam -- the policy
			#     enforced loudly; see reflect.x's meta-count! note.
			#
			#   - the #283 family is REAL and remains: objects
			#     reachable only through C-held state (sigint's
			#     handler cells, a child base's internals) are
			#     invisible to the mark, so a collect frees them live.
			#     Linux segfaults; macOS's allocator TOLERATES the bad
			#     free, which is exactly how a macOS bisect missed it
			#     and why "it passes on my machine" is not evidence
			#     here.  Those files (core/sandbox, core/signal,
			#     applicative/gc-hooks) carry the directive below
			#     until the rooting hole closes engine-side.  A lang
			#     bundle whose EVAL DOOR holds such state (x-python's
			#     python-run builds an isolated tokenizer base) turns
			#     the whole run off with SPEC_SEAM_COLLECT=0 in its
			#     wrapper -- proven by exactly the works-twice,
			#     dies-third shape in its conformance cases.
			#
			# Still no per-snippet heap dump: a heap-count is an
			# O(heap) chain walk whose output went to discarded stderr
			# -- ~120s of pure waste per heavy-lib spec.
			# A file may declare `# @no-seam-collect`, for either
			# reason above: its SUBJECT is the divergent-width
			# mechanism (cov/meta), or it holds objects only C-side
			# state can reach (#283 family).  The classifier makes
			# such a file run alone, so the opt-out never strips
			# collects from an innocent bucket-mate.
			if (i > from) {
				if (!noseam && SEAM_COLLECT != "0")
					printf "((prim-ref (lit heap) (lit collect)))\n" > tmpfile
				printf "(display \"<<SEP>>\\n\")\n" > tmpfile
			}
			# The closing paren sits on its OWN line: a test whose last
			# line ends in a `;` comment would otherwise swallow it,
			# leaving an unterminated (begin that eats the <<SEP>>
			# markers after it -- the test "vanishes" with no crash.
			# Comments are legal x-lang, so the harness must be robust
			# to them anywhere in the snippet (found via spec.md's own
			# Comments example, #70 seam 2).
			printf "(begin %s\n)\n", t_input[i] > tmpfile
		}
		printf "(display \"<<SEP>>\\n\")\n" > tmpfile
		printf "%s\n", "%END%" > tmpfile
		close(tmpfile)
	}

	# Run single interpreter invocation (no REPL needed)
	# TIMEOUT_CMD (e.g. "timeout 30") prevents runaway tests from OOM-killing.
	timeout_pfx = (TIMEOUT_CMD != "") ? TIMEOUT_CMD " " : ""
	# Arm the interpreter's runaway-memory guard before the library loads (the
	# interpreter reads no environment -- no stdlib).  The pipeline's shell
	# expands $X_ALLOC_LIMIT_OBJS (exported by spec-runner.sh; 0/unset disables).
	# Keep the interpreter's stderr in a file instead of discarding it: a
	# batch that dies during the @lib BOOT often died of a perfectly clean,
	# well-worded raise -- "compile: cc failed with status 1" was the live
	# case, an engine whose sandbox could not shell out to cc -- and with
	# stderr on /dev/null that surfaced as an unexplained "died mid-batch"
	# on every test, misread as lib rot by two independent investigations
	# before the message was found in the discard.  The file is read ONLY
	# when a death message is being built; a green batch never opens it.
	errfile = TMPDIR "/spec-" SPEC_ID ".err"
	cmd = "{ echo \"(alloc-limit! ${X_ALLOC_LIMIT_OBJS:-0})\"; cat " q(blib) "; cat " q(tmpfile) "; } | " timeout_pfx q(X_BIN) " 2>" q(errfile)

	tidx = from
	output = ""
	seen = 0
	while ((cmd | getline line) > 0) {
		# Strip REPL prompts (> and $ prefixes, looping)
		while (substr(line, 1, 2) == "> " || substr(line, 1, 2) == "$ ")
			line = substr(line, 3)
		if (line == "<<SEP>>") {
			# Full mode compares all captured lines (blanks preserved, trailing
			# newline trimmed); default mode compares only the last line.
			got = t_full[tidx] ? rtrim_blank(output) : output
			want = t_full[tidx] ? rtrim_blank(t_expect[tidx]) : t_expect[tidx]
			if (got == want) {
				printf "%s%s.%s", t_unit_hdr[tidx], GREEN, RESET
			} else {
				fails++
				printf "%s\n%sFAIL: %s: %s\n  expected: %s\n  got:      %s%s\n", \
					t_unit_hdr[tidx], RED, t_unit[tidx], t_name[tidx], \
					want, got, RESET
			}
			tidx++
			output = ""
			seen = 0
		} else if (t_full[tidx]) {
			# Capture from the first non-blank line onward, preserving interior
			# blanks. Leading blanks are skipped: the harness emits a blank line
			# after each <<SEP>> (the repl-print newline of the separator form),
			# so a test's captured output would otherwise start with one.
			if (seen || line != "") {
				output = seen ? output "\n" line : line
				seen = 1
			}
		} else if (line != "") {
			output = line
		}
	}
	cmd_status = close(cmd)

	# Account for tests with no <<SEP>> separator of their own.  Standard mode
	# emits a trailing separator after the last test, so a healthy run leaves
	# tidx == to+1 and this loop never runs.  Direct mode (Sweet) emits no
	# trailing separator, so its final test legitimately ends at EOF and is
	# COMPARED here (the first, "boundary" iteration).  Anything past that first
	# test is the interpreter dying mid-batch (segfault / timeout-kill / OOM):
	# those tests produced no result, and a missing result is a FAILURE, never a
	# silent pass -- surfacing it is the whole point of the harness.  (Before:
	# only the boundary test was handled and the rest of the batch was dropped
	# from the counts, so a crash made the tail of a spec file read as passing.
	# cmd_status is the pipeline exit code where the awk reports it -- 0 on the
	# one-true-awk, the real code on gawk/mawk.)
	boundary_done = 0
	while (tidx <= to) {
		got = t_full[tidx] ? rtrim_blank(output) : output
		want = t_full[tidx] ? rtrim_blank(t_expect[tidx]) : t_expect[tidx]
		if (!boundary_done && got == want) {
			printf "%s%s.%s", t_unit_hdr[tidx], GREEN, RESET
		} else {
			fails++
			if (!boundary_done && got != "") {
				# boundary test interrupted -- got already holds the partial output
			} else {
				got = "<no result -- interpreter died mid-batch"
				if (cmd_status > 0) got = got " (exit " cmd_status ")"
				# The engine's last words, if it had any: the tail of
				# the captured stderr names the actual cause (a load-
				# time raise, a guard trip) where the exit code alone
				# reads as a mystery.
				_lw = ""
				while ((getline _el < errfile) > 0)
					if (_el != "") _lw = _el
				close(errfile)
				if (_lw != "") got = got " -- engine stderr: " _lw
				# Name the wall-clock budget: a timeout kill produces exactly
				# this shape, and on the one-true-awk close() returns 0, so the
				# exit suffix never identifies it there -- a load-induced 60s
				# kill once read as a mystery one-off crash (the doctest-
				# variance investigation, 2026-08-02).
				if (TIMEOUT_CMD != "") {
					_tn = split(TIMEOUT_CMD, _tp, " ")
					got = got " (crash, OOM, or the " _tp[_tn] "s timeout)"
				}
				got = got ">"
			}
			printf "%s\n%sFAIL: %s: %s\n  expected: %s\n  got:      %s%s\n", \
				t_unit_hdr[tidx], RED, t_unit[tidx], t_name[tidx], \
				want, got, RESET
		}
		boundary_done = 1
		tidx++
	}
}

function batch_run(    i, batch_start, cur_lib) {
	if (tc == 0) return

	batch_start = 1
	cur_lib = t_lib[1]

	for (i = 2; i <= tc; i++) {
		if (t_lib[i] != cur_lib) {
			run_batch(batch_start, i - 1, cur_lib)
			batch_start = i
			cur_lib = t_lib[i]
		}
	}
	run_batch(batch_start, tc, cur_lib)
}

# Expected output fenced as ```output -> compare the FULL multi-line output for
# this test (opt-in). Must precede the generic fence rule below. The default
# (indented expected, or a plain ``` fence) stays last-line-only, so every
# existing spec is unaffected.
state == 2 && /^```output/ {
	fenced = 1
	expect_full = 1
	next
}

# Fenced code blocks (``` with optional language tag)
/^```/ {
	if (fenced) { fenced = 0; next }
	if (state == 1 || state == 2) { fenced = 1 }
	next
}

# Fenced content: collect literally, skip all other rules
fenced == 1 && state == 1 {
	if (input_buf == "") input_buf = $0
	else input_buf = input_buf "\n" $0
	next
}
fenced == 1 && state == 2 {
	if (expect_buf == "") expect_buf = $0
	else expect_buf = expect_buf "\n" $0
	next
}
fenced == 1 { next }

# Unit header (## heading)
/^## / {
	collect()
	unit = substr($0, 4)
	unit_hdr = sprintf("\n%s%s%s\n", BLUE, unit, RESET)
	next
}

# Test header (### heading)
/^### / {
	collect()
	tname = substr($0, 5)
	state = 1
	input_buf = ""
	expect_buf = ""
	next
}

# Comments and metadata (only in IDLE state)
state == 0 && /^# @no-seam-collect/ { noseam = 1 }

state == 0 && /^# @lib / {
	lib = lib_base "/" substr($0, 8)
	next
}
state == 0 && /^#/ { next }

# Input/expect separator (only in INPUT state)
state == 1 && /^---$/ {
	state = 2
	next
}

# Blank lines end the current test section
/^$/ {
	if (state == 2) { collect() }
	next
}

# Collect indented input lines (4-space or tab prefix required)
state == 1 && /^    / {
	if (input_buf == "") input_buf = strip($0)
	else input_buf = input_buf "\n" strip($0)
	next
}
state == 1 && /^\t/ {
	if (input_buf == "") input_buf = strip($0)
	else input_buf = input_buf "\n" strip($0)
	next
}

# Collect indented expected output lines (4-space or tab prefix required)
state == 2 && /^    / {
	if (expect_buf == "") expect_buf = strip($0)
	else expect_buf = expect_buf "\n" strip($0)
	next
}
state == 2 && /^\t/ {
	if (expect_buf == "") expect_buf = strip($0)
	else expect_buf = expect_buf "\n" strip($0)
	next
}

END {
	collect()
	batch_run()

	# Write counts to temp file for aggregation
	countfile = TMPDIR "/spec-" SPEC_ID ".cnt"
	printf "%d %d %d\n", tests, fails, pending > countfile
	close(countfile)
}
