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
  (fn ()
    (first (first (first (first (rest (first (%base)))))))))

; Look up a type struct by its handle atom (from type-of)
(def type-by-atom
  (fn (handle)
    (def %go (fn (al)
      (if (null? al) ()
        (if (eq? (first (first al)) handle)
          (rest (first al))
          (%go (rest al))))))
    (%go (type-alist))))

; --- Field access ---

; Navigate to IO group (6th element)
(def type-io
  (fn (t) (first (rest (rest (rest (rest (rest t))))))))

; Navigate to CVT group (5th element)
(def type-cvt
  (fn (t) (first (rest (rest (rest (rest t)))))))

; Get the write-stack cell from a type struct
(def type-write-cell
  (fn (t) (rest (rest (rest (type-io t))))))

; Get the analyse-stack cell from a type struct
(def type-analyse-cell
  (fn (t) (type-io t)))

; Get the from-conversion cell from a type struct
(def type-from-cell
  (fn (t) (type-cvt t)))

; Get the to-conversion cell from a type struct
(def type-to-cell
  (fn (t) (rest (type-cvt t))))

; --- Stack manipulation ---

; Push a handler onto a type's write stack
(def type-push-write
  (fn (ts handler)
    (let ((c (type-write-cell ts)))
      (set-first! c (pair handler (first c))))))

; Pop the top handler from a type's write stack
(def type-pop-write
  (fn (ts)
    (let ((c (type-write-cell ts)))
      (set-first! c (rest (first c))))))

; Push a handler onto a type's analyse stack
(def type-push-analyse
  (fn (ts handler)
    (let ((c (type-analyse-cell ts)))
      (set-first! c (pair handler (first c))))))

; provide x/type — registered by x-core.x after module system loads
; Exports: type-alist type-by-atom type-io type-cvt
;   type-write-cell type-analyse-cell type-from-cell type-to-cell
;   type-push-write type-pop-write type-push-analyse
