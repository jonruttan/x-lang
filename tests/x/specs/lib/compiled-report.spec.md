# @weight 1

A failed compile in `lib/x/tool/compiled.x` is quiet unless the process
environment sets `X_COMPILED_REPORT`; with it set, a line naming the entry
and the reason goes to stderr.  Each case points stderr at stdout first, so
the comparison sees what reached it.

## X_COMPILED_REPORT

### unset, a failed compile writes nothing

```x
(import x/tool/compiled)
(Sys unsetenv "X_COMPILED_REPORT")
(Sys dup2 1 2)
(write ((new Compiled name 'probe interpreted first
             compile (fn (_) (Err raise 'value "no compiler here" ()))
             install (fn (_ v) v))
        compile!))
```
---
    'failed

### set, a failed compile names the entry and the reason

```x
(import x/tool/compiled)
(Sys setenv "X_COMPILED_REPORT" "1")
(Sys dup2 1 2)
(write ((new Compiled name 'probe interpreted first
             compile (fn (_) (Err raise 'value "no compiler here" ()))
             install (fn (_ v) v))
        compile!))
```
---
```output
compiled: probe failed: value: no compiler here
'failed
```

### set, a compile that declines writes nothing

```x
(import x/tool/compiled)
(Sys setenv "X_COMPILED_REPORT" "1")
(Sys dup2 1 2)
(write ((new Compiled name 'probe interpreted first
             compile (fn (_) first)
             install (fn (_ v) v))
        compile!))
```
---
    'interpreted
