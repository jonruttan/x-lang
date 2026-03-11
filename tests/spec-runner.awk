#!/usr/bin/awk -f
# # Computational Expressions in C
#
# ## tests/spec-runner.awk -- AWK Test Runner
#
# @description State machine test runner for .spec format
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

BEGIN {
	state = 0
	tests = 0; fails = 0; pending = 0
	unit = ""; tname = ""; input_buf = ""; expect_buf = ""
	lib = LANG_LIB
	unit_hdr = ""
	tmpfile = TMPDIR "/spec-" SPEC_ID ".tmp"

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

function flush(    cmd, line, output) {
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

	# Write input to temp file
	printf "%s\n", input_buf > tmpfile
	close(tmpfile)

	# Run interpreter and capture output
	cmd = "cat " q(lib) " " q(tmpfile) " | " q(X_BIN) " 2>/dev/null"
	output = ""
	while ((cmd | getline line) > 0) {
		# Strip REPL prompts (> and $ prefixes, looping)
		while (substr(line, 1, 2) == "> " || substr(line, 1, 2) == "$ ")
			line = substr(line, 3)
		if (line != "") output = line
	}
	close(cmd)

	if (output == expect_buf) {
		printf "%s%s.%s", unit_hdr, GREEN, RESET
	} else {
		fails++
		printf "%s\n%sFAIL: %s: %s\n  expected: %s\n  got:      %s%s\n", \
			unit_hdr, RED, unit, tname, expect_buf, output, RESET
	}

	unit_hdr = ""
	tname = ""; input_buf = ""; expect_buf = ""
	state = 0
}

# Comments and metadata (only in IDLE state)
state == 0 && /^# @lib / {
	lib = lib_base "/" substr($0, 8)
	next
}
state == 0 && /^#/ { next }

# Unit header
/^== / {
	flush()
	unit = substr($0, 4)
	unit_hdr = sprintf("\n%s%s%s\n", BLUE, unit, RESET)
	next
}

# Test header
/^-- / {
	flush()
	tname = substr($0, 4)
	state = 1
	input_buf = ""
	expect_buf = ""
	next
}

# Input/expect separator
/^---$/ {
	state = 2
	next
}

# Blank lines end the current test section
/^$/ {
	if (state == 2) { flush() }
	next
}

# Collect input lines
state == 1 {
	if (input_buf == "") input_buf = $0
	else input_buf = input_buf "\n" $0
	next
}

# Collect expected output lines
state == 2 {
	if (expect_buf == "") expect_buf = $0
	else expect_buf = expect_buf "\n" $0
	next
}

END {
	flush()

	# Write counts to temp file for aggregation
	countfile = TMPDIR "/spec-" SPEC_ID ".cnt"
	printf "%d %d %d\n", tests, fails, pending > countfile
	close(countfile)
}
