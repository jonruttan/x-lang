# Ansi: terminal color + the REPL/help renderers
# @weight 1

## help renders the quote forms as sugar

### %code-sugar folds the reader expansions back to their shorthand

The ansi highlighter re-tokenizes doc sample strings; without this fold
'rdonly displayed as (lit rdonly) in (help File) -- the R1/R8 echo
regression jon caught at the REPL.

```x
(do (import x/repl/ansi)
  (let ((sugar (eval (lit %code-sugar) (module x/repl/ansi))))
    (list (sugar '(lit x)) (sugar (list 'quasi 'x))
          (sugar (list 'unquote 'x)) (sugar (list 'unquote-splicing 'x))
          (null? (sugar '(lit x y))) (null? (sugar '(f x))))))
```
---
    ("'" "`" "," ",@" #t #t)
