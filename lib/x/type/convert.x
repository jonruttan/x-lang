; convert.x -- Generic type conversion: the registered dispatcher + the
; Convert class.
;
; Three concerns, one mechanism each:
;   - The TYPE SYSTEM carries the data: each type struct's cvt group holds a
;     from-alist (source-type -> converter) and a to-alist (target-type ->
;     converter), set with the %type-set-from!/%type-set-to! helpers below.
;   - The CATALOG carries the implementation: %convert-to is registered as
;     (convert . to); hot consumers (the tower's coercions, reader and write
;     handlers) fetch-and-cache it at module load:
;       (def %cvt (prim-ref (lit convert) (lit to)))
;   - The Convert CLASS is the API: (Convert to val target . extra) for cold
;     call sites, and the no-match POLICY as the class-wide member `missing`.
;
; The no-match policy is the dialect's call, not the mechanism's (SoC):
;   (Convert missing)                      -- read the handler
;   (Convert missing (fn (_ v tgt) ...))   -- set it: raise, coerce, log, ...
; The default handler returns () -- the historical contract. A type wanting
; totality instead registers a #t wildcard in its own from-alist (see PTR
; below); the wildcard dispatches as a conversion, so it wins over the miss
; handler.
;
; Lookup order: identity (already the target type), exact source match in the
; target's from-alist, the target's #t wildcard, target match in the source's
; to-alist, then (Convert missing). A nil VALUE converts to nil (absence stays
; absence; see the nil-handling specs).
;
; Type handles: %int, %char, %string, %symbol, %ptr, %pair
;
; Registered conversions:
;   INT  <- char (char->integer), string (str->number), ptr (%ptr->int)
;   CHAR <- int (integer->char)
;   STR  <- int (number->str), symbol (symbol->str), list (list->str),
;           ptr (%ptr->str)
;   SYM  <- string (%str->symbol)
;   PTR  <- int (int->ptr), string (%str->ptr), any (%obj->ptr)
;
; Examples:
;   (Convert to 65 %char)        -> #\A
;   (Convert to #\A %int)        -> 65
;   (Convert to 255 %string 16)  -> "ff"
;   (Convert to "ff" %int 16)    -> 255 (hex parse)

; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %type-of (prim-ref (lit type) (lit of)))

; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref (lit char) (lit ->int)))
(def %integer->char (prim-ref (lit int) (lit ->char)))
(def %int->ptr (prim-ref (lit int) (lit ->ptr)))

; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr->int (prim-ref (lit ptr) (lit ->int)))
(def %ptr->str (prim-ref (lit ptr) (lit ->str)))

(import x/type/class)
; Fetch the raw-object prims from the catalog (ns `obj` is de-registered, R5).
(def %obj->ptr (prim-ref (lit obj) (lit ->ptr)))

; Fetch the string prims from the catalog (ns `str` is de-registered, R5).
(def %str->symbol (prim-ref (lit str) (lit ->sym)))
(def %str->ptr (prim-ref (lit str) (lit ->ptr)))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-from-cell (prim-ref (lit type) (lit from-cell)))
(def %type-to-cell (prim-ref (lit type) (lit to-cell)))


; --- Type navigation via type.x (loaded before us) ---

; Set the from alist on a type struct
(def %type-set-from!
  (fn (_ ts alist) (set-first! (%type-from-cell ts) alist)))

; Set the to alist on a type struct
(def %type-set-to!
  (fn (_ ts alist) (set-first! (%type-to-cell ts) alist)))

; --- Type handles ---
(def %int    (%type-of 0))
(def %char   (%type-of (%integer->char 0)))
(def %string (%type-of ""))
(def %symbol (%type-of (lit x)))
(def %ptr    (%type-of (%int->ptr 0)))
(def %pair   (%type-of (list 0)))

; --- Register from alists (inbound conversions) ---

; INT: from char, string, ptr
(%type-set-from! (%type-by-atom %int)
  (list
    (pair %char   (fn (_ v . extra) (%char->integer v)))
    (pair %string (fn (_ v . extra)
                    (if (null? extra)
                      (str->number v)
                      (str->number v (first extra)))))
    (pair %ptr    (fn (_ v . extra) (%ptr->int v)))))

; CHAR: from int
(%type-set-from! (%type-by-atom %char)
  (list
    (pair %int (fn (_ v . extra) (%integer->char v)))))

; STRING: from int, symbol, list (nil type-of), ptr (copies the C string,
; so FFI results like getenv survive; inverse of PTR <- string below)
(%type-set-from! (%type-by-atom %string)
  (list
    (pair %int    (fn (_ v . extra)
                    (if (null? extra)
                      (number->str v)
                      (number->str v (first extra)))))
    (pair %symbol (fn (_ v . extra) (symbol->str v)))
    (pair %pair   (fn (_ v . extra) (list->str v)))
    (pair %ptr    (fn (_ v . extra) (%ptr->str v)))))

; SYMBOL: from string
(%type-set-from! (%type-by-atom %symbol)
  (list
    (pair %string (fn (_ v . extra) (%str->symbol v)))))

; PTR: from int, string, any (%obj->ptr as wildcard -- the totality pattern:
; PTR opts out of the miss policy by accepting every source type)
(%type-set-from! (%type-by-atom %ptr)
  (list
    (pair %int    (fn (_ v . extra) (%int->ptr v)))
    (pair %string (fn (_ v . extra) (%str->ptr v)))
    (pair %ptr    (fn (_ v . extra) v))
    (pair #t (fn (_ v . extra) (%obj->ptr v)))))

; --- The dispatcher ---
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
(def %convert-to
  (fn (_ val target . extra)
    (if (null? val) ()
      (if (eq? (%type-of val) target) val
        (let ((source (%type-of val))
              (target-ts (%type-by-atom target))
              (entry ()))
          ; Exact match: source in target's from-alist
          (if (null? target-ts) ()
            (let ((from-al (first (%type-from-cell target-ts))))
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
              (let ((source-ts (%type-by-atom source)))
                (if (null? source-ts) ()
                  (let ((to-al (first (%type-to-cell source-ts))))
                    (if (null? to-al) ()
                      (set! entry (%alist-find to-al target)))))))
            ())
          ; Call converter: (fn (_ . val) . extra); a miss is the dialect's
          ; policy, not ours -- read it off the class (cold path only).
          (if (null? entry)
            ((Convert missing) val target)
            (apply (rest entry) (pair val extra))))))))

; Register the implementation: consumers fetch (convert . to) from the
; catalog instead of assuming an ambient name.
(prim-reg! (lit convert) (lit to) %convert-to)

; --- The API ---
(def-class Convert ()
  (static
    (missing (fn (_ val target) ())
      "No-match policy handler (fn (_ val target)). The dialect sets it -- raise, coerce, log, ... Default returns nil.")
    (method to (self (param val ANY "Value to convert")
                     (param target ANY "Target type handle (e.g. (Type of 0))")
                     . (param extra ANY "Converter-specific arguments (e.g. a radix)"))
      (doc "Convert VAL to the TARGET type via the type system's registered conversions."
        (returns ANY "The converted value; on no registered conversion, (Convert missing)'s result (default nil)"))
      (apply %convert-to (pair val (pair target extra))))))

(doc (provide x/type/convert Convert)
  (note "Hot consumers fetch the dispatcher from the catalog: (prim-ref 'convert 'to). The no-match policy is the (Convert missing) member.")
  "Generic type conversion: the Convert class over the type system's from/to alists.")
