; convert.x -- Register core type conversion handlers
;
; Adds from/to conversion alists directly to C built-in type structs,
; so (convert value type . extra-args) works for core types through
; the standard C dispatch.
;
; Usage: (convert value type-handle . extra-args)
;   (convert 65 %char)           -> #\A
;   (convert #\A %int)           -> 65
;   (convert 42 %string)         -> "42"
;   (convert 255 %string 16)     -> "ff"
;   (convert "42" %int)          -> 42
;   (convert "ff" %int 16)       -> 16 parsed as hex

; --- Type struct navigation ---
; Layout: (name-stack data-stack heap-group proc-group cvt-group io-group iter-group)
; cvt-group: (from-stack to-stack)
; each stack: (current . saved)

; Get type struct from type alist by handle atom
(def %type-alist
  (fn ()
    (first (first (first (first (rest (first (%base)))))))))

(def %type-lookup
  (fn (handle)
    (def %go
      (fn (alist)
        (if (null? alist) ()
          (if (eq? (first (first alist)) handle)
            (rest (first alist))
            (%go (rest alist))))))
    (%go (%type-alist))))

; Navigate to cvt group (5th element)
(def %type-cvt
  (fn (ts) (first (rest (rest (rest (rest ts)))))))

; from-stack cell (first of cvt)
(def %type-from-cell
  (fn (ts) (first (%type-cvt ts))))

; to-stack cell (first of rest of cvt)
(def %type-to-cell
  (fn (ts) (first (rest (%type-cvt ts)))))

; Set the from alist on a type struct
(def %type-set-from!
  (fn (ts alist) (set-first! (%type-from-cell ts) alist)))

; Set the to alist on a type struct
(def %type-set-to!
  (fn (ts alist) (set-first! (%type-to-cell ts) alist)))

; --- Type handles ---
(def %int    (type-of 0))
(def %char   (type-of (integer->char 0)))
(def %string (type-of ""))
(def %symbol (type-of (lit x)))
(def %ptr    (type-of (int->ptr 0)))
(def %pair   (type-of (list 0)))

; --- Register from alists (inbound conversions) ---

; INT: from char, string, ptr
(%type-set-from! (%type-lookup %int)
  (list
    (pair %char   (fn (v . extra) (char->integer v)))
    (pair %string (fn (v . extra)
                    (if (null? extra)
                      (string->number v)
                      (string->number v (first extra)))))
    (pair %ptr    (fn (v . extra) (ptr->int v)))))

; CHAR: from int
(%type-set-from! (%type-lookup %char)
  (list
    (pair %int (fn (v . extra) (integer->char v)))))

; STRING: from int, symbol, list (nil type-of)
(%type-set-from! (%type-lookup %string)
  (list
    (pair %int    (fn (v . extra)
                    (if (null? extra)
                      (number->string v)
                      (number->string v (first extra)))))
    (pair %symbol (fn (v . extra) (symbol->string v)))
    (pair %pair   (fn (v . extra) (list->string v)))))

; SYMBOL: from string
(%type-set-from! (%type-lookup %symbol)
  (list
    (pair %string (fn (v . extra) (string->symbol v)))))

; PTR: from int, string, any (obj->ptr as wildcard)
(%type-set-from! (%type-lookup %ptr)
  (list
    (pair %int    (fn (v . extra) (int->ptr v)))
    (pair %string (fn (v . extra) (string->ptr v)))
    (pair %ptr    (fn (v . extra) v))
    (pair #t (fn (v . extra) (obj->ptr v)))))
