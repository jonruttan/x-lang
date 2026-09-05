# img.x smoke (dialect entry points)

End-to-end smoke of the state-image loader's dialect (#70 family; the story
is in this directory's README.md).  img is functions and operatives only, no
class system and no numeric tower: the surface a loader needs to read a file,
resolve names and install a base, booting in a fraction of the time helium
does.  Its forms reach the engine's own read-eval loop; there is no `(repl)`.

# @weight 1

# @lib img.x
# @direct

## img.x -- the loader's dialect

### a primitive reached by its catalog coordinate

```x
(display (num->str ((prim! (lit int) (lit +)) 2 3))) (newline)
```
---
    5

### if and null? are there

```x
(display (if (null? ()) "nil is nil" "no")) (newline)
```
---
    nil is nil

### the recache hook the loader calls last is bound, and does nothing here

```x
(display (if (null? (%image-recache!)) "recache is a no-op" "no")) (newline)
```
---
    recache is a no-op
