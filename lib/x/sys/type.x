; type.x -- Type system reflection: the mechanism, registered in the catalog.
;
; Navigate the type struct layout:
;   (name (data (heap (proc (cvt (io (iter (ops))))))))
; IO layout:
;   (analyse (delimit (read (write (display)))))
; CVT layout:
;   (from (to))
;
; The helpers are %-private here and FILED IN THE CATALOG under ns `type`
; (joining the C entries make / make-instance / ? / of / name). Consumers
; fetch what they use at module load, e.g.:
;   (def %type-push-op (prim-ref (lit type) (lit push-op)))
; The human-facing API is the Type class (lib/x/type/type.x), which loads
; after the object system.
;
; Loads before doc.x so cannot use (doc ...) or (note ...); the Type class
; carries the documentation.

; --- Type struct navigation ---

; Return the interpreter's type alist from the base object
(def %type-alist
  (fn (_ )
    (first (first (first (first (rest (first (%base)))))))))

; Look up a type struct by its handle atom (from type-of)
(def %type-by-atom
  (fn (_ handle)
    (def %go (fn (self al)
      (if (null? al) ()
        (if (eq? (first (first al)) handle)
          (rest (first al))
          (self (rest al))))))
    (%go (%type-alist))))

; --- Field access ---

; Navigate to IO group (6th element)
(def %type-io
  (fn (_ t) (first (rest (rest (rest (rest (rest t))))))))

; Navigate to CVT group (5th element)
(def %type-cvt
  (fn (_ t) (first (rest (rest (rest (rest t)))))))

; Navigate to PROC group (4th element): (call-stack eval-stack).
; NOT %type-proc: boot's predicates.x owns that name (the FN type handle
; backing procedure?), and this file loads after it -- a same-named def here
; clobbers the handle and breaks procedure? everywhere.
(def %type-proc-group
  (fn (_ t) (first (rest (rest (rest t))))))

; Get the write-stack cell from a type struct
(def %type-write-cell
  (fn (_ t) (rest (rest (rest (%type-io t))))))

; Get the display-stack cell from a type struct (one past write in the IO group:
; (analyse (delimit (read (write (display (error)))))))
(def %type-display-cell
  (fn (_ t) (rest (rest (rest (rest (%type-io t)))))))

; Get the analyse-stack cell from a type struct
(def %type-analyse-cell
  (fn (_ t) (%type-io t)))

; Get the from-conversion cell from a type struct
(def %type-from-cell
  (fn (_ t) (first (%type-cvt t))))

; Get the to-conversion cell from a type struct
(def %type-to-cell
  (fn (_ t) (first (rest (%type-cvt t)))))

; --- Stack manipulation ---

; Push a handler onto a type's write stack
(def %type-push-write
  (fn (_ ts handler)
    (let ((c (%type-write-cell ts)))
      (set-first! c (pair handler (first c))))))

; Pop the top handler from a type's write stack
(def %type-pop-write
  (fn (_ ts)
    (let ((c (%type-write-cell ts)))
      (set-first! c (rest (first c))))))

; Push a handler onto a type's display stack
(def %type-push-display
  (fn (_ ts handler)
    (let ((c (%type-display-cell ts)))
      (set-first! c (pair handler (first c))))))

; The call-stack cell of a type (proc group, first element).
(def %type-call-cell
  (fn (_ t) (%type-proc-group t)))

; The current (top) call handler -- capture before pushing to delegate to it.
(def %type-call-top
  (fn (_ ts) (first (first (%type-call-cell ts)))))

; Push a handler onto a type's call stack (overrides how (obj ...) dispatches).
; A pushed (fn (_ obj . args) ...) is invoked via the procedure-call path.
(def %type-push-call
  (fn (_ ts handler)
    (let ((c (%type-call-cell ts)))
      (set-first! c (pair handler (first c))))))

; Push a handler onto a type's analyse stack
(def %type-push-analyse
  (fn (_ ts handler)
    (let ((c (%type-analyse-cell ts)))
      (set-first! c (pair handler (first c))))))

; Get the delimit-stack cell from a type struct (io group, 2nd element)
(def %type-delimit-cell
  (fn (_ t) (rest (%type-io t))))

; Get the read-stack cell from a type struct (io group, 3rd element)
(def %type-read-cell
  (fn (_ t) (rest (rest (%type-io t)))))

; Push a handler onto a type's delimit stack
(def %type-push-delimit
  (fn (_ ts handler)
    (let ((c (%type-delimit-cell ts)))
      (set-first! c (pair handler (first c))))))

; Push a handler onto a type's read stack
(def %type-push-read
  (fn (_ ts handler)
    (let ((c (%type-read-cell ts)))
      (set-first! c (pair handler (first c))))))

; Get the iter-stack cell from a type struct (iter group: 7th element, past io).
(def %type-iter-cell
  (fn (_ t) (first (rest (rest (rest (rest (rest (rest t)))))))))

; Push a handler onto a type's iter stack -- sets how (iter obj) builds an
; iterator for this type.  The handler is (fn (_ obj) -> iterator), e.g. via
; make-iter; (iter obj) calls it with the object.
(def %type-push-iter
  (fn (_ ts handler)
    (let ((c (%type-iter-cell ts)))
      (set-first! c (pair handler (first c))))))

; --- Generic-operator dispatch (ops group: 8th element, past iter) ---

; Get the ops cell (the ((op-sym . handler) ...) alist stack cell)
(def %type-ops-cell
  (fn (_ t) (first (first (rest (rest (rest (rest (rest (rest (rest t)))))))))))

; Register a binary generic-operator handler for op-sym on a type:
;   (%type-push-op ts (lit +) (fn (_ a b) ...))
; The C operators (+ - * / % = <) dispatch here when EXACTLY ONE operand is a
; typed instance; the handler receives the raw operands and owns coercing the
; plain side. (Mixed typed/typed dispatch is an open design question -- the
; cvt from-alists declare the cross-type relation.) Prepend semantics: a
; re-registration shadows the older handler. This replaces set!-wrapping the
; global operators -- types register ops; nothing wraps ambient names.
(def %type-push-op
  (fn (_ ts op-sym handler)
    (let ((c (%type-ops-cell ts)))
      (set-first! c (pair (pair op-sym handler) (first c))))))

; --- Type casting ---

; Offset to type tag in object layout (also reached by tool/compile.x)
(def %type-offset %word-size)

; Overwrite an object's type tag with the type of another object
(def %type-cast!
  (fn (_ obj type-src)
    (def %dst-ptr (obj->ptr obj))
    (def %src-ptr (obj->ptr type-src))
    (def %type-val (ptr-ref-word %src-ptr %type-offset))
    (ptr-set-word! %dst-ptr %type-offset %type-val)
    obj))

; --- File everything in the catalog (ns type) ---
(prim-reg! (lit type) (lit alist)         %type-alist)
(prim-reg! (lit type) (lit by-atom)       %type-by-atom)
(prim-reg! (lit type) (lit io)            %type-io)
(prim-reg! (lit type) (lit cvt)           %type-cvt)
(prim-reg! (lit type) (lit proc)          %type-proc-group)
(prim-reg! (lit type) (lit write-cell)    %type-write-cell)
(prim-reg! (lit type) (lit display-cell)  %type-display-cell)
(prim-reg! (lit type) (lit analyse-cell)  %type-analyse-cell)
(prim-reg! (lit type) (lit from-cell)     %type-from-cell)
(prim-reg! (lit type) (lit to-cell)       %type-to-cell)
(prim-reg! (lit type) (lit push-write)    %type-push-write)
(prim-reg! (lit type) (lit pop-write)     %type-pop-write)
(prim-reg! (lit type) (lit push-display)  %type-push-display)
(prim-reg! (lit type) (lit call-cell)     %type-call-cell)
(prim-reg! (lit type) (lit call-top)      %type-call-top)
(prim-reg! (lit type) (lit push-call)     %type-push-call)
(prim-reg! (lit type) (lit push-analyse)  %type-push-analyse)
(prim-reg! (lit type) (lit delimit-cell)  %type-delimit-cell)
(prim-reg! (lit type) (lit read-cell)     %type-read-cell)
(prim-reg! (lit type) (lit push-delimit)  %type-push-delimit)
(prim-reg! (lit type) (lit push-read)     %type-push-read)
(prim-reg! (lit type) (lit iter-cell)     %type-iter-cell)
(prim-reg! (lit type) (lit push-iter)     %type-push-iter)
(prim-reg! (lit type) (lit ops-cell)      %type-ops-cell)
(prim-reg! (lit type) (lit push-op)       %type-push-op)
(prim-reg! (lit type) (lit cast!)         %type-cast!)
