; printer.x -- display/write rendering, pure X (bootstrap)
;
; The printer is POLICY -- how values look -- and policy lives in X.  The C
; layer keeps one OUT instruction: (io write-str), raw bytes to the current
; output.  Everything above it is here:
;
;   - the dispatch mirror of C's x_token_display/x_token_write: nil, #t/#f,
;     sentinel-typed atoms (#<ATOM:0x..>), structural pairs, then the type
;     CELL dispatch for everything tree-typed
;   - the default renderers for the built-in cell-dispatched types (int,
;     str, symbol, list), PUSHED onto their write/display stacks exactly
;     like any other handler -- so later pushes (ansi colors, char-io's
;     UTF-8 chars, tool overrides) stack above them unchanged
;   - display-to-str / write-to-str via a swappable SINK: handlers print by
;     calling display/write recursively, so capture is state, not plumbing
;
; Loads BEFORE boot/string.x (which resolves display/write from here); the
; number->str / str-append dependencies below are CALL-time only, and
; string.x loads immediately after -- before anything prints.

; --- the OUT door and the sink ---
(def %print-out (prim-ref (lit io) (lit write-str)))
; The sink box: (first %print-sink) is the current emitter, a fn of one
; string.  to-str swaps it for a collector; everything renders through it.
(def %print-sink (pair (fn (_ s) (%print-out s)) ()))
(def %print-emit (fn (_ s) ((first %print-sink) s)))

; --- type machinery (boot-level: contract paths + the registry walk) ---
(def %print-type-of (prim-ref (lit type) (lit of)))
(def %print-tree
  (fn (_ handle) (%registry-assoc-rest handle (first %reflect-type-alist-cell))))
; List/symbol checks are by type HANDLE (name-interned), not tag identity:
; C's islist compares the type NAME, so lists from OTHER bases (make-base
; children) must print as lists too -- their trees differ, their names
; intern to the same atom.
(def %print-list-handle (%print-type-of (lit (0))))
(def %print-sym-handle  (%print-type-of (lit q)))
; (type ?) IS this predicate: #f for nil, compares the type's NAME atom
; against the handle -- the cross-base name-matching property the note
; above needs.  Alias the C prim; no hand-rolled twin.
(def %print-is? (prim-ref (lit type) (lit ?)))
(def %print-path-write         (%reflect-path (lit type-write) %base-paths))
(def %print-path-display       (%reflect-path (lit type-display) %base-paths))
(def %print-path-write-stack   (%reflect-path (lit type-write-stack) %base-paths))
(def %print-path-display-stack (%reflect-path (lit type-display-stack) %base-paths))

; --- generic sentinel-atom form: #<ATOM:0x{value-hex}> ---
; For SENTINEL-tagged atoms only (their value word IS the payload).  A
; handler-less CELL instance must never come here: first-int on a
; zero-data-word instance reads past the allocation, and a slot-0 pointer
; is not a value -- those render via %print-obj-opaque below.
;
; ONE identity-known sentinel prints its PAYLOAD instead: the base's
; error atom (x_eval_error's delivery -- unbound symbols and every other
; C-raised error).  It is a nil-typed atom whose string is the error
; scratch buffer, so the generic form rendered the BUFFER POINTER --
; every C-raised error printed as the same #<ATOM:0x..>, carrying zero
; diagnostic signal while the message sat right there in the atom (#54).
; (error "msg") delivers a real STRING and never reaches this path; a
; make-base child's error atom is a different object and still renders
; generically.  The append prim reads the atom's bytes directly, exactly
; as guard handlers already do with (Str8 append "" e).
(def %print-error-atom (first (%reflect-base-cell (lit error-str))))
(def %print-same? (prim-ref (lit obj) (lit same?)))
(def %print-str-append (prim-ref (lit str) (lit append)))
(def %print-generic
  (fn (_ o)
    (match
      ((%print-same? o %print-error-atom)
        (%print-emit (%print-str-append "" o)))
      (#t
        (do
          (%print-emit "#<ATOM:0x")
          (%print-emit (%number->str (%first-int o) 16))
          (%print-emit ">"))))))
; Bounded opaque form for handler-less cell-typed instances: only the
; header-derived type NAME is read, never a data word.
(def %print-obj-opaque
  (fn (_ o)
    (do
      (%print-emit "#<obj:")
      (def %print-tn (%reflect-type-name o))
      (match
        ((eq? %print-tn ()) (%print-emit "?"))
        (#t (%print-emit %print-tn)))
      (%print-emit ">"))))

; --- the string escaper (write mode): "..." with \" \\ \n \t \r and \xHH ---
; C int ops, fetched once: these loops run PER BYTE of every written
; string, and the tower's arithmetic wrappers cost ~92 objects per op
; where the raw instruction costs ~5 (the prim-caching rule for heat).
(def %print-int+ (prim-ref (lit int) (lit +)))
(def %print-int- (prim-ref (lit int) (lit -)))
; The classifier, ordered for the COMMON case: a printable byte concludes
; safe in THREE compares (34 and 92 are the only escapes >= 32); it builds
; nothing, so run scanning discards no allocations.
(def %print-str-esc?
  (fn (_ b)
    (match
      ((eq? b 34) #t)
      ((eq? b 92) #t)
      (#t (< b 32)))))
; The escape string for a byte the classifier flagged (only ever called
; for those, so the >= 32 non-escapes never reach the \x arms).
(def %print-str-esc-byte
  (fn (_ b)
    (match
      ((eq? b 34) "\\\"")
      ((eq? b 92) "\\\\")
      ((eq? b 10) "\\n")
      ((eq? b 9)  "\\t")
      ((eq? b 13) "\\r")
      ((< b 16) (%str-append "\\x0" (%number->str b 16)))
      (#t (%str-append "\\x" (%number->str b 16))))))
; Emit whole SAFE RUNS, not bytes: scan ahead to the next byte needing an
; escape and emit the run with one %str-byte-sub (one allocation, one OUT
; call -- the door is an unbuffered write(2), so per-byte emission costs a
; syscall per byte of every written string).
(def %print-str-w-run-end
  (fn (self s i n)
    (match
      ((< i n)
        (match
          ((%print-str-esc? (%str-byte-ref s i)) i)
          (#t (self s (%print-int+ i 1) n))))
      (#t i))))
(def %print-str-w-loop
  (fn (self s i n)
    (match
      ((< i n)
        (match
          ((%print-str-esc? (%str-byte-ref s i))
            (do
              (%print-emit (%print-str-esc-byte (%str-byte-ref s i)))
              (self s (%print-int+ i 1) n)))
          (#t (do
            (def %print-run-end (%print-str-w-run-end s (%print-int+ i 1) n))
            (%print-emit (%str-byte-sub s i (%print-int- %print-run-end i)))
            (self s %print-run-end n)))))
      (#t ()))))
(def %print-str-w
  (fn (_ s)
    (do
      (%print-emit "\"")
      (%print-str-w-loop s 0 (%str-byte-len s))
      (%print-emit "\""))))

; --- quasi shorthand: (quasi x) -> `x, (unquote x) -> ,x, splicing -> ,@x ---
; Returns #t when it rendered o, #f to fall through to the list walker.
(def %print-quasi-prefix
  (fn (_ name)
    (match
      ((eq? name (lit quasi)) "`")
      ((eq? name (lit unquote)) ",")
      ((eq? name (lit unquote-splicing)) ",@")
      (#t ()))))
(def %print-quasi
  (fn (_ o render)
    (match
      ((%print-is? (first o) %print-sym-handle)
        (do
          (def %print-tl (rest o))
          (match
            ((eq? %print-tl ()) #f)
            ((%print-is? %print-tl %print-list-handle)
              (match
                ((eq? (rest %print-tl) ())
                  (do
                    (def %print-pfx (%print-quasi-prefix (first o)))
                    (match
                      ((eq? %print-pfx ()) #f)
                      (#t (do (%print-emit %print-pfx) (render (first %print-tl)) #t)))))
                (#t #f)))
            (#t #f))))
      (#t #f))))

; --- walkers: proper/dotted lists and structural pairs ---
; C shape: "(" elem { " " elem } [ " . " tail ] ")", nil elements as "()".
(def %print-seq-loop
  (fn (self o render tail?)
    (do
      (render (first o))
      (def %print-tl (rest o))
      (match
        ((eq? %print-tl ()) (%print-emit ")"))
        ((tail? %print-tl)
          (do (%print-emit " ") (self %print-tl render tail?)))
        (#t (do
          (%print-emit " . ")
          (render %print-tl)
          (%print-emit ")")))))))
(def %print-list-tail? (fn (_ o) (%print-is? o %print-list-handle)))
(def %print-spair-tail?
  (fn (_ o)
    (match
      ((eq? o ()) #f)
      (#t (eq? (%reflect-type-word o) %reflect-spair-tw)))))
(def %print-list
  (fn (_ o render)
    (match
      ((%print-quasi o render) ())
      (#t (do
        (%print-emit "(")
        (%print-seq-loop o render %print-list-tail?))))))
(def %print-spair
  (fn (_ o render)
    (do
      (%print-emit "(")
      (%print-seq-loop o render %print-spair-tail?))))

; --- the dispatch mirror (write, then display) ---
; A cell handler renders the value itself (calling display/write back for
; children); apply -- never a direct call -- so list-valued objects are not
; re-evaluated as forms.
; Resolve a handler from ONE tree: the path, then the fallback path
; (display falls back to write).  %reflect-step nil-propagates, so an
; empty stack or nil tree just answers nil.
(def %print-tree-h
  (fn (_ t path fallback-path)
    (do
      (def %print-hd (%reflect-step t path))
      (match
        ((eq? %print-hd ()) (match ((eq? fallback-path ()) ())
                            (#t (%reflect-step t fallback-path))))
        (#t %print-hd)))))
; Handler resolution is OWN-TREE-FIRST: the type word IS the tree pointer
; (mirrors C's x_obj_type dispatch), so a custom type registered in another
; base carries its own handlers with it -- and the common case costs one
; materialization instead of a type-of + alist walk.  The name-keyed alist
; lookup stays as the FALLBACK: a child base's BUILT-IN trees are bare (the
; parent's defaults were pushed only on the parent's trees), but their names
; intern to the same atoms, so the parent's handlers still apply.
; Top handler of a memoized stack-parent node, or nil.
(def %print-stack-top
  (fn (_ node)
    (match
      ((eq? node ()) ())
      (#t (do
        (def %print-st (first node))
        (match ((eq? %print-st ()) ()) (#t (first %print-st))))))))
(def %print-cell
  (fn (_ o tw path fallback-path)
    (do
      ; MEMO front: the four built-in types cover nearly every rendered
      ; value, and the descriptor walk costs ~400 objects per cell.  The
      ; memo maps tw -> the pre-resolved stack-PARENT node (spine-stable:
      ; %print-push! mutates it in place, so ansi/char-io pushes stay
      ; visible), read live per call.  Display falls back to the write
      ; stack, mirroring the walk's fallback-path.  A miss (custom/other
      ; types) takes the full walk below.
      ; same?, NEVER eq?, for path identity: paths are LISTS, and eq?
      ; compares first-pointers -- both paths start with the same
      ; interned step symbol, so eq? called them equal (display rendered
      ; through WRITE handlers; 12 specs red).
      (def %print-wr? (same? path %print-path-write))
      (def %print-mh (do
        (def %print-hd (%print-stack-top (%print-memo-node tw %print-wr?)))
        (match
          ((eq? %print-hd ()) (match
            (%print-wr? ())
            (#t (%print-stack-top (%print-memo-node tw #t)))))
          (#t %print-hd))))
      (match
        ((eq? %print-mh ()) (%print-cell-walk o tw path fallback-path))
        (#t (do (apply %print-mh (pair o ())) ()))))))
(def %print-cell-walk
  (fn (_ o tw path fallback-path)
    (do
      (def %print-own (%ptr->obj (%int->ptr tw)))
      (def %print-hd (match
        ; guard like reflect.x: only a spair-tagged word is a navigable tree
        ((eq? (%reflect-type-word %print-own) %reflect-spair-tw)
          (%print-tree-h %print-own path fallback-path))
        (#t ())))
      (def %print-hd2 (match
        ((eq? %print-hd ()) (%print-tree-h (%print-tree (%print-type-of o)) path fallback-path))
        (#t %print-hd)))
      (match
        ((eq? %print-hd2 ()) (%print-obj-opaque o))
        (#t (do (apply %print-hd2 (pair o ())) ()))))))
; ONE dispatch body for both modes (write and display differ only in the
; path pair handed to the cell dispatch); %print-w/%print-d stay as named
; fronts because handlers and walkers reference them.  `self` is the
; recursion knot -- children render in the SAME mode.
; Booleans by same? (object identity), NEVER eq?: eq? compares value words,
; and any scalar whose word collides with #t's -- e.g. (%first-int #t) -- would
; render as a boolean.  #t/#f are singletons, so identity is exact (mirrors
; C's pointer compare against the base true/false objects).
(def %print-render
  (fn (_ o self path fallback-path)
    (match
      ((eq? o ()) (%print-emit "()"))
      ((same? o #t) (%print-emit "#t"))
      ((same? o #f) (%print-emit "#f"))
      (#t (do
        (def %print-tw (%reflect-type-word o))
        (match
          ((eq? %print-tw 0) ())
          ((eq? %print-tw %reflect-satom-tw) (%print-generic o))
          ((eq? %print-tw %reflect-spair-tw) (%print-spair o self))
          (#t (%print-cell o %print-tw path fallback-path))))))))
(def %print-w
  (fn (self o) (%print-render o self %print-path-write ())))
(def %print-d
  (fn (self o) (%print-render o self %print-path-display %print-path-write)))

; --- default cell handlers for the built-ins, pushed like any handler ---
; Descriptor paths END at the slot VALUE (the handler list); mutation needs
; the PARENT node whose first IS that slot -- registry.x's shared
; %reflect-path-parent derives it (hoisted to registry.x -- the single
; cell-from-slot derivation point shared with sys/type.x and reflect.x).
(def %print-push!
  (fn (_ handle stack-path handler)
    (do
      (def %print-nd (%reflect-step (%print-tree handle) (%reflect-path-parent stack-path)))
      (%set-first! %print-nd (pair handler (first %print-nd))))))
(def %print-int-h  (fn (_ o) (%print-emit (%number->str o))))
(def %print-str-dh (fn (_ o) (%print-emit o)))
; Symbols WRITE with the quote shorthand -- 'x, not (lit x) -- so the echo
; is what you would type and pastes back re-readably (#45 R1). The reader
; half of ' lives in lit-reader.x; this is the writer half that was missing.
(def %print-sym-wh
  (fn (_ o) (do (%print-emit "'") (%print-emit (symbol->str o)))))
(def %print-sym-dh (fn (_ o) (%print-emit (symbol->str o))))
(def %print-list-wh (fn (_ o) (%print-list o %print-w)))
(def %print-list-dh (fn (_ o) (%print-list o %print-d)))
(%print-push! (%print-type-of 0)        %print-path-write-stack   %print-int-h)
(%print-push! (%print-type-of 0)        %print-path-display-stack %print-int-h)
(%print-push! (%print-type-of "")       %print-path-write-stack   %print-str-w)
(%print-push! (%print-type-of "")       %print-path-display-stack %print-str-dh)
(%print-push! (%print-type-of (lit q))  %print-path-write-stack   %print-sym-wh)
(%print-push! (%print-type-of (lit q))  %print-path-display-stack %print-sym-dh)
(%print-push! (%print-type-of (lit (0))) %print-path-write-stack   %print-list-wh)
(%print-push! (%print-type-of (lit (0))) %print-path-display-stack %print-list-dh)

; --- the dispatch memo: tw -> pre-resolved stack-parent nodes ---
; Resolved ONCE here for the four built-in types.  Safe to cache: the
; nodes are reachable from the type alist (marked live, never moved by
; the non-moving sweep) and %print-push! only ever set-first!s them.
(def %print-wstack-parent (%reflect-path-parent %print-path-write-stack))
(def %print-dstack-parent (%reflect-path-parent %print-path-display-stack))
(def %print-node-of
  (fn (_ handle parent-path)
    (%reflect-step (%print-tree handle) parent-path)))
(def %print-int-tw  (%reflect-type-word 0))
(def %print-str-tw  (%reflect-type-word ""))
(def %print-symq-tw (%reflect-type-word (lit q)))
(def %print-listq-tw (%reflect-type-word (lit (0))))
(def %print-int-wnode  (%print-node-of (%print-type-of 0)        %print-wstack-parent))
(def %print-int-dnode  (%print-node-of (%print-type-of 0)        %print-dstack-parent))
(def %print-str-wnode  (%print-node-of (%print-type-of "")       %print-wstack-parent))
(def %print-str-dnode  (%print-node-of (%print-type-of "")       %print-dstack-parent))
(def %print-sym-wnode  (%print-node-of (%print-type-of (lit q))  %print-wstack-parent))
(def %print-sym-dnode  (%print-node-of (%print-type-of (lit q))  %print-dstack-parent))
(def %print-list-wnode (%print-node-of (%print-type-of (lit (0))) %print-wstack-parent))
(def %print-list-dnode (%print-node-of (%print-type-of (lit (0))) %print-dstack-parent))
(def %print-memo-node
  (fn (_ tw write?)
    (match
      ((eq? tw %print-int-tw)   (match (write? %print-int-wnode)  (#t %print-int-dnode)))
      ((eq? tw %print-str-tw)   (match (write? %print-str-wnode)  (#t %print-str-dnode)))
      ((eq? tw %print-symq-tw)  (match (write? %print-sym-wnode)  (#t %print-sym-dnode)))
      ((eq? tw %print-listq-tw) (match (write? %print-list-wnode) (#t %print-list-dnode)))
      (#t ()))))

; --- the opaque types: fixed #<...> forms (write; display falls back) ---
; These replace the C write handlers of the same seven types (deleted with
; the print stack).  Their handles are C-STATIC name atoms, not reader
; symbols -- (lit PROCEDURE) does NOT intern to them -- so resolve each by
; NAME BYTES against the type-alist keys.  Load-time only; the byte prims
; are fetched here because string.x loads after this file.
(def %print-byte-len (prim-ref (lit str) (lit byte-len)))
(def %print-byte-ref (prim-ref (lit str) (lit byte-ref)))
(def %print-name-eq-loop
  (fn (self a b i n)
    (match
      ((eq? i n) #t)
      ((eq? (%print-byte-ref a i) (%print-byte-ref b i)) (self a b (+ i 1) n))
      (#t #f))))
(def %print-name=?
  (fn (_ a b)
    (match
      ((eq? (%print-byte-len a) (%print-byte-len b))
        (%print-name-eq-loop a b 0 (%print-byte-len a)))
      (#t #f))))
(def %print-handle-by-name
  (fn (self s cur)
    (match
      ((eq? cur ()) ())
      ((%print-name=? (%reflect-sym->str (first (first cur))) s) (first (first cur)))
      (#t (self s (rest cur))))))
(def %print-opaque!
  (fn (_ name form)
    (do
      (def %print-hd (%print-handle-by-name name (first %reflect-type-alist-cell)))
      (match
        ((eq? %print-hd ()) ())  ; type absent in this build -- %print-generic covers it
        (#t (%print-push! %print-hd %print-path-write-stack (fn (_ o) (%print-emit form))))))))
; ATOM registers lazily on first x_mkatom and nothing in-tree constructs
; one, so this push no-ops here; kept for embedders that pre-register it.
(%print-opaque! "ATOM"      "#<atom>")
(%print-opaque! "BUFFER"    "#<buffer>")
(%print-opaque! "POINTER"   "#<ptr>")
(%print-opaque! "PRIMITIVE" "#<prim>")
(%print-opaque! "ITER"      "#<iter>")
(%print-opaque! "PROCEDURE" "#<fn>")
(%print-opaque! "OPERATIVE" "#<op>")

; --- to-str: swap the sink for a collector, render, restore, join ---
; Parts accumulate REVERSED (collector prepends).  Join adjacent PAIRS per
; round -- O(bytes * log parts) copying, not the linear fold's
; O(bytes * parts).  The round is TAIL-recursive with an accumulator (a
; non-tail round burned one C frame per fragment pair -- write-to-str of a
; 10k-element list segfaulted); prepending to the accumulator REVERSES the
; list each round, so the join direction alternates with it (rev? tracks
; whether the current list is in reverse logical order).
(def %print-join-round
  (fn (self parts rev? acc)
    (match
      ((eq? parts ()) acc)
      ((eq? (rest parts) ()) (pair (first parts) acc))
      (#t (self (rest (rest parts)) rev?
            (pair (match
                    (rev? (%str-append (first (rest parts)) (first parts)))
                    (#t   (%str-append (first parts) (first (rest parts)))))
                  acc))))))
(def %print-join
  (fn (self parts rev?)
    (match
      ((eq? parts ()) "")
      ((eq? (rest parts) ()) (first parts))
      (#t (self (%print-join-round parts rev? ())
                (match (rev? #f) (#t #t)))))))
; The single-COLLECTED-part case copies: the collected object is the
; handler's emitted string ITSELF (or a printer literal like "#t"), and
; to-str's contract is a FRESH string -- returning the original let a
; caller's raw-mem poke mutate the source, or permanently corrupt the
; shared literal.  Multi-part joins are fresh by construction.
(def %print-to-str-finish
  (fn (_ parts)
    (match
      ((eq? parts ()) "")
      ((eq? (rest parts) ()) (%str-append (first parts) ""))
      (#t (%print-join parts #t)))))
; Collector state (%parts box, saved sink) rides PARAMETERS, never body
; defs: under the TCO trampoline a body def binds GLOBALLY (the save-stack
; frame is popped before the deferred tail form runs), so def'd state is
; shared across activations and a NESTED to-str (a handler rendering to a
; string mid-capture) corrupted the outer capture.  Params are
; per-activation.
(def %print-to-str-run
  (fn (_ o render %parts %old)
    (do
      (%set-first! %print-sink
        (fn (_ s) (%set-first! %parts (pair s (first %parts)))))
      (guard (e (do (%set-first! %print-sink %old) (error e)))
        (render o))
      (%set-first! %print-sink %old)
      (%print-to-str-finish (first %parts)))))
(def %print-to-str
  (fn (_ o render)
    (%print-to-str-run o render (pair () ()) (first %print-sink))))

; --- the public surface: catalog entries + the bare verbs ---
(def %print-display1 (fn (_ o) (%print-d o) ()))
(def %print-write1   (fn (_ o) (%print-w o) ()))
(prim-reg! (lit io) (lit display)        %print-display1)
(prim-reg! (lit io) (lit write)          %print-write1)
(prim-reg! (lit io) (lit display-to-str) (fn (_ o) (%print-to-str o %print-d)))
(prim-reg! (lit io) (lit write-to-str)   (fn (_ o) (%print-to-str o %print-w)))
; The bare verbs: write is unary; display is variadic (the shape the old
; string.x shim over the retired C prim established).
; The bare verbs are OPS, not fns: the repl's print seat calls them between
; a form's eval and the next form's READ, and an X fn there (save-stack push
; + env save/restore) corrupts reader-lambda state under x-base (hex mis-
; analyses; see the printer-batch notes).  An op call leaves the seat clean.
(def write (op (%w-o) %w-e (do (%print-w (eval %w-o %w-e)) ())))
; display evals ALL args BEFORE emitting anything (two passes, not one
; interleaved loop): the retired C prim's x_eargs did the same, so an error
; in a later arg prints NOTHING rather than a truncated line.  Semantics,
; not an accident -- don't fuse the loops.
(def %print-d-each
  (fn (self args)
    (match
      ((eq? args ()) ())
      (#t (do (%print-d (first args)) (self (rest args)))))))
(def display
  (op %d-args %d-e
    (do (%print-d-each (%print-eval-each %d-args %d-e)) ())))
(def %print-eval-each
  (fn (self args e)
    (match
      ((eq? args ()) ())
      (#t (pair (eval (first args) e) (self (rest args) e))))))

