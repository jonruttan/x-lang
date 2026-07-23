; type/io.x -- Io: the input/output surface.
;
; The C primitives live in src/x-prim/io.c (catalog ns `io`). ns `io` is
; DE-REGISTERED (R5) -- EXCEPT `write` and `display`, the universal output
; verbs, which stay bound bare via the C keep-list (x_prims_name_kept), the
; same treatment eq?/same? get. So both forms work for those two:
;   (display x)        (Io display x)
;   (write x)          (Io write x)
; The others (read, read-char, write-to-str, display-to-str, error-line,
; error-file, repl-read) have NO bare name; the Io class -- or a catalog fetch, for
; reader-context/hot code -- is the only surface. Reader-context callers
; (e.g. the %vector-read handler) must fetch-and-cache, never class-dispatch
; inside a tokenizer callback:
;   (def %read (prim-ref (lit io) (lit read)))

(import x/type/class)

(def-class Io ()
  (static
    (method write (self (param v ANY "Value to write"))
      (doc "Write a value in machine-readable form (strings quoted, etc.). Also available bare as the fundamental output verb."
        (returns ANY "nil"))
      ((prim-ref (lit io) (lit write)) v))
    (method display (self (param v ANY "Value to display"))
      (doc "Display a value in human-readable form (strings unquoted). Also available bare as the fundamental output verb."
        (returns ANY "nil"))
      ((prim-ref (lit io) (lit display)) v))
    (method read (self)
      (doc "Read and parse one expression from stdin."
        (returns ANY "The parsed expression, or () at end of input"))
      ((prim-ref (lit io) (lit read))))
    (method read-char (self)
      (doc "Read one character from stdin."
        (returns ANY "The character, or () at end of input"))
      ((prim-ref (lit io) (lit read-char))))
    (method write-to-str (self (param v ANY "Value to serialize"))
      (doc "Capture write output as a string (write form: strings quoted)."
        (returns STRING "The machine-readable rendering of V"))
      ((prim-ref (lit io) (lit write-to-str)) v))
    (method display-to-str (self (param v ANY "Value to serialize"))
      (doc "Capture display output as a string (display form: strings unquoted)."
        (returns STRING "The human-readable rendering of V"))
      ((prim-ref (lit io) (lit display-to-str)) v))
    (method error-line (self)
      (doc "The source line number where the most recent error was raised. Frozen at raise time, so it is accurate read from inside a guard handler; between errors it retains the last one (boot itself catches some, so it is rarely 0)."
        (returns INT "Line number"))
      ((prim-ref (lit io) (lit error-line))))
    (method error-file (self)
      (doc "The source file path where the most recent error was raised, or \"\" when it arose from stdin/REPL input rather than an included file. Frozen at raise time (see error-line)."
        (returns STRING "File path"))
      ((prim-ref (lit io) (lit error-file))))
    (method repl-read (self)
      (doc "Read one expression for the REPL, applying its read conventions."
        (returns ANY "The parsed expression"))
      ((prim-ref (lit io) (lit repl-read))))))

(doc (provide x/type/io Io)
  (note "ns `io` de-registered except write/display (kept bare via the keep-list); the other six are Io-only. Reader-context/hot callers fetch-and-cache.")
  "Input/output on the Io class: write/display (also bare), read/read-char, the to-string captures, and the REPL hooks.")
