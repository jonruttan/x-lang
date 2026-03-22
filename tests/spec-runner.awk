#!/usr/bin/awk -f
# # Computational Expressions in C
#
# ## tests/spec-runner.awk -- AWK Test Runner
#
# @description Batched test runner for .spec.md format
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2024 Jon Ruttan
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
#   MAX_TEST_SECS -- per-test time limit (default 10, 0=disable)
#   SLOW_STREAK   -- consecutive slow-test limit (default 5, 0=disable)
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
	read_fn = READ_FN ? READ_FN : "read"
	unit_hdr = ""
	tmpfile = TMPDIR "/spec-" SPEC_ID ".tmp"
	tc = 0

	# Derive lib_base directory from LANG_LIB
	n = split(LANG_LIB, _parts, "/")
	lib_base = ""
	for (i = 1; i < n; i++) {
		if (i > 1) lib_base = lib_base "/"
		lib_base = lib_base _parts[i]
	}

	RED = "\033[1;31m"; GREEN = "\033[1;32m"
	BLUE = "\033[1;34m"; RESET = "\033[0m"

	# Regression detection defaults
	max_test_secs = (MAX_TEST_SECS != "") ? MAX_TEST_SECS + 0 : 10
	slow_streak_limit = (SLOW_STREAK != "") ? SLOW_STREAK + 0 : 5
	slow_streak = 0
	completed = 0
}

function now() { srand(); return srand() }
# Timing uses interpreter (clock) primitive via <<SEP:us>> markers

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

function abort_regression(reason) {
	printf "\n\n%s*** SPEED REGRESSION: %s ***%s\n", RED, reason, RESET
	printf "Aborting -- %d of %d tests completed before regression detected.\n", \
		completed, tests
	# Write counts so shell wrapper doesn't error on missing file
	countfile = TMPDIR "/spec-" SPEC_ID ".cnt"
	printf "%d %d %d\n", tests, fails + (tests - completed), pending > countfile
	close(countfile)
	exit 1
}

function check_regression(dt_ms, tidx,    dt_s) {
	completed++
	dt_s = int(dt_ms / 1000)
	if (dt_s > 0) {
		slow_streak++
		if (max_test_secs > 0 && dt_s > max_test_secs)
			abort_regression(sprintf("test \"%s\" took %ds (limit: %ds)", \
				t_name[tidx], dt_s, max_test_secs))
		if (slow_streak_limit > 0 && slow_streak >= slow_streak_limit)
			abort_regression(sprintf("%d consecutive tests took >=1s each", \
				slow_streak))
	} else {
		slow_streak = 0
	}
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

	unit_hdr = ""
	tname = ""; input_buf = ""; expect_buf = ""
	state = 0
}

function run_batch(from, to, blib,    i, cmd, line, tidx, output) {
	if (repl_cmd == " ") {
		# Direct mode: feed tests to the personality REPL without
		# %T harness or (begin ...) wrapper.  Used by Sweet where
		# indentation-based grouping must see raw newlines/tokens.
		# Each separator on its own line so sweet-read doesn't group them.
		printf "" > tmpfile
		for (i = from; i <= to; i++) {
			if (i > from) {
				printf "(heap-collect)\n" > tmpfile
				printf "(%%profile-dump)\n" > tmpfile
				printf "(display \"<<SEP>>\\n\")\n" > tmpfile
			}
			printf "%s\n", t_input[i] > tmpfile
		}
		close(tmpfile)
	} else {
		# Standard mode: %T harness with (begin ...) wrapping.
		printf "(def %%T (op () %%E (def %%r (%s)) (if (eq? %%r (lit %%END%%)) () (%%seq (guard (err (display \"Error: \") (display err) (newline)) (%%repl-print (eval %%r %%E))) (%%T)))))\n", read_fn > tmpfile
		printf "%s\n", "(%T)" > tmpfile
		for (i = from; i <= to; i++) {
			if (i > from)
				printf "(%%profile-dump) (display \"<<SEP>>\\n\")\n" > tmpfile
			printf "(begin %s)\n", t_input[i] > tmpfile
		}
		printf "(display \"<<SEP>>\\n\")\n" > tmpfile
		printf "%s\n", "%END%" > tmpfile
		close(tmpfile)
	}

	# Run single interpreter invocation (no REPL needed)
	# TIMEOUT_CMD (e.g. "timeout 30") prevents runaway tests from OOM-killing.
	timeout_pfx = (TIMEOUT_CMD != "") ? TIMEOUT_CMD " " : ""
	cmd = "{ cat " q(blib) "; cat " q(tmpfile) "; } | " timeout_pfx q(X_BIN) " 2>/dev/null"

	tidx = from
	output = ""
	load_time_ms = 0
	while ((cmd | getline line) > 0) {
		# Strip REPL prompts (> and $ prefixes, looping)
		while (substr(line, 1, 2) == "> " || substr(line, 1, 2) == "$ ")
			line = substr(line, 3)
		if (line == "<<SEP>>") {
			dt_ms = 0
			dt = int(dt_ms / 1000)
			t_time_ms[tidx] = dt_ms
			if (output == t_expect[tidx]) {
				if (dt > 0)
					printf "%s%s.%s(%ds)", t_unit_hdr[tidx], GREEN, RESET, dt
				else
					printf "%s%s.%s", t_unit_hdr[tidx], GREEN, RESET
			} else {
				fails++
				printf "%s\n%sFAIL: %s: %s\n  expected: %s\n  got:      %s%s", \
					t_unit_hdr[tidx], RED, t_unit[tidx], t_name[tidx], \
					t_expect[tidx], output, RESET
				if (dt > 0) printf "(%ds)", dt
				printf "\n"
			}
			check_regression(dt_ms, tidx)
			tidx++
			output = ""
		} else if (line != "") {
			output = line
		}
	}
	close(cmd)

	# Safety fallback: final test without separator (shouldn't happen)
	if (tidx <= to) {
		dt_ms = 0
		dt = 0
		t_time_ms[tidx] = dt_ms
		if (output == t_expect[tidx]) {
			if (dt > 0)
				printf "%s%s.%s(%ds)", t_unit_hdr[tidx], GREEN, RESET, dt
			else
				printf "%s%s.%s", t_unit_hdr[tidx], GREEN, RESET
		} else {
			fails++
			printf "%s\n%sFAIL: %s: %s\n  expected: %s\n  got:      %s%s", \
				t_unit_hdr[tidx], RED, t_unit[tidx], t_name[tidx], \
				t_expect[tidx], output, RESET
			if (dt > 0) printf "(%ds)", dt
			printf "\n"
		}
		check_regression(dt_ms, tidx)
	}

	# Record load time for this batch
	batch_load_ms = load_time_ms
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

	# Write timing data: load_ms then per-test ms
	timefile = TMPDIR "/spec-" SPEC_ID ".time"
	printf "load %d\n", batch_load_ms > timefile
	for (i = 1; i <= tc; i++) {
		printf "%s\t%s\t%d\n", t_unit[i], t_name[i], t_time_ms[i] > timefile
	}
	close(timefile)
}
