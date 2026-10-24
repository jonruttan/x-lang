; source.x -- Source: where a form was read, by name.
;
; The reader stamps one object for each thing it reads with the line it
; began on and the file it came from, in the two meta words boot arms on
; every object: word 0 the line, word 1 the file id.  For a list that object
; is its first cell; the other cells are never stamped and hold whatever
; their allocation left, so a stamp is believed only when its line is above
; zero and its file id is one the loader filed, as the profiler believes it.
; A file id names an entry in the base's file-registry row, the alist of
; (id . path) that include grows, newest first, each id an integer atom; id
; 0 is standard input and has no entry.  The reader's live position is the
; base's line and file rows.
;
; A program the wrapper streams onto standard input, -c and -f alike, is
; read behind the wrapper's own forms, so its stamps are stream lines and
; its file is standard input.  A file reached by include carries its own
; lines and its path.
(module x/reader/source)

(import x/type/class)

(def-class Source ()
  (doc "Where a form was read: (Source line form) and (Source file form) read the stamp the reader left on it, (Source path id) and (Source files) read the registry of included files, and (Source here) is the reader's live position. A form built at run time carries no stamp and answers ()."
    (example "(Source path 0)" "\"\"")
    (example "(null? (Source line (list 1 2)))" "#t"))
  (static
    (method %meta (self o i)
      (doc "Meta word i of o, or 0 when o carries none.")
      ((prim-ref (lit obj) (lit meta-ref)) o i))
    (method %registry (self)
      (doc "The base's file registry: ((id-atom . path) ...), newest first.")
      (first (%reflect-base-cell (lit file-registry))))
    ; The path filed under id, or () when none is: the one lookup every
    ; reader below shares.  Id 0 is standard input, which has no entry.
    (method %path-of (self id)
      (doc "The path filed under id, \"\" for 0, () when none is.")
      (if (= id 0) ""
        (let go ((reg (Source %registry)))
          (match
            ((null? reg) ())
            ((= (%cell-int (first (first reg))) id) (rest (first reg)))
            (#t (go (rest reg)))))))
    ; A stamp is believed when its line is above zero and its file id is
    ; standard input or a file the loader filed; anything else is what the
    ; allocation left in an unstamped cell.
    (method %believed? (self form)
      (doc "Whether form carries a stamp the reader left, rather than leftover words.")
      (if (< 0 (Source %meta form 0))
        (not (null? (Source %path-of (Source %meta form 1))))
        #f))
    (method line (self (param form ANY "A form the reader read: a list's first cell carries the stamp"))
      (doc "The line form was read on, counted from 1 in the file include read it from, or in the stream for a program on standard input. () for a form built at run time, or for a list cell other than a form's first."
        (returns INTEGER "The line, or ()")
        (example "(null? (Source line (list 1 2)))" "#t"))
      (if (Source %believed? form) (Source %meta form 0) ()))
    (method file (self (param form ANY "A form the reader read"))
      (doc "The path of the file form was read from, \"\" when it was read from standard input, () for a form that carries no stamp."
        (returns STRING "A path, \"\", or ()")
        (example "(null? (Source file (list 1 2)))" "#t"))
      (if (Source %believed? form) (Source %path-of (Source %meta form 1)) ()))
    (method path (self (param id INTEGER "A file id, as a stamp's second word or a (Source files) entry carries it"))
      (doc "The path filed under a file id: \"\" for 0, standard input; () for an id no include filed."
        (returns STRING "A path, \"\", or ()")
        (example "(Source path 0)" "\"\"")
        (example "(null? (Source path 999999))" "#t"))
      (Source %path-of id))
    (method files (self)
      (doc "Every file include has filed, as an alist of (id . path) with integer ids, in the order they were filed."
        (returns LIST "An alist of (id . path)")
        (example "(number? (first (first (Source files))))" "#t"))
      ; The registry's cells are engine-built and answer #f to pair?, so
      ; the walk steps with first and rest and answers fresh pairs; the
      ; registry is newest first, and the walk reverses it on the way.
      (let go ((reg (Source %registry)) (acc ()))
        (if (null? reg) acc
          (go (rest reg)
              (pair (pair (%cell-int (first (first reg))) (rest (first reg))) acc)))))
    ; The live position rides the input buffer the reader is reading from:
    ; include stamps the buffer it pushes with line 1 and the file's id, and
    ; the reader advances the line word as it reads, which is also where
    ; each form's stamp is copied from.  The base's line and file rows are
    ; the engine's own counters for its standard input and do not follow an
    ; include.
    (method here (self)
      (doc "The reader's live position: (path . line), the file being read and the line of the form being read, \"\" for standard input. Evaluated while a file loads, it names that file and the line the form it appears in begins on."
        (returns PAIR "(path . line)")
        (example "(str? (first (Source here)))" "#t"))
      (def buf (first (%reflect-base-cell (lit buffer))))
      (pair (Source %path-of (Source %meta buf 1))
            (Source %meta buf 0)))))

(doc (provide x/reader/source Source)
  (note "Where a form was read: (Source line form), (Source file form); the registry of included files: (Source path id), (Source files); the reader's live position: (Source here).")
  (example "(Source path 0)" "\"\"")
  "Source: where a form was read -- the reader's line and file stamps, the registry of included files, and the reader's live position.")
