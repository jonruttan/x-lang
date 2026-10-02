# @no-seam-collect
<!-- A child tokenizer base, like core/sandbox.spec.md: objects reachable only
     through it are invisible to the parent's mark, so this file runs with no
     seam collects. -->
# @weight 1
# @requires native/jit

The Lexer's compiled states beside other native code: a program that lexes,
then assembles and frees a buffer of its own, then lexes again, as x-cc's
compiler does.

## other native code comes and goes

### an assembler buffer made, finalized and freed between two reads leaves the states whole

```x
(do
  (import x/reader/lexer)
  (import x/tool/asm)
  (def %lxa-l (Lexer make (list
    (Lexer skip " ")
    (Lexer until () "/*" "*/")
    (Lexer quoted 'str 34 34 92)
    (Lexer run 'id "ab" "ab"))))
  (def %lxa-before (%lxa-l read-str "a \"x\\ny\" /* c */ b"))
  (def %lxa-a (asm-new))
  (asm-prologue! %lxa-a)
  (asm-epilogue! %lxa-a)
  (asm-finalize! %lxa-a)
  (asm-free! %lxa-a)
  (Heap collect)
  (write (list %lxa-before (%lxa-l read-str "a \"x\\ny\" /* c */ b")))
  (newline))
```
---
    ((('id "a") ('str "\"x\\ny\"") ('id "b")) (('id "a") ('str "\"x\\ny\"") ('id "b")))
