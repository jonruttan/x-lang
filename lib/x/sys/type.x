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

; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-ref-word (prim-ref (lit ptr) (lit ref-word)))
(def %ptr-set-word! (prim-ref (lit ptr) (lit set-word!)))


; --- Type struct navigation ---
; Every walk below is derived at MODULE LOAD from the committed layout
; descriptor (tools/base-paths.x) via registry.x's walker -- a layout
; change follows the contract automatically; nothing here re-flattens the
; tree by hand.  Group accessors resolve their row's full step list; each
; *-cell resolves the PARENT of the row naming the value it fronts (via
; the shared %reflect-path-parent, exactly like the printer's handler
; pushes), because set-first! on that parent is what replaces the value.
; Load-time resolution is safe: %base-paths is a boot-time literal, and
; the type-* rows are rooted at the type-tree ARGUMENT, not the base.
(def %type-parent-path
  (fn (_ name) (%reflect-path-parent (%reflect-path name %base-paths))))

; Return the interpreter's type alist from the base object: row type-alist
; ends at the base CELL; the alist is its first.  Walked from (%base) per
; call, as the C prim did (only the step list is cached).
(def %type-alist-path (%reflect-path (lit type-alist) %base-paths))
(def %type-alist
  (fn (_ )
    (first (%reflect-step (%base) %type-alist-path))))

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

; Navigate to IO group (row type-io)
(def %type-io-path (%reflect-path (lit type-io) %base-paths))
(def %type-io
  (fn (_ t) (%reflect-step t %type-io-path)))

; Navigate to CVT group (row type-cvt)
(def %type-cvt-path (%reflect-path (lit type-cvt) %base-paths))
(def %type-cvt
  (fn (_ t) (%reflect-step t %type-cvt-path)))

; Navigate to PROC group (row type-proc): (call-stack eval-stack).
; NOT %type-proc: boot's predicates.x owns that name (the FN type handle
; backing procedure?), and this file loads after it -- a same-named def here
; clobbers the handle and breaks procedure? everywhere.
(def %type-proc-path (%reflect-path (lit type-proc) %base-paths))
(def %type-proc-group
  (fn (_ t) (%reflect-step t %type-proc-path)))

; The write-stack cell of a type struct: parent of row type-write-stack.
(def %type-write-cell-path (%type-parent-path (lit type-write-stack)))
(def %type-write-cell
  (fn (_ t) (%reflect-step t %type-write-cell-path)))

; The display-stack cell: parent of row type-display-stack.
(def %type-display-cell-path (%type-parent-path (lit type-display-stack)))
(def %type-display-cell
  (fn (_ t) (%reflect-step t %type-display-cell-path)))

; The analyse-stack cell: parent of row type-analyse-stack (the IO group
; node itself -- analyse is the group's first slot).
(def %type-analyse-cell-path (%type-parent-path (lit type-analyse-stack)))
(def %type-analyse-cell
  (fn (_ t) (%reflect-step t %type-analyse-cell-path)))

; The from-conversion cell: parent of row type-from (the cvt rows name the
; VALUE alist; its parent is the cell set-first! replaces).
(def %type-from-cell-path (%type-parent-path (lit type-from)))
(def %type-from-cell
  (fn (_ t) (%reflect-step t %type-from-cell-path)))

; The to-conversion cell: parent of row type-to.
(def %type-to-cell-path (%type-parent-path (lit type-to)))
(def %type-to-cell
  (fn (_ t) (%reflect-step t %type-to-cell-path)))

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

; The call-stack cell of a type: parent of row type-call-stack (the proc
; group node itself -- call is the group's first slot).
(def %type-call-cell-path (%type-parent-path (lit type-call-stack)))
(def %type-call-cell
  (fn (_ t) (%reflect-step t %type-call-cell-path)))

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

; The delimit-stack cell: parent of row type-delimit-stack.
(def %type-delimit-cell-path (%type-parent-path (lit type-delimit-stack)))
(def %type-delimit-cell
  (fn (_ t) (%reflect-step t %type-delimit-cell-path)))

; The read-stack cell: parent of row type-read-stack.
(def %type-read-cell-path (%type-parent-path (lit type-read-stack)))
(def %type-read-cell
  (fn (_ t) (%reflect-step t %type-read-cell-path)))

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

; The iter-stack cell: parent of row type-iter-stack (the iter group node).
(def %type-iter-cell-path (%type-parent-path (lit type-iter-stack)))
(def %type-iter-cell
  (fn (_ t) (%reflect-step t %type-iter-cell-path)))

; Push a handler onto a type's iter stack -- sets how (iter obj) builds an
; iterator for this type.  The handler is (fn (_ obj) -> iterator), e.g. via
; make-iter; (iter obj) calls it with the object.
(def %type-push-iter
  (fn (_ ts handler)
    (let ((c (%type-iter-cell ts)))
      (set-first! c (pair handler (first c))))))

; --- Generic-operator dispatch (ops group: 8th element, past iter) ---

; The ops cell (the ((op-sym . handler) ...) alist stack cell): parent of
; row type-ops (the VALUE alist; its parent is what set-first! replaces).
(def %type-ops-cell-path (%type-parent-path (lit type-ops)))
(def %type-ops-cell
  (fn (_ t) (%reflect-step t %type-ops-cell-path)))

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
    (def %dst-ptr (%obj->ptr obj))
    (def %src-ptr (%obj->ptr type-src))
    (def %type-val (%ptr-ref-word %src-ptr %type-offset))
    (%ptr-set-word! %dst-ptr %type-offset %type-val)
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
