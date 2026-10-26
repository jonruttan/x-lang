# Ansi: terminal color + the REPL/help renderers
# @weight 1

## help renders code as written

### Ansi highlight writes (Syntax x)'s colours over the example's own bytes

help's examples go through `Ansi highlight`. It colours the text lexically,
so a quote form shows as the author wrote it: `'rdonly`, never the reader's
`(lit rdonly)`. Colour is forced on and the output read back through a pipe.

```x
(do (import x/repl/ansi) (import x/sys/posix) (import x/tool/syntax)
  (let ((was (Ansi enabled?)) (fds (Sys pipe)) (code "(open 'rdonly `(a ,b))"))
    (eval (lit (set! %ansi? #t)) (module x/repl/ansi))
    (Stream with-fd (rest fds) (fn (_) (Ansi highlight code)))
    (Sys close (rest fds))
    (let ((out (bytes->str (Sys fd-read (first fds) 4096))))
      (Sys close (first fds))
      (let ((want (Syntax ansi code ((Syntax x) spans code) 0 (Str8 length code))))
        (eval (list (lit set!) (lit %ansi?) was) (module x/repl/ansi))
        (list (Str8 =? out want) (null? (Str8 index-of "lit" out))
              (not (null? (Str8 index-of "'rdonly" out))))))))
```
---
    (#t #t #t)
