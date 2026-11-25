# ne.x smoke (dialect entry points)
# @weight 3

End-to-end smoke of the `ne.x` launcher: neon, the base for a language
built on x-lang.  One file per dialect so the boots schedule in parallel
(#320); the story behind these specs is in this directory's README.md.

# @lib ne.x

## ne.x -- neon, helium with the compiler and the Lexer

### arithmetic

```x
(+ 2 3)
```
---
    5

### the dialect names itself

```x
%lang-name
```
---
    "neon"

### Dict and the Lexer are loaded, with no import

```x
(list (Dict dict? (Dict make)) (null? Lexer))
```
---
    (#t #f)

### the compiler is loaded

```x
(null? compile-asm)
```
---
    #f

### the tower is not: a rational is not a literal here

```x
(guard (_ "unbound") 1/3)
```
---
    "unbound"

### nor is a float: the text reads as an integer and a symbol

```x
(guard (_ "unbound") 1.5)
```
---
    "unbound"
