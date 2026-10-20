# jit-group
# @weight 15
# @timeout-scale 4

A compiled engine's functions as one cache group (x/tool/jit-group): the
first build under a key generates, compiles and proves; a later one under
the same key pours the functions from the group's plan and runs no proof.
A group the heap already holds is not read again, so a second call in one
process replays, and the two paths show in one case.  The keys carry the
process id, so a run never meets a group an earlier run stored.  The file
compiles, so it carries an engine's weight.

## the two paths

### a fresh group generates and proves; the same key then replays

```x
(do
  (import x/tool/jit-group jit-group)
  (import x/sys/posix)
  (def %jg-key (Str8 append "jit-group-spec:" (%number->str (Sys getpid))))
  (def %jg-trace (pair () ()))
  (def %jg-note (fn (_ what) (%set-first! %jg-trace (pair what (first %jg-trace)))))
  (def %jg-gen (fn (_) (%jg-note (lit gen)) (list (lit (fn (_ a b) (+ a b))) (lit (fn (_ a b) (* a b))))))
  (def %jg-use
    (fn (_ fns replayed?)
      (%jg-note (if replayed? (lit replay) (lit fresh)))
      (list ((first fns) 3 4) ((first (rest fns)) 3 4))))
  (def %jg-a (jit-group %jg-key %jg-gen %jg-use))
  (def %jg-b (jit-group %jg-key %jg-gen %jg-use))
  (write (list %jg-a %jg-b (List reverse (first %jg-trace)))))
```
---
    ((7 12) (7 12) ('gen 'fresh 'replay))

### a proof that fails leaves no plan: the next build generates again

```x
(do
  (import x/tool/jit-group jit-group)
  (import x/sys/posix)
  (def %jf-key (Str8 append "jit-group-spec-fail:" (%number->str (Sys getpid))))
  (def %jf-trace (pair () ()))
  (def %jf-note (fn (_ what) (%set-first! %jf-trace (pair what (first %jf-trace)))))
  (def %jf-gen (fn (_) (%jf-note (lit gen)) (list (lit (fn (_ a) (- a 1))))))
  (def %jf-fail (fn (_ fns replayed?) (%jf-note (lit fresh)) (Err raise (lit state) "disagrees" ())))
  (def %jf-ok (fn (_ fns replayed?) (%jf-note (if replayed? (lit replay) (lit fresh))) ((first fns) 10)))
  (def %jf-first (guard (e (e msg)) (jit-group %jf-key %jf-gen %jf-fail)))
  (def %jf-second (jit-group %jf-key %jf-gen %jf-ok))
  (write (list %jf-first %jf-second (List reverse (first %jf-trace)))))
```
---
    ("disagrees" 9 ('gen 'fresh 'gen 'fresh))
