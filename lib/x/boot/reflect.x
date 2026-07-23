; reflect.x -- reflective object accessors over the layout contract (bootstrap)
;
; The interpreter is fully reflective: %obj->ptr + the ptr word ops reach
; every word of every object, and tools/obj-layout.x (included by x-core.x
; before data.x) commits the offsets.  These accessors REPLACE the C prims
; of the same catalog names -- the C table rows are deleted and the ISA
; keeps only the load/store instructions -- filed with prim-reg! so every
; later consumer's (prim-ref (lit obj) ...) fetch is unchanged.
;
; GC-safety: raw pointers held as ints across these bodies are safe because
; collection is EXPLICIT-only -- allocation (the arg lists here) never
; triggers a collect, so an object cannot move between the %obj->ptr and
; the word op that consumes it.
;
; Boot constraints: loads right after data.x (needs its %-instruments and
; %word-size/%data-offset); `if` is not defined until core/control.x, so
; bodies use `match` (a C spine form).
;
; C semantics preserved exactly:
;   (obj ref o i)         the OBJECT stored in data word i
;   (obj set! o i v)      data word i := v (as object ref); returns v
;   (obj meta-ref o i)    0 unless o carries %obj-flag-meta; else meta word i
;   (obj meta-set! o i v) no-op unless flagged; meta word i := v (int); returns v
; Extended meta unit I is PREPENDED, at word -(I+1) (see the descriptor).

; The materialization instruction: read a word back AS an object (see the
; (ptr ->obj) manifest entry).  With it, accessors can RETURN objects.
(def %ptr->obj (prim-ref (lit ptr) (lit ->obj)))

; Header-word byte offsets, computed ONCE: these accessors run multiple
; times per printed cell, and the multiply is a boot constant.
(def %reflect-flags-off (* %obj-slot-flags %word-size))
(def %reflect-type-off  (* %obj-slot-type %word-size))

; The flags header word of an object.
(def %reflect-flags
  (fn (_ o) (%ptr-ref-word (%obj->ptr o) %reflect-flags-off)))

; Data-slot read: materialize the object whose pointer sits in data word i.
; Addressing via data.x's %data-word-off -- the ONE formula shared with the
; write half (%obj-set!), so ref and set! can never target different words.
(def %reflect-obj-ref
  (fn (_ o i)
    (%ptr->obj (%int->ptr
      (%ptr-ref-word (%obj->ptr o) (%data-word-off i))))))

(def %reflect-meta-ref
  (fn (_ o i)
    (match
      ((eq? o ()) 0)
      ((eq? (& (%reflect-flags o) %obj-flag-meta) 0) 0)
      (#t (%ptr-ref-word (%obj->ptr o) (- 0 (* (+ i 1) %word-size)))))))

(def %reflect-meta-set!
  (fn (_ o i v)
    (match
      ((eq? o ()) v)
      ((eq? (& (%reflect-flags o) %obj-flag-meta) 0) v)
      (#t (do (%ptr-set-word! (%obj->ptr o) (- 0 (* (+ i 1) %word-size)) v)
              v)))))

; --- base-cell reflection ---
; The walker (%reflect-step / %reflect-path / %reflect-base-cell) lives in
; boot/registry.x, which loads first.  Cells resolved once at boot: they
; are spine-stable (their CONTENTS mutate; the cells are never replaced).
(def %reflect-meta-extra-cell    (%reflect-base-cell (lit obj-meta-extra)))

; (obj meta-count) / (obj meta-count!) -- the allocation policy cell: how
; many extra meta units subsequent allocations prepend.  The cell holds an
; int ATOM; its value is the atom's data word (first-int/set-first-int!).
; meta-count! returns the PREVIOUS count (C contract).
(def %reflect-meta-count
  (fn (_) (%first-int (first %reflect-meta-extra-cell))))
(def %reflect-meta-count!
  (fn (_ n)
    (do
      (def %reflect-prev-extra (%first-int (first %reflect-meta-extra-cell)))
      (%set-first-int! (first %reflect-meta-extra-cell) n)
      %reflect-prev-extra)))

; (io error-line) / (io error-file) -- the source location FROZEN at the last
; error's raise site.  The C raise path snapshots the live line/file counters
; into the base cells err-line/err-file BEFORE the caught guard pops its handler
; (control.c pops it before its body runs, so the REPL -- which reads these from
; inside the handler body -- can no longer reach the handler object).  Reading
; the snapshot cells, not the handler, is what makes the reported line survive.
; err-line is a line int; err-file is a file id indexing the (id . path) alist
; that `include` grows in file-registry (id 0 / stdin -> no file, "").
(def %reflect-err-line-cell      (%reflect-base-cell (lit err-line)))
(def %reflect-err-file-cell      (%reflect-base-cell (lit err-file)))
(def %reflect-file-registry-cell (%reflect-base-cell (lit file-registry)))
(def %reflect-error-line
  (fn (_) (%first-int (first %reflect-err-line-cell))))
; Walk the (id . path) alist for `id`, returning its path string; "" when the
; id is absent (0, or never registered).  Int equality via (- a b) then the
; proven (eq? <int> 0) zero-test -- eq? on two int atoms is not relied upon.
(def %reflect-registry-lookup
  (fn (self id reg)
    (match
      ((eq? reg ()) "")
      ((eq? (- (%first-int (first (first reg))) id) 0) (rest (first reg)))
      (#t (self id (rest reg))))))
(def %reflect-error-file
  (fn (_)
    (%reflect-registry-lookup
      (%first-int (first %reflect-err-file-cell))
      (first %reflect-file-registry-cell))))

; --- type reflection ---
; The type slot (header word 1) as an integer tag.
(def %reflect-type-word
  (fn (_ o) (%ptr-ref-word (%obj->ptr o) %reflect-type-off)))

; Discriminator tags, resolved once at boot (static objects, stable).
; The static-ATOM sentinel tag marks type HANDLES (the name atoms `type of`
; returns) and other raw atoms.  It is NOT what #t/#f carry (nil-typed,
; tag 0) and NOT what interned symbols carry (the SYMBOL type tree) -- so
; probe it from a real handle.  The structural-PAIR tag is every registered
; type TREE's own tag, probed from the first type-alist entry; C files the
; alist during init, before any lib loads.
(def %reflect-type-alist-cell (%reflect-base-cell (lit type-alist)))
(def %reflect-satom-tw
  (%reflect-type-word ((prim-ref (lit type) (lit of)) 0)))
(def %reflect-spair-tw
  (%reflect-type-word (rest (first (first %reflect-type-alist-cell)))))

; THE TYPE-TAG TRAP predicate: does this type word mark a type HANDLE
; rather than an instance?  Both sentinel tags qualify -- the static-atom
; tag (bare handle atoms) and the structural-pair tag (registered type
; trees) -- and neither carries a navigable type-tree pointer, so every
; consumer must branch on BOTH before dereferencing the word.
(def %reflect-handle-tw?
  (fn (_ tw)
    (match
      ((eq? tw %reflect-satom-tw) #t)
      (#t (eq? tw %reflect-spair-tw)))))

; (obj retag!) -- write an object's type header slot to the type resolved
; from a registry handle: the door for x-defined types over C-created
; values (#101 -- BOOL claims the #t/#f statics at boot; C prims return
; them by IDENTITY, so only the object itself changing type touches them).
; Born as a C instruction on the #101 branch, retired here by ruling: the
; store is the same layout-contract write %type-cast! (struct.x) performs,
; so it is pure reflection like every accessor above.  RAW like the mem
; ops: retagging an object whose payload does not match the new type's
; declared layout (its units walk -- see bool.x's units 0) is UB, and the
; caller owns it; any new consumer on the collect path gets ASan-verified
; before it lands (the #101 lesson).  Unknown handles refuse -- policy in
; x.  Returns nil (the C side-effect-primitive contract, kept).
(def %reflect-retag!
  (fn (_ o h)
    (do
      (def %reflect-rtt (%registry-assoc-rest h (first %reflect-type-alist-cell)))
      (match
        ((eq? %reflect-rtt ()) (error "retag!: unknown type handle"))
        (#t (do
              (%ptr-set-word! (%obj->ptr o) %reflect-type-off
                (%ptr->int (%obj->ptr %reflect-rtt)))
              ()))))))

; Copying string maker (C used x_mkstr on the name atom's bytes).
(def %reflect-sym->str (prim-ref (lit sym) (lit ->str)))

; The name atom of a type tree: descriptor path (type-name type f f).
(def %reflect-type-tree-name
  (fn (_ t) (%reflect-step t (%reflect-path (lit type-name) %base-paths))))

; (type name o) -- the type's name as a FRESH string, or nil.  Mirrors the
; C branches exactly: a bare atom / structural pair is a type HANDLE,
; resolved against the type-alist (its own type field holds a sentinel, so
; navigating it would misread the tag payload); nil-typed objects have no
; name; anything else reads its type tree's name field.
(def %reflect-name-str
  (fn (_ n)
    (match
      ((eq? n ()) ())
      (#t (%reflect-sym->str n)))))
(def %reflect-handle-name
  (fn (_ h)
    (do
      (def %reflect-tt (%registry-assoc-rest h (first %reflect-type-alist-cell)))
      (match
        ((eq? %reflect-tt ()) ())
        (#t (%reflect-name-str (%reflect-type-tree-name %reflect-tt)))))))
(def %reflect-type-name
  (fn (_ o)
    (match
      ((eq? o ()) ())
      (#t
        (do
          (def %reflect-twd (%reflect-type-word o))
          (match
            ((%reflect-handle-tw? %reflect-twd) (%reflect-handle-name o))
            ((eq? %reflect-twd 0) ())
            (#t (%reflect-name-str
                  (%reflect-type-tree-name
                    (%ptr->obj (%int->ptr %reflect-twd)))))))))))

; (iter new o) -- fetch the iter handler from o's type tree (descriptor
; path type-iter) and apply it to o; nil for nil-typed/sentinel-typed
; objects, types without a tree, or trees without an iter handler.
; C semantics (x_prim_iter) preserved: the handler is APPLIED (args as
; values, not re-evaluated).
; The type-iter step list, resolved ONCE at load: %base-paths is a boot-time
; literal (no writers), and the path is rooted at the type-tree ARGUMENT,
; not the base -- so caching holds no base reference and survives re-basing.
; (iter new) is per-iteration hot; a per-call descriptor scan is ~100
; interpreted steps of pure waste.
(def %reflect-iter-path (%reflect-path (lit type-iter) %base-paths))
(def %reflect-iter-new
  (fn (_ o)
    (match
      ((eq? o ()) ())
      (#t
        (do
          (def %reflect-twd (%reflect-type-word o))
          (match
            ((eq? %reflect-twd 0) ())
            ((%reflect-handle-tw? %reflect-twd) ())
            (#t
              (do
                (def %reflect-tt (%ptr->obj (%int->ptr %reflect-twd)))
                (match
                  ((eq? (%reflect-type-word %reflect-tt) %reflect-spair-tw)
                    (do
                      (def %reflect-ih (%reflect-step %reflect-tt %reflect-iter-path))
                      (match
                        ((eq? %reflect-ih ()) ())
                        (#t (apply %reflect-ih (pair o ()))))))
                  (#t ()))))))))))

; (prim-reg! ns method value) -- the catalog protocol's producer half:
; file an entry under ns/method.  Prepend semantics (a re-registration
; shadows on lookup); returns nil (C contract).  Needs set-first!/set-rest!
; (data.x), which is why it lives here and not in boot/registry.x with the
; read half.  No manual rooting: the args live in env frames, and the
; explicit-only GC never collects mid-body.
(def prim-reg!
  (fn (_ ns method value)
    (do
      (def %reflect-dom (%registry-domain-pair ns (first %registry-prims-cell)))
      (match
        ((eq? %reflect-dom ())
          (%set-first! %registry-prims-cell
            (pair (pair ns (pair (pair method value) ()))
                  (first %registry-prims-cell))))
        (#t (%set-rest! %reflect-dom (pair (pair method value) (rest %reflect-dom)))))
      ())))

; File into the catalog under the retired C prims' names; %obj-set! is
; data.x's (already the pure-reflection implementation).
(prim-reg! (lit obj) (lit ref)         %reflect-obj-ref)
(prim-reg! (lit obj) (lit set!)        %obj-set!)
(prim-reg! (lit obj) (lit meta-ref)    %reflect-meta-ref)
(prim-reg! (lit obj) (lit meta-set!)   %reflect-meta-set!)
(prim-reg! (lit obj) (lit meta-count)  %reflect-meta-count)
(prim-reg! (lit obj) (lit meta-count!) %reflect-meta-count!)
(prim-reg! (lit obj) (lit retag!)      %reflect-retag!)
(prim-reg! (lit io)  (lit error-line)  %reflect-error-line)
(prim-reg! (lit io)  (lit error-file)  %reflect-error-file)
(prim-reg! (lit type) (lit name)       %reflect-type-name)
(prim-reg! (lit iter) (lit new)        %reflect-iter-new)
