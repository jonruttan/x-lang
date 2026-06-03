; type.x -- Type system reflection utilities
;
; Navigate the type struct layout:
;   (name (data (heap (proc (cvt (io (iter)))))))
; IO layout:
;   (analyse (delimit (read (write (display)))))
; CVT layout:
;   (from (to))
;
; Loads before doc.x so cannot use (doc ...) or (note ...).

; --- Type struct navigation ---

; Return the interpreter's type alist from the base object
(def type-alist
  (fn (_ )
    (first (first (first (first (rest (first (%base)))))))))

; Look up a type struct by its handle atom (from type-of)
(def type-by-atom
  (fn (_ handle)
    (def %go (fn (self al)
      (if (null? al) ()
        (if (eq? (first (first al)) handle)
          (rest (first al))
          (self (rest al))))))
    (%go (type-alist))))

; --- Field access ---

; Navigate to IO group (6th element)
(def type-io
  (fn (_ t) (first (rest (rest (rest (rest (rest t))))))))

; Navigate to CVT group (5th element)
(def type-cvt
  (fn (_ t) (first (rest (rest (rest (rest t)))))))

; Navigate to PROC group (4th element): (call-stack eval-stack)
(def type-proc
  (fn (_ t) (first (rest (rest (rest t))))))

; Get the write-stack cell from a type struct
(def type-write-cell
  (fn (_ t) (rest (rest (rest (type-io t))))))

; Get the display-stack cell from a type struct (one past write in the IO group:
; (analyse (delimit (read (write (display (error)))))))
(def type-display-cell
  (fn (_ t) (rest (rest (rest (rest (type-io t)))))))

; Get the analyse-stack cell from a type struct
(def type-analyse-cell
  (fn (_ t) (type-io t)))

; Get the from-conversion cell from a type struct
(def type-from-cell
  (fn (_ t) (first (type-cvt t))))

; Get the to-conversion cell from a type struct
(def type-to-cell
  (fn (_ t) (first (rest (type-cvt t)))))

; --- Stack manipulation ---

; Push a handler onto a type's write stack
(def type-push-write
  (fn (_ ts handler)
    (let ((c (type-write-cell ts)))
      (set-first! c (pair handler (first c))))))

; Pop the top handler from a type's write stack
(def type-pop-write
  (fn (_ ts)
    (let ((c (type-write-cell ts)))
      (set-first! c (rest (first c))))))

; Push a handler onto a type's display stack
(def type-push-display
  (fn (_ ts handler)
    (let ((c (type-display-cell ts)))
      (set-first! c (pair handler (first c))))))

; The call-stack cell of a type (proc group, first element).
(def type-call-cell
  (fn (_ t) (type-proc t)))

; The current (top) call handler -- capture before pushing to delegate to it.
(def type-call-top
  (fn (_ ts) (first (first (type-call-cell ts)))))

; Push a handler onto a type's call stack (overrides how (obj ...) dispatches).
; A pushed (fn (_ obj . args) ...) is invoked via the procedure-call path.
(def type-push-call
  (fn (_ ts handler)
    (let ((c (type-call-cell ts)))
      (set-first! c (pair handler (first c))))))

; Push a handler onto a type's analyse stack
(def type-push-analyse
  (fn (_ ts handler)
    (let ((c (type-analyse-cell ts)))
      (set-first! c (pair handler (first c))))))

; Get the iter-stack cell from a type struct (iter group: 7th element, past io).
(def type-iter-cell
  (fn (_ t) (first (rest (rest (rest (rest (rest (rest t)))))))))

; Push a handler onto a type's iter stack -- sets how (iter obj) builds an
; iterator for this type.  The handler is (fn (_ obj) -> iterator), e.g. via
; make-iter; (iter obj) calls it with the object.
(def type-push-iter
  (fn (_ ts handler)
    (let ((c (type-iter-cell ts)))
      (set-first! c (pair handler (first c))))))

; --- Type casting ---

; Offset to type tag in object layout
(def %type-offset %word-size)

; Overwrite an object's type tag with the type of another object
(def type-cast!
  (fn (_ obj type-src)
    (def %dst-ptr (obj->ptr obj))
    (def %src-ptr (obj->ptr type-src))
    (def %type-val (ptr-ref-word %src-ptr %type-offset))
    (ptr-set-word! %dst-ptr %type-offset %type-val)
    obj))

; provide x/sys/type — registered by x-core.x after module system loads
; Exports: type-alist type-by-atom type-io type-cvt
;   type-write-cell type-analyse-cell type-from-cell type-to-cell
;   type-push-write type-pop-write type-push-analyse type-cast!
