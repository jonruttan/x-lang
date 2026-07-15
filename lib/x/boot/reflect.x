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
; the word op that consumes it.  (See docs/gc-stack-roots.md.)
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

; The flags header word of an object.
(def %reflect-flags
  (fn (_ o) (%ptr-ref-word (%obj->ptr o) (* %obj-slot-flags %word-size))))

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
(def %reflect-error-handler-cell (%reflect-base-cell (lit error-handler)))

; (obj meta-count) / (obj meta-count!) -- the allocation policy cell: how
; many extra meta units subsequent allocations prepend.  The cell holds an
; int ATOM; its value is the atom's data word (first-int/set-first-int!).
; meta-count! returns the PREVIOUS count (C contract).
(def %reflect-meta-count
  (fn (_) (first-int (first %reflect-meta-extra-cell))))
(def %reflect-meta-count!
  (fn (_ n)
    (do
      (def old (first-int (first %reflect-meta-extra-cell)))
      (set-first-int! (first %reflect-meta-extra-cell) n)
      old)))

; (io error-line) -- the line recorded in the active error handler, 0 when
; no handler is installed.  The handler's line lives in an INT-slot at
; handler path (r r r) -- read as rest-int of (r r), per the walker note.
(def %reflect-error-line
  (fn (_)
    (match
      ((eq? (first %reflect-error-handler-cell) ()) 0)
      (#t (rest-int (rest (rest (first %reflect-error-handler-cell))))))))

; --- type reflection ---
; The type slot (header word 1) as an integer tag.
(def %reflect-type-word
  (fn (_ o) (%ptr-ref-word (%obj->ptr o) (* %obj-slot-type %word-size))))

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
      (def %t (%registry-assoc-rest h (first %reflect-type-alist-cell)))
      (match
        ((eq? %t ()) ())
        (#t (%reflect-name-str (%reflect-type-tree-name %t)))))))
(def %reflect-type-name
  (fn (_ o)
    (match
      ((eq? o ()) ())
      (#t
        (do
          (def %tw (%reflect-type-word o))
          (match
            ((eq? %tw %reflect-satom-tw) (%reflect-handle-name o))
            ((eq? %tw %reflect-spair-tw) (%reflect-handle-name o))
            ((eq? %tw 0) ())
            (#t (%reflect-name-str
                  (%reflect-type-tree-name
                    (%ptr->obj (%int->ptr %tw)))))))))))

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
          (def %tw (%reflect-type-word o))
          (match
            ((eq? %tw 0) ())
            ((eq? %tw %reflect-satom-tw) ())
            ((eq? %tw %reflect-spair-tw) ())
            (#t
              (do
                (def %t (%ptr->obj (%int->ptr %tw)))
                (match
                  ((eq? (%reflect-type-word %t) %reflect-spair-tw)
                    (do
                      (def %h (%reflect-step %t %reflect-iter-path))
                      (match
                        ((eq? %h ()) ())
                        (#t (apply %h (pair o ()))))))
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
      (def %dom (%registry-domain-pair ns (first %registry-prims-cell)))
      (match
        ((eq? %dom ())
          (set-first! %registry-prims-cell
            (pair (pair ns (pair (pair method value) ()))
                  (first %registry-prims-cell))))
        (#t (set-rest! %dom (pair (pair method value) (rest %dom)))))
      ())))

; File into the catalog under the retired C prims' names; %obj-set! is
; data.x's (already the pure-reflection implementation).
(prim-reg! (lit obj) (lit ref)         %reflect-obj-ref)
(prim-reg! (lit obj) (lit set!)        %obj-set!)
(prim-reg! (lit obj) (lit meta-ref)    %reflect-meta-ref)
(prim-reg! (lit obj) (lit meta-set!)   %reflect-meta-set!)
(prim-reg! (lit obj) (lit meta-count)  %reflect-meta-count)
(prim-reg! (lit obj) (lit meta-count!) %reflect-meta-count!)
(prim-reg! (lit io)  (lit error-line)  %reflect-error-line)
(prim-reg! (lit type) (lit name)       %reflect-type-name)
(prim-reg! (lit iter) (lit new)        %reflect-iter-new)
