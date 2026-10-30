; cont.x -- Cont: a continuation the collector can see into.
;
; The engine's call/cc copies the C stack segment from the capture point to
; the stack base and restores it when the continuation is invoked.  The
; collector's root chain -- the stack objects frames register as roots --
; runs through that segment, so while the continuation waits, its nodes are
; bytes in the copy and the mark never walks them.  An object held only by a
; captured frame, an argument evaluated while the call's next argument runs,
; was swept, and the resumed frame read freed memory (x-lang#283).
;
; (Cont capture f) is call/cc with a marker beside the continuation: an
; object of a type whose mark handler walks the saved chain in the copy.  A
; node of the segment is read at its offset in the copy, and an object off
; the segment is marked as the live chain marks it.  The marker lives in
; the environment of the procedure f receives, so it is marked exactly while
; that procedure is, and a dead continuation costs nothing.
;
; What the walk reads is the engine's object layout (lib/x/boot/engine.x
; loads tools/contract/obj-layout.x) and the state list call/cc builds:
; (env save-stack error-handler eval-list root-chain stack-lo stack-size
; stack-copy), bound as %cc-state in the continuation procedure's own
; environment.
(module x/sys/cont)
(import x/type/class)
(import x/core/doors int+ int- int->ptr int< obj->ptr ptr->int ptr->obj ptr-ref-word type-make type-make-instance)

(def-class Cont ()
  (doc "A continuation the collector can see into: call/cc with the captured frames' roots marked while it waits."
    (note "(Cont capture f) replaces (call/cc f) wherever a continuation outlives the frames that captured it -- a generator, a coroutine.")
    (example "(Cont capture (fn (_ k) (k 1)))" "1"))
  (static
    (%callcc (prim-ref (lit ctrl) (lit call/cc)))
    (%tree-mark! (prim-ref (lit heap) (lit tree-mark!)))
    (%heap-off (* %obj-slot-heap %word-size))
    (%type-off (* %obj-slot-type %word-size))
    (%data-off (* %obj-meta-len %word-size))
    (%type-cell (pair () ()) "The marker type, made on the first capture")

    (method capture (self (param f CALLABLE "Receives the continuation, a procedure of the value to pass"))
      (doc "call/cc, with the captured frames' roots marked while the continuation waits."
        (returns ANY "What f answers, or the value the continuation was invoked with"))
      ((Cont %callcc)
        (fn (_ k)
          (let ((m (Cont %marker k)))
            (f (fn (_ . args) (apply k args)))))))

    ; The marker: the continuation and, from its state list, the root-chain
    ; head, the segment's low address and size, and the copy.
    (method %marker (self k)
      (let ((st (Cont %state k)))
        (type-make-instance (Cont %type)
          (pair k (rest (rest (rest (rest st))))))))

    ; %cc-state, read from the continuation procedure's environment: a
    ; procedure's first unit is its C call routine, its second the state
    ; (params . (body . env)).
    (method %state (self k)
      (let ((procstate (ptr->obj (int->ptr
                          (ptr-ref-word (obj->ptr k)
                            (int+ (Cont %data-off) %word-size))))))
        (eval (lit %cc-state) (rest (rest procstate)))))

    (method %type (self)
      (if (null? (first (Cont %type-cell)))
        (%set-first! (Cont %type-cell)
          (type-make "CONTINUATION"
            (list (pair (lit mark) (fn (_ m flags) (Cont %mark m flags))))))
        ())
      (first (Cont %type-cell)))

    ; The mark handler.  A type with a mark handler marks its instances
    ; itself, so the marker's own data comes first; then the saved chain,
    ; each node of it from the head to the first address off the segment
    ; (the nodes below the capture point were popped before it), and the
    ; tree each node holds as the segment holds it: a pair of the segment is
    ; followed into, first then rest, and anything off the segment is marked
    ; by the engine.  An object of the segment is never flagged -- a flag
    ; written into the copy would outlive this collection.
    ;
    ; The walk runs once a marker a collect, over every node of the chain,
    ; so the doors and the offsets are bound once here and the walk is two
    ; closures on them: a class send a node cost some 0.3 s a marker.
    ; Addresses are integers; a word is read through a pointer made at the
    ; read, in the copy, at the address's offset from the segment.
    (method %mark (self m flags)
      ((Cont %tree-mark!) (first m) flags)
      (let ((d (rest (first m)))
            (ref ptr-ref-word) (->ptr int->ptr) (->obj ptr->obj)
            (->int ptr->int) (mark! (Cont %tree-mark!))
            (i+ int+) (i- int-) (i< int<)
            (heap-off (Cont %heap-off)) (type-off (Cont %type-off))
            (first-off (Cont %data-off)) (rest-off (int+ (Cont %data-off) %word-size)))
        (let ((lo (->int (first (rest d))))
              (end (i+ (->int (first (rest d))) (first (rest (rest d)))))
              (delta (i- (->int (first (rest (rest (rest d))))) (->int (first (rest d))))))
          (def saved (fn (_ a off) (ref (->ptr (i+ a delta)) off)))
          (def tree
            (fn (self p)
              (if (eq? p 0) ()
                (if (i< p lo)
                  (mark! (->obj (->ptr p)) flags)
                  (if (i< p end)
                    (if (eq? (saved p type-off) %reflect-spair-tw)
                      (%seq (self (saved p first-off)) (self (saved p rest-off)))
                      ())
                    (mark! (->obj (->ptr p)) flags))))))
          (def chain
            (fn (self node)
              (if (i< node lo) ()
                (if (i< node end)
                  (%seq (tree node) (self (saved node heap-off)))
                  ()))))
          (chain (->int (first d))))))))

(doc (provide x/sys/cont Cont)
  (note "The engine's call/cc stays bare; this is the door for a continuation that waits -- a generator, a coroutine.")
  "Continuations whose captured frames' roots the collector marks while they wait.")
