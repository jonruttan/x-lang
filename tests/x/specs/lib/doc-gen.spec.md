# doc-gen: a method's page shows what (help) shows
# @weight 1

## runtime notes reach the generated entry

`(help Class/method)` shows notes a wrap adds at load -- x/type/block.x's
"Block form:" -- but the generator reads source, where that note never was.
The generator now merges the method's LIVE registry notes into its emitted
entry, deduplicated against the source form's own notes. The emitter here is
a stub that records `note` calls, so the spec is not coupled to Markdown.

### the wrap's note is emitted once, and a note already in the source is not doubled

```x
(do (import x/doc/doc-gen)
    (def-class DgT () (static (method m (self f x) (doc "doc" (note "shared") (returns ANY "r")) (f x))))
    (Block method! DgT 'm)
    (def-class DgRec (extends DocEmit)
      (static (got ())
        (method page-header (self . a) ()) (method section (self . a) ())
        (method class-head (self . a) ()) (method interface-line (self . a) ())
        (method entry-head (self . a) ()) (method alias (self . a) ())
        (method text (self . a) ()) (method params (self . a) ())
        (method returns (self . a) ()) (method examples (self . a) ())
        (method see-also (self . a) ())
        (method note (self s) (DgRec got (pair s (DgRec got))))))
    (%doc-emit-method DgRec '(method m (self f x) (doc "doc" (note "shared") (returns ANY "r")) (f x)) "DgT" #t "")
    (list (List count-if (n) (Str8 includes? "Block form" n) (DgRec got))
          (List count-if (n) (Str8 includes? "shared" n) (DgRec got))))
```
---
    (1 1)

### a method the running library does not have merges nothing

```x
(do (import x/doc/doc-gen)
    (def-class DgRec2 (extends DocEmit)
      (static (got ())
        (method page-header (self . a) ()) (method section (self . a) ())
        (method class-head (self . a) ()) (method interface-line (self . a) ())
        (method entry-head (self . a) ()) (method alias (self . a) ())
        (method text (self . a) ()) (method params (self . a) ())
        (method returns (self . a) ()) (method examples (self . a) ())
        (method see-also (self . a) ())
        (method note (self s) (DgRec2 got (pair s (DgRec2 got))))))
    (%doc-emit-method DgRec2 '(method zz (self f x) (doc "doc" (note "only")) (f x)) "NoSuchClassDg" #t "")
    (DgRec2 got))
```
---
    ("only")
