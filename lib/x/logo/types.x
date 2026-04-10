; types.x -- Logo tokenizer base and type definitions
(import x/logo/state)
(import x/sys/token)
(import x/type/string)

; ============================================================
; Type helpers
; ============================================================

(def %logo-block-close (pair (lit logo-block-close) ()))

(def %logo-alpha?
  (fn (_ chr)
    (if (and (>= chr 65) (<= chr 90)) #t
      (if (and (>= chr 97) (<= chr 122)) #t #f))))

(def %logo-word-continue
  (fn (self buffer score chr)
    (if (if (%logo-alpha? chr) #t
          (if (= chr 46) #t
            (if (and (>= chr 48) (<= chr 57)) #t #f)))
      self
      (token-accept buffer score chr))))

; Forward declarations
(def %logo ())
(def %logo-indent ())
(def %logo-block ())
(def logo-process-tokens ())
(def logo-process-to ())

; ============================================================
; Whitespace type detection
; ============================================================

(def %is-ws-type?
  (fn (_ entry)
    (def io (type-io (rest entry)))
    (def delimit (first (first (rest io))))
    (def read-h (first (first (rest (rest io)))))
    (if (null? delimit) #f (null? read-h))))

; ============================================================
; Logo tokenizer base
; ============================================================

(def %logo-base
  (let ((base (make-base)))
    (def %cell (first (first (first (rest (first base))))))
    (def %sym-name (type-of (lit x)))
    ; Remove SYMBOL and WHITESPACE types
    (def %filter
      (fn (self al)
        (if (null? al) ()
          (if (eq? (first (first al)) %sym-name)
            (self (rest al))
            (if (%is-ws-type? (first al))
              (self (rest al))
              (pair (first al) (self (rest al))))))))
    (set-first! %cell (%filter (first %cell)))

    ; LOGO-BLOCK
    (set! %logo-block
      (base-make-type base "LOGO-BLOCK"
        (list
          (pair (lit write) (fn (_ self) (display "[ ... ]")))
          (pair (lit eval) (fn (_ self) (logo-process-tokens (first self)))))))

    ; LOGO-CLOSE
    (base-make-type base "LOGO-CLOSE"
      (list
        (pair (lit first-chars) "]")
        (pair (lit analyse)
          (make-char-state (char->integer #\]) token-accept ()))
        (pair (lit read) (fn (_ . args) %logo-block-close))))

    ; LOGO-OPEN
    (base-make-type base "LOGO-OPEN"
      (list
        (pair (lit first-chars) "[")
        (pair (lit analyse)
          (make-char-state (char->integer #\[) token-accept ()))
        (pair (lit read)
          (fn (_ . args)
            (def buf (first args))
            (def %rb
              (fn (self acc)
                (def tok (token-read buf))
                (if (null? tok)
                  (make-instance %logo-block (reverse acc))
                  (if (eq? tok %logo-block-close)
                    (make-instance %logo-block (reverse acc))
                    (self (pair tok acc))))))
            (%rb ())))))

    ; LOGO (word type)
    (set! %logo
      (base-make-type base "LOGO"
        (list
          (pair (lit first-chars) "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
          (pair (lit analyse)
            (fn (_ buffer score chr)
              (if (%logo-alpha? chr) %logo-word-continue ())))
          (pair (lit read)
            (fn (_ . args)
              (make-instance %logo (buffer-token (first args)))))
          (pair (lit write)
            (fn (_ self) (display (first self)))))))

    ; LOGO-WS: spaces and tabs only, discard
    (base-make-type base "LOGO-WS"
      (list
        (pair (lit analyse)
          (fn (self buffer score chr)
            (if (if (= chr 32) #t (= chr 9))
              self
              (if (> (- (buffer-len buffer) 1) 0)
                (do (buffer-unread buffer)
                    (score-set score 1 buffer))
                ()))))
        (pair (lit delimit)
          (fn (_ buffer score chr)
            (if (if (= chr 32) #t (= chr 9))
              (do (buffer-unread buffer) buffer)
              ())))))

    ; LOGO-NEWLINE: bare newline, discard
    (base-make-type base "LOGO-NEWLINE"
      (list
        (pair (lit first-chars) "\n")
        (pair (lit analyse)
          (make-char-state 10 token-accept ()))))

    ; LOGO-INDENT: \n + spaces/tabs + word
    (def %indent-after-nl
      (fn (self buffer score chr)
        (if (if (= chr 32) #t (= chr 9))
          self
          (if (%logo-alpha? chr)
            %logo-word-continue
            ()))))

    (set! %logo-indent
      (base-make-type base "LOGO-INDENT"
        (list
          (pair (lit first-chars) "\n")
          (pair (lit analyse)
            (fn (_ buffer score chr)
              (if (= chr 10) %indent-after-nl ())))
          (pair (lit read)
            (fn (_ . read-args)
              (def text (buffer-token (first read-args)))
              (def len (str-length text))
              (def %count-indent
                (fn (self i)
                  (if (>= i len) i
                    (if (if (char=? (text i) #\space) #t
                          (char=? (text i) #\tab))
                      (self (+ i 1))
                      i))))
              (def indent-end (%count-indent 1))
              (def indent (- indent-end 1))
              (def word (substring text indent-end len))
              (make-instance %logo-indent (pair indent word))))
          (pair (lit write)
            (fn (_ self)
              (display (first (rest (first self)))))))))

    base))

; ============================================================
; Block and word accessors
; ============================================================

(def %indent-block-tag (pair (lit indent-block) ()))

(def %is-block?
  (fn (_ tok)
    (if (type? tok %logo-block) #t
      (if (pair? tok) (eq? (first tok) %indent-block-tag) #f))))

(def %block-contents
  (fn (_ tok)
    (if (type? tok %logo-block) (first tok)
      (rest tok))))

(def %make-indent-block
  (fn (_ tokens)
    (pair %indent-block-tag tokens)))

(def %logo-word
  (fn (_ tok)
    (if (type? tok %logo) (first tok)
      (if (type? tok %logo-indent) (rest (first tok))
        ()))))

(provide x/logo/types
  %logo-base %logo %logo-indent %logo-block
  %logo-word %is-block? %block-contents %make-indent-block
  %logo-alpha? logo-process-tokens logo-process-to)
