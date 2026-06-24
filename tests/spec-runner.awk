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
# invocation per spec file (or per library group if @lib changes).
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

function run_batch(from, to, blib,    i, cmd, line, tidx, output, cmd_status, got, boundary_done, seen, want) {
	if (repl_cmd == " ") {
		# Direct mode: feed tests to the personality REPL without
		# %T harness or (begin ...) wrapper.  Used by Sweet where
		# indentation-based grouping must see raw newlines/tokens.
		# Each separator on its own line so sweet-read doesn't group them.
		printf "" > tmpfile
		for (i = from; i <= to; i++) {
			if (i > from) {
				# heap-collect = real GC between snippets (OOM guard).
				# No (%profile-dump) here: its heap-count is an O(heap)
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
			# Inter-snippet separator only.  No (%profile-dump): its
			# heap-count is an O(heap) chain walk (~1.9s/call on the
			# numeric-tower heap) whose output went to discarded stderr
			# -- ~120s of pure waste per heavy-lib (x-base/complex/...) spec.
			if (i > from)
				printf "(display \"<<SEP>>\\n\")\n" > tmpfile
			printf "(begin %s)\n", t_input[i] > tmpfile
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
	cmd = "{ echo \"(alloc-limit! ${X_ALLOC_LIMIT_OBJS:-0})\"; cat " q(blib) "; cat " q(tmpfile) "; } | " timeout_pfx q(X_BIN) " 2>/dev/null"

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
