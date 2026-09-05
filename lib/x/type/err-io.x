; err-io.x -- ERR write/display handlers: the wording of an engine error
;
; An ERR is what the engine hands a guard when the ENGINE itself raises --
; an unbound symbol, a failed include, an unknown character name.  It is a
; typed value with two slots, (code . subject): the raise site's message
; literal, and what it was complaining about, as a stable string.  The
; engine words nothing; it stops at those two facts on purpose, and the
; type's IO stacks boot EMPTY so that the sentence belongs here instead.
;
; WHY THAT MATTERS.  Before, the engine flattened the two into one English
; string -- "Unbound SYMBOL 'car'" -- inside a type-less atom, and a lang
; that wanted to say it differently had nothing to work with: no type, so
; no dispatch stack to push onto, and no structure, so its only option was
; to pattern-match English and hope.  Now the default prose lives on a
; stack, and a lang pushes its own over it:
;
;   (%type-push-display (%type-by-atom (%type-of e))
;     (fn (_ e) (Str8 append "symbole non liee : " (rest e))))
;
; and pops it again to get this file's wording back.  The same shape
; char-io.x uses for CHARACTER, for the same reason.
;
; Loaded beside char-io in x-core's IO block: EARLY, because until it
; loads an engine error renders as the bounded #<obj:ERR> form, and an
; error raised during boot is exactly when you can least afford that.

(def %err-io-by-atom (prim-ref (lit type) (lit by-atom)))
(def %err-io-type-of (prim-ref (lit type) (lit of)))
(def %err-io-push-write (prim-ref (lit type) (lit push-write)))
(def %err-io-push-display (prim-ref (lit type) (lit push-display)))
(def %err-io-append (prim-ref (lit str) (lit append)))
(def %err-io-byte-len (prim-ref (lit str) (lit byte-len)))

; The engine's own wording, reproduced EXACTLY: code, then the subject in
; single quotes when there is one.  Byte-for-byte what the C path printed
; before this type existed -- the 28 spec files that assert error text are
; the check on that, and they must not have to care that the sentence
; moved from C to here.  A raise with no subject carries the empty string
; (the engine cannot spell nil in a repointed atom), so length is the test.
(def %err-io-render
  (fn (_ e)
    (let ((subject (rest e)))
      (if (= 0 (%err-io-byte-len subject))
        ; Appending to "" is not a no-op here: the code is a static-string
        ; ATOM, and handing that to display renders #<ATOM:0x..> -- the very
        ; failure this type exists to end.  The lift makes it a real STRING.
        (%err-io-append "" (first e))
        (%err-io-append (first e)
          (%err-io-append " '" (%err-io-append subject "'")))))))

; --- install (onto the empty boot stacks) ---
;
; The type is reached through the BASE'S OWN ERR -- the single instance
; every raise fills -- rather than by provoking an error to get one.  Same
; route printer.x used to reach the old error atom, and the reason the
; `err` cell is named in the base-paths contract at all.

(let ((et (%err-io-by-atom (%err-io-type-of (first (%reflect-base-cell (lit err)))))))
  (%err-io-push-display et (fn (_ e) (display (%err-io-render e))))
  (%err-io-push-write   et (fn (_ e) (display (%err-io-render e)))))

(doc (provide x/type/err-io)
  "Write/display handlers for ERR, the engine's raised-error value -- the default wording of an engine error, and the stack a lang pushes its own over.")
