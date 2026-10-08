# @no-seam-collect
<!-- A child tokenizer base, like core/sandbox.spec.md: objects reachable only
     through it are invisible to the parent's mark, so this file runs with no
     seam collects. -->
# @weight 1
# @requires native/jit

A Lexer made with every state compiled leaves its cache group a plan: for
each state, the entry its code is in and what each of its free variables is.
A later make whose group holds every entry rebuilds the states from the plan
and reads the same tokens, with no form made, printed or checked.  Each case
starts the cache in a directory of its own, so the first make is a full one
whatever an earlier run left in /tmp.

## the plan

### a second make of the same rules replays the plan and reads the same tokens

```x
(do
  (import x/reader/lexer)
  (import x/tool/asm-cache)
  (import x/type/hash)
  (def %lp-ac (fn (_ name) (eval name (module x/tool/asm-cache))))
  (def %lp-pcall (%lp-ac (lit %asm-cache-pcall)))
  (def %lp-sym (fn (_ name) ((%lp-ac (lit %asm-cache-dlsym)) (%lp-ac (lit %asm-cache-lib)) name)))
  (def %lp-dir (Str append "/tmp/lexer-plan-" ((%lp-ac (lit %asm-cache-wts)) (Sys getpid))))
  (%lp-pcall (%lp-sym "mkdir") %lp-dir 448)
  (Sys setenv "X_ASM_CACHE_DIR" %lp-dir)
  (def %lp-rules
    (list (Lexer skip " \n")
          (Lexer table (lit kw) (list "if" "else"))
          (Lexer run (lit id) "abcdefghijklmnopqrstuvwxyz" "abcdefghijklmnopqrstuvwxyz0123456789")
          (Lexer number (lit num) "uL")
          (Lexer quoted (lit str) 34 34 92)
          (Lexer until () "/*" "*/")
          (Lexer until (lit pat) "/" "/" (lit take) (lit to-end))
          (Lexer escape (lit esc) 92)
          (Lexer run (lit io) "0123456789" "0123456789" "<>")
          (Lexer table (lit op) (list "<" "<<" "<<=" "+"))
          (Lexer any (lit bad))))
  (def %lp-text "if x1 else 42u 0x1f 1.5e3 \"s\\\"q\" /* c */ /pat/ \\n 2> a<<=b + @ /open")
  (def %lp-a (Lexer make %lp-rules))
  (def %lp-b (Lexer make %lp-rules))
  (write (list (%lp-a replayed) (%lp-b replayed)
               (= (%lp-a compiled) (%lp-b compiled))
               (equal? (%lp-a read-str %lp-text) (%lp-b read-str %lp-text))))
  (newline))
```
---
    (#f #t #t #t)

### a fresh heap replays from the group file

The held entries and the groups remembered are dropped, which is what a
process that reads the group file sees.

```x
(do
  (eval '(set! %asm-cache-held ()) (module x/tool/asm-cache))
  (eval '(set! %asm-cache-groups ()) (module x/tool/asm-cache))
  (def %lp-c (Lexer make %lp-rules))
  (write (list (%lp-c replayed) (= (%lp-c compiled) (%lp-a compiled))
               (equal? (%lp-a read-str %lp-text) (%lp-c read-str %lp-text))))
  (newline))
```
---
    (#t #t #t)

### nested, word, pattern and record rules replay, their cells and buffers remade

```x
(do
  (def %lp-rules2
    (list (Lexer skip " ")
          (Lexer nested (lit dq) "\"" (lit dq)
            (list (list (lit dq) 34 92 (list (pair "$(" (lit cmd))))
                  (list (lit cmd) 41 92 (list (pair "(" (lit cmd)) (pair "\"" (lit dq)) (pair "'" (lit sq))))
                  (list (lit sq) 39 () ())))
          (Lexer pattern (lit dir) (list (list "%" 1 1) (list "-+ #0123456789." 0 ()) (list #t 1 1)))
          (Lexer word (lit word) (lit w)
            (list (list (lit w) () 92 (list (pair "'" (lit sq))))
                  (list (lit sq) 39 () ()))
            " \t\n;&|<>()")))
  (def %lp-text2 "\"a $(b \"c\" 'd') e\" %-5.2f x\\ y'z w' ; q")
  (def %lp-d (Lexer make %lp-rules2))
  (def %lp-e (Lexer make %lp-rules2))
  (def %lp-rules3 (list (Lexer record (lit rec) (list (pair "ab" (lit ((bytes 1)))) (pair "z" (lit ((units 1 32))))))))
  (def %lp-f (Lexer make %lp-rules3))
  (def %lp-g (Lexer make %lp-rules3))
  (write (list (%lp-d replayed) (%lp-e replayed)
               (equal? (%lp-d read-str %lp-text2) (%lp-e read-str %lp-text2))
               (%lp-f replayed) (%lp-g replayed)
               (equal? (%lp-f read-span "a1b2zDq" 0 7) (%lp-g read-span "a1b2zDq" 0 7))))
  (newline))
```
---
    (#f #t #t #f #t #t)

### the states a rule list makes are pinned to the plan's version

The plan is keyed by the rules and `%plan-version`, not by the states' forms:
a change to how states are made -- a form, a free variable's name or value,
a state added or dropped -- replays an old plan over new rules unless the
version moves.  This digest is of every state's key text (its identity
prefix off) and the plan, for the first rule list: when it changes, bump
`%plan-version` in lib/x/reader/lexer.x and set the new digest here.

```x
(do
  (def %lp-key (Str append "lexer:" (%number->str (Lexer %plan-version)) ":"
                 ((prim-ref (lit io) (lit write-to-str)) (pair " " %lp-rules))))
  (def %lp-held ((prim-ref (lit compile) (lit asm-cache-group)) %lp-key
                  (fn (_) ((prim-ref (lit compile) (lit asm-cache-group-held))))))
  (def %lp-id (%lp-ac (lit %asm-cache-identity)))
  (def %lp-blen (prim-ref (lit str) (lit byte-len)))
  (def %lp-bsub (prim-ref (lit str) (lit byte-sub)))
  (def %lp-strip (fn (_ s) (%lp-bsub s (%lp-blen %lp-id) (- (%lp-blen s) (%lp-blen %lp-id)))))
  (def %lp-texts ((fn (self l acc) (if (null? l) acc (self (rest l) (pair (%lp-strip (first l)) acc)))) (first %lp-held) ()))
  (Sys unsetenv "X_ASM_CACHE_DIR")
  (write (list (List length %lp-texts) (str? (rest %lp-held))
               (Hash fnv-1a (Str append (Str8 join "\n" %lp-texts) "\n" (rest %lp-held)))))
  (newline))
```
---
    (40 #t 6559654134466246748)

### the plan's text reads back as the plan, and text that is not one is no plan

The group keeps the plan as words: integers, free variables' names, and `-`
for a cell that holds nothing, each list led by its length.

```x
(do
  (import x/reader/lexer)
  (def %lp-plan (list 2 3 (list (pair 0 ()) (pair 2 (list (list "body" 0 0) (list "k" 3 -1) (list "cell" 1 0))))
                      (list () 1) (list 512) (list 1 0) (list 1)))
  (def %lp-text (Lexer %plan-text %lp-plan))
  (write (list %lp-text
               (equal? (Lexer %plan-read %lp-text) %lp-plan)
               (Lexer %plan-read "2 3 4")
               (Lexer %plan-read "(2 3)")))
  (newline))
```
---
    ("2 3 2 0 0 2 3 body 0 0 k 3 -1 cell 1 0 2 - 1 1 512 2 1 0 1 1" #t () ())
