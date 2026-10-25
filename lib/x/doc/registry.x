; registry.x -- Doc: the documentation registry as data.
;
; Every (doc ...) form files one entry in the registry doc.x keeps, a list
; (name desc returns params examples sees notes samples) in the order
; %doc-register! takes them.  This class hands one back as a record with a
; field per part, and lists the names; help, apropos, modules and Tab
; completion read the registry through it.  The doctest checker and the
; reference generator walk the entries themselves.
;
; The registry fills lazily: a doc form is stashed at load and committed on
; the first read, so every reader commits first, through the catalogue door
; doc.x files.  The entry list and the lookup are shared with this file; the
; record is built from the entry's positions, so the layout is written in
; two places, here and at %doc-register!.
(module x/doc/registry)

(import x/type/class)

(def-class Doc ()
  (doc "A documentation entry as data: what one (doc ...) form filed, a field per part. (Doc entry 'name) answers one; (Doc names) lists every documented name. The params are (name TYPE desc) triples, the examples and samples (expr . result) pairs of strings, the sees symbols and the notes strings, as the doc form wrote them."
    (example "((Doc entry 'Str8/split) name)" "'Str8/split")
    (example "(List map first ((Doc entry 'Str8/split) params))" "('sep 's)"))
  (name "The symbol the entry is keyed under: a bare name, Class/method, or a module name")
  (desc "The summary: the doc form's trailing string")
  (returns "The return annotation, (TYPE desc), or () when the form states none")
  (params "The parameters as (name TYPE desc) triples, in order")
  (examples "The (expr . result) pairs the doctest gate runs, both strings")
  (sees "The names the entry refers to, as symbols")
  (notes "The note strings, in order")
  (samples "The (expr . result) pairs shown but never run, both strings")
  (static
    (method entry (self (param name ANY "A documented name: a symbol such as 'Str8/split, or the same as a string"))
      (doc "The entry documented under name, as a Doc record, or () when nothing is documented under it. A name is a bare symbol as the registry keys it, a method as Class/method, a module as its name; a string is interned first."
        (returns ANY "A Doc record, or ()")
        (example "((Doc entry \"Str8/split\") name)" "'Str8/split")
        (example "(first ((Doc entry 'Str8/split) returns))" "'LIST")
        (example "(null? (Doc entry 'no-such-name-zz))" "#t"))
      ((prim-ref (lit doc) (lit commit!)))
      (def key (if (str? name) (Str8 ->sym name) name))
      (def e (%doc-lookup key))
      ; The parts are read in one walk down the entry: help reads a record
      ; for every member of a class, and a class call per part costs more
      ; than the record itself.
      (if (null? e) ()
        (let ()
          (def r1 (rest e)) (def r2 (rest r1)) (def r3 (rest r2))
          (def r4 (rest r3)) (def r5 (rest r4)) (def r6 (rest r5))
          (def r7 (rest r6))
          (new Doc
            (first e) (first r1) (first r2) (first r3)
            (first r4) (first r5) (first r6) (first r7)))))
    (method names (self)
      (doc "Every documented name, sorted, each once: the names apropos searches and Tab completes."
        (returns LIST "Symbols, sorted by name")
        (example "(List includes? 'Str8/split (Doc names))" "#t"))
      ((prim-ref (lit doc) (lit commit!)))
      ; The order is Str8 <?'s, one block compare of the common prefix and
      ; then the shorter first, taken on the engine's instructions directly:
      ; a sort of the whole registry makes thousands of comparisons, and a
      ; class call costs each one several times what the compare does.
      (def %mem-cmp (prim-ref (lit mem) (lit cmp)))
      (def %byte-len (prim-ref (lit str) (lit byte-len)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def %name<?
        (fn (_ a b)
          (def sa (symbol->str a))
          (def sb (symbol->str b))
          (def la (%byte-len sa))
          (def lb (%byte-len sb))
          (def c (%mem-cmp (%str->ptr sa) (%str->ptr sb) (if (< lb la) lb la)))
          (if (eq? c 0) (< la lb) (eq? c -1))))
      ; Sorted first, then the duplicates dropped in one pass: a name
      ; documented twice sits beside itself once sorted.  (List distinct)
      ; walks the whole list for each element, through equal?, and over the
      ; registry's hundreds of names that is tens of millions of
      ; allocations in one call.
      (List uniq
        (List sort %name<?
          (List map (fn (_ e) (first e)) (first %doc-registry-cell)))))))

(doc (provide x/doc/registry Doc)
  (note "The registry as data: (Doc entry 'name) answers a record with name, desc, returns, params, examples, sees, notes and samples; (Doc names) lists every documented name.")
  (example "((Doc entry 'Str8/split) name)" "'Str8/split")
  "Doc: the documentation registry as data -- one record per documented name.")
