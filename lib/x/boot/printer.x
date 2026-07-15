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
; Loads right after boot/string.x (needs number->str, str-append and the
; byte accessors at CALL time; and it re-defines string.x's variadic
; `display`, whose captured %display1 pointed at the C prim).

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
(def %print-is?
  (fn (_ o handle)
    (match
      ((eq? o ()) #f)
      (#t (eq? (%print-type-of o) handle)))))
(def %print-path-write         (%reflect-path (lit type-write) %base-paths))
(def %print-path-display       (%reflect-path (lit type-display) %base-paths))
(def %print-path-write-stack   (%reflect-path (lit type-write-stack) %base-paths))
(def %print-path-display-stack (%reflect-path (lit type-display-stack) %base-paths))

; --- generic sentinel-atom form: #<ATOM:0x{value-hex}> ---
(def %print-generic
  (fn (_ o)
    (do
      (%print-emit "#<ATOM:0x")
      (%print-emit (number->str (first-int o) 16))
      (%print-emit ">"))))

; --- the string escaper (write mode): "..." with \" \\ \n \t \r and \xHH ---
(def %print-str-esc-byte
  (fn (_ b)
    (match
      ((eq? b 34) "\\\"")
      ((eq? b 92) "\\\\")
      ((eq? b 10) "\\n")
      ((eq? b 9)  "\\t")
      ((eq? b 13) "\\r")
      ((< b 32)
        (match
          ((< b 16) (%str-append "\\x0" (number->str b 16)))
          (#t (%str-append "\\x" (number->str b 16)))))
      (#t ()))))
(def %print-str-w-loop
  (fn (self s i n)
    (match
      ((>= i n) ())
      (#t (do
        (def %e (%print-str-esc-byte (%str-byte-ref s i)))
        (match
          ((eq? %e ()) (%print-emit (%str-byte-sub s i 1)))
          (#t (%print-emit %e)))
        (self s (+ i 1) n))))))
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
          (def %tail (rest o))
          (match
            ((eq? %tail ()) #f)
            ((%print-is? %tail %print-list-handle)
              (match
                ((eq? (rest %tail) ())
                  (do
                    (def %p (%print-quasi-prefix (first o)))
                    (match
                      ((eq? %p ()) #f)
                      (#t (do (%print-emit %p) (render (first %tail)) #t)))))
                (#t #f)))
            (#t #f))))
      (#t #f))))

; --- walkers: proper/dotted lists and structural pairs ---
; C shape: "(" elem { " " elem } [ " . " tail ] ")", nil elements as "()".
(def %print-seq-loop
  (fn (self o render tail?)
    (do
      (render (first o))
      (def %tail (rest o))
      (match
        ((eq? %tail ()) (%print-emit ")"))
        ((tail? %tail)
          (do (%print-emit " ") (self %tail render tail?)))
        (#t (do
          (%print-emit " . ")
          (render %tail)
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
(def %print-cell
  (fn (_ o path fallback-path)
    (do
      (def %t (%print-tree (%print-type-of o)))
      (def %h (match ((eq? %t ()) ()) (#t (%reflect-step %t path))))
      (def %h2 (match
        ((eq? %h ()) (match ((eq? %t ()) ()) ((eq? fallback-path ()) ())
                            (#t (%reflect-step %t fallback-path))))
        (#t %h)))
      (match
        ((eq? %h2 ()) (%print-generic o))
        (#t (do (apply %h2 (pair o ())) ()))))))
(def %print-w
  (fn (_ o)
    (match
      ((eq? o ()) (%print-emit "()"))
      ((eq? o #t) (%print-emit "#t"))
      ((eq? o #f) (%print-emit "#f"))
      (#t (do
        (def %tw (%reflect-type-word o))
        (match
          ((eq? %tw 0) ())
          ((eq? %tw %reflect-satom-tw) (%print-generic o))
          ((eq? %tw %reflect-spair-tw) (%print-spair o %print-w))
          (#t (%print-cell o %print-path-write ()))))))))
(def %print-d
  (fn (_ o)
    (match
      ((eq? o ()) (%print-emit "()"))
      ((eq? o #t) (%print-emit "#t"))
      ((eq? o #f) (%print-emit "#f"))
      (#t (do
        (def %tw (%reflect-type-word o))
        (match
          ((eq? %tw 0) ())
          ((eq? %tw %reflect-satom-tw) (%print-generic o))
          ((eq? %tw %reflect-spair-tw) (%print-spair o %print-d))
          (#t (%print-cell o %print-path-display %print-path-write))))))))

; --- default cell handlers for the built-ins, pushed like any handler ---
; Drop a path's final step: descriptor paths END at the slot VALUE (the
; handler list); mutation needs the PARENT node whose first IS that slot.
(def %print-path-parent
  (fn (self p)
    (match
      ((eq? (rest p) ()) ())
      (#t (pair (first p) (self (rest p)))))))
(def %print-push!
  (fn (_ handle stack-path handler)
    (do
      (def %node (%reflect-step (%print-tree handle) (%print-path-parent stack-path)))
      (set-first! %node (pair handler (first %node))))))
(def %print-int-h  (fn (_ o) (%print-emit (number->str o))))
(def %print-str-wh (fn (_ o) (%print-str-w o)))
(def %print-str-dh (fn (_ o) (%print-emit o)))
(def %print-sym-wh
  (fn (_ o) (do (%print-emit "(lit ") (%print-emit (symbol->str o)) (%print-emit ")"))))
(def %print-sym-dh (fn (_ o) (%print-emit (symbol->str o))))
(def %print-list-wh (fn (_ o) (%print-list o %print-w)))
(def %print-list-dh (fn (_ o) (%print-list o %print-d)))
(%print-push! (%print-type-of 0)        %print-path-write-stack   %print-int-h)
(%print-push! (%print-type-of 0)        %print-path-display-stack %print-int-h)
(%print-push! (%print-type-of "")       %print-path-write-stack   %print-str-wh)
(%print-push! (%print-type-of "")       %print-path-display-stack %print-str-dh)
(%print-push! (%print-type-of (lit q))  %print-path-write-stack   %print-sym-wh)
(%print-push! (%print-type-of (lit q))  %print-path-display-stack %print-sym-dh)
(%print-push! (%print-type-of (lit (0))) %print-path-write-stack   %print-list-wh)
(%print-push! (%print-type-of (lit (0))) %print-path-display-stack %print-list-dh)

; --- to-str: swap the sink for a collector, render, restore, join ---
(def %print-join
  (fn (self parts acc)
    (match
      ((eq? parts ()) acc)
      (#t (self (rest parts) (%str-append (first parts) acc))))))
(def %print-to-str
  (fn (_ o render)
    (do
      (def %parts (pair () ()))
      (def %old (first %print-sink))
      (set-first! %print-sink
        (fn (_ s) (set-first! %parts (pair s (first %parts)))))
      (guard (e (do (set-first! %print-sink %old) (error e)))
        (render o))
      (set-first! %print-sink %old)
      (%print-join (first %parts) ""))))

; --- the public surface: catalog entries + the bare verbs ---
(def %print-display1 (fn (_ o) (%print-d o) ()))
(def %print-write1   (fn (_ o) (%print-w o) ()))
(prim-reg! (lit io) (lit display)        %print-display1)
(prim-reg! (lit io) (lit write)          %print-write1)
(prim-reg! (lit io) (lit display-to-str) (fn (_ o) (%print-to-str o %print-d)))
(prim-reg! (lit io) (lit write-to-str)   (fn (_ o) (%print-to-str o %print-w)))
; The bare verbs: write is unary; display keeps string.x's variadic shape
; (its captured %display1 pointed at the retired C prim).
; The bare verbs are OPS, not fns: the repl's print seat calls them between
; a form's eval and the next form's READ, and an X fn there (save-stack push
; + env save/restore) corrupts reader-lambda state under x-base (hex mis-
; analyses; see the printer-batch notes).  An op call leaves the seat clean.
(def write (op (%w-o) %w-e (do (%print-w (eval %w-o %w-e)) ())))
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

