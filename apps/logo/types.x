; types.x -- Logo tokenizer base and type definitions
(import logo/state)
; Fetch the tokenizer prims from the catalog (ns `buf`/`tok` are de-registered, R5).
(def %buffer-token (prim-ref 'buf 'tok))
(def %token-read (prim-ref 'tok 'read))

; Fetch the type-system helpers from the catalog (registered by sys/type.x).
(def %type-io (prim-ref 'type 'io))

(import x/sys/token)
; Fetch the tokenizer terminators from the catalog (ns `token`). Reader-context
; states call these per character, so cache the raw refs and call them directly
; -- never (Token accept ...), whose dispatch would allocate mid-reader-callback.
(def %tok-accept (prim-ref 'token 'accept))
(def %tok-accept-inclusive (prim-ref 'token 'accept-inclusive))
(import x/type/str)
; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-instance (prim-ref 'type 'make-instance))
(def %make-type (prim-ref 'type 'make))
(def %type-of (prim-ref 'type 'of))
(def %type? (prim-ref 'type '?))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %char->integer (prim-ref 'char '->int))



; ============================================================
; Type helpers
; ============================================================

(def %logo-block-close (pair 'logo-block-close ()))
(def %logo-paren-tag 'logo-paren)

(def %logo-alpha?
  (fn (_ chr)
    (or (and (>= chr 65) (<= chr 90))
        (and (>= chr 97) (<= chr 122)))))

(def %logo-word-char?
  (fn (_ chr)
    (or (%logo-alpha? chr)
        (= chr 46)                        ; .
        (= chr 63)                        ; ?
        (and (>= chr 48) (<= chr 57))))) ; 0-9

(def %logo-word-continue
  (fn (self buffer score chr)
    (if (%logo-word-char? chr)
      self
      (%tok-accept buffer score chr))))

; Forward declarations (set! by dispatch.x/expr.x)
(def %logo ())
(def %logo-indent ())
(def %logo-block ())
(def %logo-op ())
(def %logo-string ())
(def logo-process-tokens ())
(def logo-process-to ())
(def %logo-vars ())
(def %logo-commands ())

; ============================================================
; Whitespace type detection
; ============================================================

(def %is-ws-type?
  (fn (_ entry)
    (def io (%type-io (rest entry)))
    (def delimit (first (first (rest io))))
    (def read-h (first (first (rest (rest io)))))
    (if (null? delimit) #f (null? read-h))))

; ============================================================
; Pre-allocated analyse state functions (avoid closure allocation)
; ============================================================

; Single-char operator: accept on next char
(def %logo-op-accept-next
  (fn (_ buffer score chr2)
    (%tok-accept buffer score chr2)))

; < followed by second char: accept-inclusive for <- <= <>, accept for others
(def %logo-op-lt-second
  (fn (_ buffer score chr2)
    (if (or (= chr2 45) (= chr2 61) (= chr2 62))
      (%tok-accept-inclusive buffer score chr2)
      (%tok-accept buffer score chr2))))

; > followed by second char: accept-inclusive for >=, accept for others
(def %logo-op-gt-second
  (fn (_ buffer score chr2)
    (if (= chr2 61)
      (%tok-accept-inclusive buffer score chr2)
      (%tok-accept buffer score chr2))))

; ============================================================
; Logo tokenizer base
; ============================================================

(def %logo-base
  (let ((base (Base make)))
    (def %cell (first (first (first (rest (first base))))))
    (def %int-name (%type-of 0))
    (def %float-name (%type-of (Float exact->inexact 0)))
    ; Keep only INTEGER and FLOAT from the base
    (def %filter
      (fn (self al)
        (if (null? al) ()
          (let ((name (first (first al))))
            (if (or (eq? name %int-name) (eq? name %float-name))
              (pair (first al) (self (rest al)))
              (self (rest al)))))))
    (set-first! %cell (%filter (first %cell)))

    ; LOGO-BLOCK
    (set! %logo-block
      (Base make-type base "LOGO-BLOCK"
        (list
          (pair 'write (fn (_ _) (display "[ ... ]")))
          (pair 'eval (fn (_ self) (logo-process-tokens (first self)))))))

    ; LOGO-CLOSE
    (Base make-type base "LOGO-CLOSE"
      (list
        (pair 'analyse
          (Token make-char-state (%char->integer #\]) %tok-accept ()))
        (pair 'read (fn (_ . args) %logo-block-close))))

    ; LOGO-OPEN
    (Base make-type base "LOGO-OPEN"
      (list
        (pair 'analyse
          (Token make-char-state (%char->integer #\[) %tok-accept ()))
        (pair 'read
          (fn (_ . args)
            (def buf (first args))
            (def %rb
              (fn (self acc)
                (def tok (%token-read buf))
                (if (null? tok)
                  (%make-instance %logo-block (reverse acc))
                  (if (eq? tok %logo-block-close)
                    (%make-instance %logo-block (reverse acc))
                    (self (pair tok acc))))))
            (%rb ())))))

    ; LOGO (word type)
    (set! %logo
      (Base make-type base "LOGO"
        (list
          (pair 'analyse
            (fn (_ buffer score chr)
              (if (%logo-alpha? chr) %logo-word-continue ())))
          (pair 'read
            (fn (_ . args)
              (%make-instance %logo (%buffer-token (first args)))))
          (pair 'write
            (fn (_ self) (display (first self)))))))

    ; LOGO-WS: spaces and tabs only, discard
    (Base make-type base "LOGO-WS"
      (list
        (pair 'analyse
          (fn (self buffer score chr)
            (if (or (= chr 32) (= chr 9))
              self
              (if (> (buffer-len buffer) 1)
                (do (buffer-unread buffer)
                    (score-set score 1 buffer))
                ()))))
        (pair 'delimit
          (fn (_ buffer score chr)
            (if (or (= chr 32) (= chr 9))
              (do (buffer-unread buffer) buffer)
              ())))))

    ; LOGO-NEWLINE: bare newline, discard
    (Base make-type base "LOGO-NEWLINE"
      (list
        (pair 'analyse
          (Token make-char-state 10 %tok-accept ()))))

    ; LOGO-INDENT: \n + spaces/tabs + word
    (def %indent-after-nl
      (fn (self buffer score chr)
        (if (or (= chr 32) (= chr 9))
          self
          (if (%logo-alpha? chr)
            %logo-word-continue
            ()))))

    (set! %logo-indent
      (Base make-type base "LOGO-INDENT"
        (list
          (pair 'analyse
            (fn (_ buffer score chr)
              (if (= chr 10) %indent-after-nl ())))
          (pair 'read
            (fn (_ . read-args)
              (def text (%buffer-token (first read-args)))
              (def len (str-length text))
              (def %count-indent
                (fn (self i)
                  (if (>= i len) i
                    (if (or (Char =? (str-ref text i) #\space)
                            (Char =? (str-ref text i) #\tab))
                      (self (+ i 1))
                      i))))
              (def indent-end (%count-indent 1))
              (def indent (- indent-end 1))
              (def word (substring text indent-end len))
              (%make-instance %logo-indent (pair indent word))))
          (pair 'write
            (fn (_ self)
              (display (first (rest (first self)))))))))

    ; LOGO-OP: operators and <- assignment
    (set! %logo-op
      (Base make-type base "LOGO-OP"
        (list
          (pair 'analyse
            (fn (_ buffer score chr)
              ; Single-char: + - * / ^ = ,
              (if (or (= chr 43) (= chr 45) (= chr 42) (= chr 47)
                      (= chr 94) (= chr 61) (= chr 44))
                %logo-op-accept-next
                ; < may continue with - = >
                (if (= chr 60) %logo-op-lt-second
                  ; > may continue with =
                  (if (= chr 62) %logo-op-gt-second
                    ())))))
          (pair 'read
            (fn (_ . args)
              (%make-instance %logo-op (%buffer-token (first args)))))
          (pair 'write
            (fn (_ self) (display (first self)))))))

    ; LOGO-PAREN: ( and )
    (Base make-type base "LOGO-PAREN-OPEN"
      (list
        (pair 'analyse
          (Token make-char-state 40 %tok-accept ()))
        (pair 'read (fn (_ . args) (pair %logo-paren-tag "(")))))

    (Base make-type base "LOGO-PAREN-CLOSE"
      (list
        (pair 'analyse
          (Token make-char-state 41 %tok-accept ()))
        (pair 'read (fn (_ . args) (pair %logo-paren-tag ")")))))

    ; LOGO-STRING: "..."
    (def %string-body
      (fn (self buffer score chr)
        (if (= chr 34)
          (%tok-accept-inclusive buffer score chr)
          (if (= chr 10) () self))))

    (set! %logo-string
      (Base make-type base "LOGO-STRING"
        (list
          (pair 'analyse
            (fn (_ buffer score chr)
              (if (= chr 34) %string-body ())))
          (pair 'read
            (fn (_ . args)
              (def text (%buffer-token (first args)))
              (def len (str-length text))
              (%make-instance %logo-string (substring text 1 (- len 1)))))
          (pair 'write
            (fn (_ self)
              (display "\"") (display (first self)) (display "\""))))))

    ; LOGO-SEMI: ; comment to end of line (discard)
    (Base make-type base "LOGO-SEMI"
      (list
        (pair 'analyse
          (fn (_ buffer score chr)
            (if (= chr 59)
              (fn (self buf sc chr2)
                (if (= chr2 10)
                  (%tok-accept buf sc chr2)
                  self))
              ())))))

    base))

; ============================================================
; Block and word accessors
; ============================================================

(def %indent-block-tag (pair 'indent-block ()))

(def %is-block?
  (fn (_ tok)
    (match
      ((%type? tok %logo-block) #t)
      ((pair? tok) (eq? (first tok) %indent-block-tag))
      (#t #f))))

(def %block-contents
  (fn (_ tok)
    (match
      ((%type? tok %logo-block) (first tok))
      (#t (rest tok)))))

(def %make-indent-block
  (fn (_ tokens)
    (pair %indent-block-tag tokens)))

(def %logo-word
  (fn (_ tok)
    (match
      ((%type? tok %logo)        (first tok))
      ((%type? tok %logo-indent) (rest (first tok)))
      (#t ()))))

(def %logo-op-str
  (fn (_ tok)
    (if (%type? tok %logo-op) (first tok) ())))

(def %is-op?
  (fn (_ tok)
    (%type? tok %logo-op)))

(def %is-string?
  (fn (_ tok)
    (%type? tok %logo-string)))

(def %logo-string-val
  (fn (_ tok)
    (first tok)))

(def %is-paren?
  (fn (_ tok str)
    (and (pair? tok)
         (eq? (first tok) %logo-paren-tag)
         (str=? (rest tok) str))))

; ============================================================
; Shared helpers (must be after accessors they depend on)
; ============================================================

; Case-insensitive alist lookup by first element
(def %logo-alist-find
  (fn (_ name alist)
    (def uname (Str upcase name))
    (def %find
      (fn (self entries)
        (match
          ((null? entries) ())
          ((str=? uname (first (first entries))) (first entries))
          (#t (self (rest entries))))))
    (%find alist)))

; Check if a token's word matches a keyword (case-insensitive)
(def %logo-word=?
  (fn (_ tok keyword)
    (let ((w (%logo-word tok)))
      (and (not (null? w))
           (str=? (Str upcase w) keyword)))))

; Command entry accessors
(def %cmd-name    (fn (_ entry) (first entry)))
(def %cmd-arity   (fn (_ entry) (first (rest entry))))
(def %cmd-handler (fn (_ entry) (first (rest (rest entry)))))


(provide logo/types
  %logo-base %logo %logo-indent %logo-block %logo-op %logo-string
  %logo-word %logo-word=? %is-block? %block-contents %make-indent-block
  %logo-op-str %is-op? %is-string? %logo-string-val %is-paren?
  %logo-alpha? logo-process-tokens logo-process-to
  %logo-vars %logo-commands
  %logo-alist-find %cmd-name %cmd-arity %cmd-handler)
