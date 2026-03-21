; type.x -- Type system reflection utilities
;
; Navigate the type struct layout:
;   (name (data (heap (proc (cvt (io (iter)))))))
; IO layout:
;   (analyse (delimit (read (write (display (error))))))
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
    (def %go (fn (_ al)
      (if (null? al) ()
        (if (eq? (first (first al)) handle)
          (rest (first al))
          (%go (rest al))))))
    (%go (type-alist))))

; --- Field access ---

; Navigate to IO group (6th element)
(def type-io
  (fn (_ t) (first (rest (rest (rest (rest (rest t))))))))

; Navigate to CVT group (5th element)
(def type-cvt
  (fn (_ t) (first (rest (rest (rest (rest t)))))))

; Get the write-stack cell from a type struct
(def type-write-cell
  (fn (_ t) (rest (rest (rest (type-io t))))))

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

; Push a handler onto a type's analyse stack
(def type-push-analyse
  (fn (_ ts handler)
    (let ((c (type-analyse-cell ts)))
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

; provide x/type — registered by x-core.x after module system loads
; Exports: type-alist type-by-atom type-io type-cvt
;   type-write-cell type-analyse-cell type-from-cell type-to-cell
;   type-push-write type-pop-write type-push-analyse type-cast!
