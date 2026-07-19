# Ansi: terminal color + the REPL/help renderers

## help renders the quote family as sugar

### %code-sugar folds the reader expansions back to their shorthand

The ansi highlighter re-tokenizes doc sample strings; without this fold
'rdonly displayed as (lit rdonly) in (help File) -- the R1/R8 echo
regression jon caught at the REPL.

```scheme
(do (import x/repl/ansi)
  (list (%code-sugar '(lit x)) (%code-sugar (list 'quasi 'x))
        (%code-sugar (list 'unquote 'x)) (%code-sugar (list 'unquote-splicing 'x))
        (null? (%code-sugar '(lit x y))) (null? (%code-sugar '(f x)))))
```
---
    ("'" "`" "," ",@" #t #t)
