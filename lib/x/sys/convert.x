; convert.x -- Generic type conversion dispatch
;
; Provides (convert value target-type . extra-args) for core types.
; Loads before doc.x so cannot use (doc ...) annotations.
;
; The convert function looks up a converter in two places:
;   1. Target type's "from" alist — keyed by source type handle
;   2. Source type's "to" alist — keyed by target type handle
;   3. Wildcard (#t) in from-alist as fallback
;
; Type handles: %int, %char, %string, %symbol, %ptr, %pair
;
; Registered conversions:
;   INT  <- char (char->integer), string (str->number), ptr (ptr->int)
;   CHAR <- int (integer->char)
;   STR  <- int (number->str), symbol (symbol->str), list (list->str)
;   SYM  <- string (str->symbol)
;   PTR  <- int (int->ptr), string (str->ptr), any (obj->ptr)
;
; Examples:
;   (convert 65 %char)           -> #\A
;   (convert #\A %int)           -> 65
;   (convert 42 %string)         -> "42"
;   (convert 255 %string 16)     -> "ff"
;   (convert "42" %int)          -> 42
;   (convert "ff" %int 16)       -> 255 (hex parse)
;   (convert (lit foo) %string)  -> "foo"
;
; Exports: convert
; Registered by x-core.x after module system loads (no provide).

; --- Type navigation via type.x (loaded before us) ---

; Set the from alist on a type struct
(def %type-set-from!
  (fn (_ ts alist) (set-first! (type-from-cell ts) alist)))

; Set the to alist on a type struct
(def %type-set-to!
  (fn (_ ts alist) (set-first! (type-to-cell ts) alist)))

; --- Type handles ---
(def %int    (type-of 0))
(def %char   (type-of (integer->char 0)))
(def %string (type-of ""))
(def %symbol (type-of (lit x)))
(def %ptr    (type-of (int->ptr 0)))
(def %pair   (type-of (list 0)))

; --- Register from alists (inbound conversions) ---

; INT: from char, string, ptr
(%type-set-from! (type-by-atom %int)
  (list
    (pair %char   (fn (_ v . extra) (char->integer v)))
    (pair %string (fn (_ v . extra)
                    (if (null? extra)
                      (str->number v)
                      (str->number v (first extra)))))
    (pair %ptr    (fn (_ v . extra) (ptr->int v)))))

; CHAR: from int
(%type-set-from! (type-by-atom %char)
  (list
    (pair %int (fn (_ v . extra) (integer->char v)))))

; STRING: from int, symbol, list (nil type-of)
(%type-set-from! (type-by-atom %string)
  (list
    (pair %int    (fn (_ v . extra)
                    (if (null? extra)
                      (number->str v)
                      (number->str v (first extra)))))
    (pair %symbol (fn (_ v . extra) (symbol->str v)))
    (pair %pair   (fn (_ v . extra) (list->str v)))))

; SYMBOL: from string
(%type-set-from! (type-by-atom %symbol)
  (list
    (pair %string (fn (_ v . extra) (str->symbol v)))))

; PTR: from int, string, any (obj->ptr as wildcard)
(%type-set-from! (type-by-atom %ptr)
  (list
    (pair %int    (fn (_ v . extra) (int->ptr v)))
    (pair %string (fn (_ v . extra) (str->ptr v)))
    (pair %ptr    (fn (_ v . extra) v))
    (pair #t (fn (_ v . extra) (obj->ptr v)))))

; --- convert dispatch (replaces C primitive) ---
(def %alist-find
  (fn (self alist key)
    (if (null? alist) ()
      (if (eq? (first (first alist)) key)
        (first alist)
        (self (rest alist) key)))))

; Locals are bound with `let`, NOT `def`.  This body sits in the fn's tail
; position, and a `def` in a tail context runs *after* TCO has popped the
; closure frame -- so `def` would see an empty save-stack and bind GLOBALLY,
; silently clobbering any caller variable of the same name (e.g. a caller's
; `entry`).  `let` binds through parameters (a real frame), so source/entry/etc.
; stay local.  (See the def-in-tail-`do` scope hazard.)
(def convert
  (fn (_ val target . extra)
    (if (null? val) ()
      (if (eq? (type-of val) target) val
        (let ((source (type-of val))
              (target-ts (type-by-atom target))
              (entry ()))
          ; Exact match: source in target's from-alist
          (if (null? target-ts) ()
            (let ((from-al (first (type-from-cell target-ts))))
              (if (null? from-al) ()
                (do
                  (if (null? source) ()
                    (set! entry (%alist-find from-al source)))
                  ; Wildcard: #t key
                  (if (null? entry)
                    (set! entry (%alist-find from-al #t))
                    ())))))
          ; Outbound: target in source's to-alist
          (if (null? entry)
            (if (null? source) ()
              (let ((source-ts (type-by-atom source)))
                (if (null? source-ts) ()
                  (let ((to-al (first (type-to-cell source-ts))))
                    (if (null? to-al) ()
                      (set! entry (%alist-find to-al target)))))))
            ())
          ; Call converter: (fn (_ . val) . extra)
          (if (null? entry) ()
            (apply (rest entry) (pair val extra))))))))
