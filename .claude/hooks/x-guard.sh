#!/bin/sh
# PreToolUse guard: block raw x-bin engine invocations (unbounded RAM).
#
# The engine, run bare, has no allocation ceiling: a runaway program takes
# the whole machine down (9 documented OOM incidents).  The SAFE routes arm
# limits before any user code runs:
#   ./x.sh                   the wrapper: pipes the library onto stdin,
#                            which arms conservative allocation limits
#   tests/x/spec-runner.sh   arms X_ALLOC_LIMIT_OBJS per spec
#
# Matching is anchored on the COMMAND POSITION -- line start or after
# | ; & ` ( plus leading VAR=val assignments, plus the usual prefix
# commands (time/timeout/env/nice/...).  The engine name as an ARGUMENT
# (a grep pattern, an ls target, a commit message) is not an invocation
# and passes.  The predecessor guard matched the bare token `x` anywhere
# in the command text and misfired constantly, and its *spec-runner.sh*
# substring allowlist bypassed it entirely; `x-bin` appears nowhere else
# in the repo, so the two anchored patterns below are the whole rule --
# no allowlist.
c=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$c" ] && exit 0

# A backslash-newline continues the SAME command, so join those lines first.
# The quote-stripping below is per line (sed), and a quoted span that crosses
# a continuation was invisible to it: an ssh payload spread over three lines
# for readability had its interior read as host commands and was denied --
# the same text on one line passed.  Genuine newlines are left alone: they
# separate commands, and an engine name starting its own line must still
# match.
c=$(printf '%s\n' "$c" | sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba' -e '}')

# Quoted spans are argument DATA (sed programs, grep patterns, commit
# messages) -- text inside them cannot start a command, so strip them
# before matching.  An engine path deliberately spelled in quotes to
# dodge the guard is evasion, which a text-level guard cannot police and
# this one does not try to.
c=$(printf '%s' "$c" | sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g")

# Engine names: x-bin + its variants, bare or path'd.  The pre-rename
# VARIANT names stay, path'd only, for stale binaries in checkouts built
# before the rename (a bare pre-rename `x` is the installed WRAPPER --
# safe -- and matching plain /x is what made the old guard misfire, so
# neither is matched).  [^[:space:]=] in the path part keeps an env
# assignment's VALUE (X_BIN=./x-bin-asan sh ...) from reading as an
# invocation.
E='(([^[:space:]=]*/)?x-bin(-debug|-profile|-asan|-cov)?|[^[:space:]=]*/x-(debug|profile|asan|dbg|cov))'
T='([[:space:]<>;&)|]|$)'
P='(^|[|;&`(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
W='([^[:space:]=]*/)?(time|timeout|rlwrap|env|nice|gdb|lldb|valgrind|strace|ltrace)([[:space:]][^|;&()]*)?[[:space:]]'

if printf '%s' "$c" | grep -qE "$P$E$T" \
	|| printf '%s' "$c" | grep -qE "$P$W$E$T"; then
	printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: raw x-bin engine invocation (unconfigured it has no allocation ceiling; 9 documented OOM incidents). Use ./x.sh instead -- the wrapper pipes the library onto stdin, which arms conservative allocation limits -- or tests/x/spec-runner.sh (arms X_ALLOC_LIMIT_OBJS), or hand the command to the user."}}'
fi
exit 0
