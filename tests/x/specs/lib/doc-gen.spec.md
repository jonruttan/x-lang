# doc-gen: what a class's page shows of its members
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
    ((eval (lit %doc-emit-method) (module x/doc/doc-gen)) DgRec '(method m (self f x) (doc "doc" (note "shared") (returns ANY "r")) (f x)) "DgT" #t "")
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
    ((eval (lit %doc-emit-method) (module x/doc/doc-gen)) DgRec2 '(method zz (self f x) (doc "doc" (note "only")) (f x)) "NoSuchClassDg" #t "")
    (DgRec2 got))
```
---
    ("only")

## a documented field is named by its declaration

A field's doc form wraps its declaration, `(doc DECL "description")`, and a
declaration is `NAME` or `(NAME default)`. The page names the field by the
declaration's name in both shapes, and a static member the same way. Each
case walks a class form as the generator's driver does, through
`doc-walk-with-prims`, into a stub emitter that records the calls the case
reads.

### a field documented with a default is headed by its name

```x
(do (import x/doc/doc-gen doc-walk-with-prims)
    (def-class DgHeads (extends DocEmit)
      (static (got ())
        (method page-header (self . a) ()) (method section (self . a) ())
        (method class-head (self . a) ()) (method interface-line (self . a) ())
        (method alias (self . a) ()) (method text (self . a) ())
        (method note (self . a) ()) (method params (self . a) ())
        (method returns (self . a) ()) (method examples (self . a) ())
        (method see-also (self . a) ())
        (method entry-head (self s) (DgHeads got (pair s (DgHeads got))))))
    (doc-walk-with-prims
      '((def-class DgSite ()
          (doc "A site.")
          (doc (state (lit down)) "Where the site stands.")
          (doc (reason "") "Why it stands there.")
          (doc label "A field documented by name alone.")))
      () DgHeads "")
    (DgHeads got))
```
---
    ("label" "reason" "state")

### a static member documented with a default is headed by its name

```x
(do (import x/doc/doc-gen doc-walk-with-prims)
    (def-class DgHeads2 (extends DocEmit)
      (static (got ())
        (method page-header (self . a) ()) (method section (self . a) ())
        (method class-head (self . a) ()) (method interface-line (self . a) ())
        (method alias (self . a) ()) (method text (self . a) ())
        (method note (self . a) ()) (method params (self . a) ())
        (method returns (self . a) ()) (method examples (self . a) ())
        (method see-also (self . a) ())
        (method entry-head (self s) (DgHeads2 got (pair s (DgHeads2 got))))))
    (doc-walk-with-prims
      '((def-class DgSites ()
          (static (doc (all ()) "Every site made.")
                  (doc (made 0) "How many sites were made."))))
      () DgHeads2 "")
    (DgHeads2 got))
```
---
    ("made" "all")

### the description and the lookup name follow the declaration

```x
(do (import x/doc/doc-gen doc-walk-with-prims)
    (def-class DgText (extends DocEmit)
      (static (got ())
        (method page-header (self . a) ()) (method section (self . a) ())
        (method class-head (self . a) ()) (method interface-line (self . a) ())
        (method entry-head (self . a) ()) (method note (self . a) ())
        (method params (self . a) ()) (method returns (self . a) ())
        (method examples (self . a) ()) (method see-also (self . a) ())
        (method alias (self s) (DgText got (pair s (DgText got))))
        (method text (self s) (DgText got (pair s (DgText got))))))
    (doc-walk-with-prims
      '((def-class DgSite2 ()
          (doc (state (lit down)) "Where the site stands.")))
      () DgText "")
    (DgText got))
```
---
    ("Where the site stands." "DgSite2-state")


## a member's note says who holds it

A field is data each instance carries. A member declared inside
`(static ...)` is the class's own, a static member, so its note says that
instead.

### a static member's note says the class holds it

```x
(do (import x/doc/doc-gen doc-walk-with-prims)
    (def-class DgNotes (extends DocEmit)
      (static (got ())
        (method page-header (self . a) ()) (method section (self . a) ())
        (method class-head (self . a) ()) (method interface-line (self . a) ())
        (method entry-head (self . a) ()) (method alias (self . a) ())
        (method text (self . a) ()) (method params (self . a) ())
        (method returns (self . a) ()) (method examples (self . a) ())
        (method see-also (self . a) ())
        (method note (self s) (DgNotes got (pair s (DgNotes got))))))
    (doc-walk-with-prims
      '((def-class DgSite3 ()
          (static (doc (all ()) "Every site made."))))
      () DgNotes "")
    (DgNotes got))
```
---
    ("Static member: data held by DgSite3 itself, not by its instances.")

### a field's note says an instance carries it

```x
(do (import x/doc/doc-gen doc-walk-with-prims)
    (def-class DgNotes2 (extends DocEmit)
      (static (got ())
        (method page-header (self . a) ()) (method section (self . a) ())
        (method class-head (self . a) ()) (method interface-line (self . a) ())
        (method entry-head (self . a) ()) (method alias (self . a) ())
        (method text (self . a) ()) (method params (self . a) ())
        (method returns (self . a) ()) (method examples (self . a) ())
        (method see-also (self . a) ())
        (method note (self s) (DgNotes2 got (pair s (DgNotes2 got))))))
    (doc-walk-with-prims
      '((def-class DgSite4 ()
          (doc (state (lit down)) "Where the site stands.")))
      () DgNotes2 "")
    (DgNotes2 got))
```
---
    ("Field: data carried by a DgSite4 instance.")

### a static member declared without a doc form gets the static note too

```x
(do (import x/doc/doc-gen doc-walk-with-prims)
    (def-class DgNotes3 (extends DocEmit)
      (static (got ())
        (method page-header (self . a) ()) (method section (self . a) ())
        (method class-head (self . a) ()) (method interface-line (self . a) ())
        (method entry-head (self . a) ()) (method alias (self . a) ())
        (method text (self . a) ()) (method params (self . a) ())
        (method returns (self . a) ()) (method examples (self . a) ())
        (method see-also (self . a) ())
        (method note (self s) (DgNotes3 got (pair s (DgNotes3 got))))))
    (doc-walk-with-prims
      '((def-class DgSite5 ()
          (static (made 0) (private held))))
      () DgNotes3 "")
    (list (List count-if (n) (Str8 includes? "Static member" n) (DgNotes3 got))
          (List count-if (n) (Str8 includes? "Private:" n) (DgNotes3 got))))
```
---
    (2 1)
