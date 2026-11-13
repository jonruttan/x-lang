; gc.x -- Heap: garbage-collection control as static methods.
;
; The underlying operations are C primitives (src/x-prim/io.c, catalogue ns
; `heap`); the methods fetch them from the registry -- cold operations, so
; inline (prim-ref ...) per the caching rule. The `heap` namespace is
; DE-REGISTERED (R5): no bare heap-* names exist; the class (or a catalogue
; fetch, for pre-object/hook callers) is the only surface.
;
; heap-collect runs an atomic mark+sweep in one C call. It MUST be atomic:
; mark and sweep cannot straddle an allocation, or the sweep frees the
; eval-list cell the evaluator is mid-traversal on (the env/ctrl/extras
; base-tree cells and eval-list scratch cells are X_OBJ_FLAG_NONE, kept
; alive only by marking). The raw mark/sweep prims remain exposed but are
; low-level.

(import x/type/class)

(def-class Heap ()
  (static
    (method collect (self)
      (doc "Run a full, atomic garbage collection (mark + sweep in one C call)."
        (returns ANY "nil (count freed objects via (Heap count) deltas; see x/tool/profile)")
        (sample "(let ((before (Heap count))) (Heap collect) (- before (Heap count)))" "how many objects the collection freed"))
      ((prim-ref (lit heap) (lit collect))))
    (method count (self)
      (doc "Count live heap objects." (returns INTEGER "Number of objects on the heap")
        (example "(> (Heap count) 0)" "#t")
        (sample "(Heap count)" "the number of objects on the heap, e.g. 61234"))
      ((prim-ref (lit heap) (lit count))))
    (method limit! (self (param n INTEGER "Heap-object ceiling; 0 disables"))
      (doc "Set the heap-object ceiling: a collection that cannot get under it errors."
        (returns ANY "nil")
        (sample "(Heap limit! 2000000)" "nil; a collection that leaves more than two million objects then errors"))
      ((prim-ref (lit heap) (lit limit!)) n))
    (method mark (self)
      (doc "LOW-LEVEL: run only the mark phase. Pair with sweep atomically -- prefer (Heap collect)."
        (returns ANY "nil")
        (sample "(do (Heap mark) (Heap sweep))" "nil; (Heap collect) does both in one call"))
      ((prim-ref (lit heap) (lit mark))))
    (method sweep (self)
      (doc "LOW-LEVEL: run only the sweep phase. Pair with mark atomically -- prefer (Heap collect)."
        (returns ANY "nil")
        (sample "(do (Heap mark) (Heap sweep))" "nil; frees what the mark left unmarked"))
      ((prim-ref (lit heap) (lit sweep))))
    (method mark-hook! (self (param f CALLABLE "Hook: called during the mark phase"))
      (doc "Install a GC mark hook (e.g. to mark objects only C can reach)." (returns ANY "nil")
        (sample "(Heap mark-hook! (fn (_) (Heap mark-root! cache)))" "nil; each mark phase then calls the hook"))
      ((prim-ref (lit heap) (lit mark-hook!)) f))
    (method free-hook! (self (param f CALLABLE "Hook: called as objects are freed"))
      (doc "Install a GC free hook for type-specific cleanup." (returns ANY "nil")
        (sample "(Heap free-hook! (fn (_ obj) (release obj)))" "nil; the sweep then calls the hook on each object it frees"))
      ((prim-ref (lit heap) (lit free-hook!)) f))
    (method mark-root! (self (param obj ANY "Object to pin as a GC root"))
      (doc "Register an object as a GC root: it and everything it references survive collection."
        (returns ANY "nil")
        (sample "(Heap mark-root! table)" "nil; table and what it holds survive every later collection"))
      ((prim-ref (lit heap) (lit mark-root!)) obj))
    (method pin! (self (param obj ANY "Object to mark as a system object"))
      (doc "Pin an object with the system flag so the sweeper never frees it." (returns ANY "nil")
        (sample "(Heap pin! buffer)" "nil; the sweeper never frees buffer"))
      ((prim-ref (lit heap) (lit pin!)) obj))))

(doc (provide x/sys/gc Heap)
  (note "GC control homed on the Heap class; ns `heap` is de-registered -- no bare names.")
  (example "(> (Heap count) 0)" "#t")
  (sample "(Heap collect)" "nil, with the unreachable objects freed")
  "Garbage collection control: collect/count/limit! and the mark/free/root hooks, on the Heap class.")
