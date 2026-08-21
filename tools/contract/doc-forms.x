; doc-forms.x -- the class-body forms the reference generator renders
;
; Pure data -- no code, just s-expressions.  Each entry: (name "what the
; generator does with it").  This is the STRUCTURAL vocabulary: the forms a
; class body can hold that are not members.
;
; It is documentation, not the gate's authority.  tools/check/doc-forms.sh
; checks COVERAGE -- every member declared under lib/ appears on its page --
; because the obvious check does not exist to be written: a member is
; declared as (name), (name default) or (name default "description"), so the
; head of a class-body form is the MEMBER'S OWN NAME and the set is open.
; Anything not listed below is therefore a member, and the generator renders
; it as one.
;
; WHY EITHER EXISTS.  The walker used to end in a silent catch-all: a form it
; did not recognise reached the page as nothing at all, and the page still
; looked finished.  Every member in the library rendered that way -- Ansi's
; colours, Random's kind/state/fd -- and it was found by reading a page
; beside (help ...), not by any check.
;
; The object-model v2 (private ...) and (protected ...) blocks are taught:
; their tail SPLICES into the class body (lib/x/type/class.x explodes them
; that way), so the walker descends and marks what it finds with its tier.
; A bare symbol inside one is a member declaration and normalises to (name).

(
  (doc       "The class's own description, notes and examples -- and a member's documentation when its first argument is a symbol rather than a string.")
  (method    "An instance method, or a static when it sits inside a (static ...) block.")
  (static    "A block of statics; its body is walked as methods.")
  (interface "The operations a type must supply to satisfy the protocol.")
  (private   "A visibility block; its tail splices into the class body and each name is marked private -- reachable from the class's own methods only.")
  (protected "A visibility block; its tail splices into the class body and each name is marked protected -- reachable from methods anywhere on the chain.")
)
