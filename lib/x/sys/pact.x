; pact.x -- Deferred cross-module registration: a rendezvous for modules
; that are optional to each other (the numeric tower's arbitrary-order
; loading).
;
; The problem: a pairwise registration (e.g. the bignum->float conversion)
; can only be installed once BOTH sides are loaded -- it needs one side's
; type handle and the other side's operations -- and either side may load
; first, or never. Whichever module carries the code cannot probe for the
; other: an unbound global raises (the language has no bound?), and a
; load-time check covers only one load order.
;
; The mechanism: a module JOINS the pact under a stable name symbol as its
; last load-time act, publishing its handle. A registration that needs other
; parties is filed with WHEN: it runs immediately if every named party has
; already joined, and is queued otherwise, firing exactly once at the join
; that completes it. Load order stops mattering, and a registration against
; a module that never loads simply never runs.
;
;   (Pact join (lit bignum) %bignum)   -- announce; publish the handle
;   (Pact when (list (lit bignum))     -- run now, or at bignum's join
;     (fn (_ big) ...))                -- applied to the joined values
;   (Pact get (lit bignum))            -- joined value, or ()
;   (Pact has? (lit bignum))           -- #t if the name has joined
;
; A when-body may reference the waited-on module's globals: by the time it
; fires, that module has fully loaded and its top-level defs are bound.

(import x/type/object)

; --- State ---
; The roll-call: (name . value) alist, newest first (a re-join shadows).
(def %pact-joined ())
; The waiting registrations: list of (names . thunk), registration order.
(def %pact-pending ())

; --- Boot-lean helpers ---
; Pact loads mid-boot (the tower modules import it), so it defines its own
; list recursion instead of importing x/core/list. Recursion goes through
; the self argument, per the self-passing convention.

(def %pact-rev
  (fn (self l acc)
    (if (null? l) acc (self (rest l) (pair (first l) acc)))))

(def %pact-entry
  (fn (self alist name)
    (if (null? alist) ()
      (if (eq? (first (first alist)) name)
        (first alist)
        (self (rest alist) name)))))

; All of NAMES joined?
(def %pact-all?
  (fn (self names)
    (if (null? names) #t
      (if (null? (%pact-entry %pact-joined (first names))) ()
        (self (rest names))))))

; Joined values for NAMES, in the names' order. Looked up at fire time, so
; a thunk always sees the newest published values.
(def %pact-values
  (fn (self names)
    (if (null? names) ()
      (pair (rest (%pact-entry %pact-joined (first names)))
            (self (rest names))))))

; Fire one (names . thunk) entry: apply the thunk to the joined values.
(def %pact-fire
  (fn (_ entry) (apply (rest entry) (%pact-values (first entry)))))

(def %pact-fire-all
  (fn (self entries)
    (if (null? entries) ()
      (do (%pact-fire (first entries))
          (self (rest entries))))))

; Partition PENDING into (ready . waiting), both in registration order.
(def %pact-split
  (fn (self entries ready waiting)
    (if (null? entries)
      (pair (%pact-rev ready ()) (%pact-rev waiting ()))
      (if (%pact-all? (first (first entries)))
        (self (rest entries) (pair (first entries) ready) waiting)
        (self (rest entries) ready (pair (first entries) waiting))))))

; Drain after a join: commit the still-waiting list BEFORE firing, so a
; fired thunk that itself joins or files new when-entries sees a pending
; list that no longer contains the entries this drain took.
(def %pact-drain
  (fn (_)
    (let ((split (%pact-split %pact-pending () ())))
      (set! %pact-pending (rest split))
      (%pact-fire-all (first split)))))

(def %pact-join
  (fn (_ name value)
    (set! %pact-joined (pair (pair name value) %pact-joined))
    (%pact-drain)))

; Append preserves registration (= firing) order; pending lists are tiny.
(def %pact-when
  (fn (_ names thunk)
    (if (%pact-all? names)
      (%pact-fire (pair names thunk))
      (set! %pact-pending
        (%pact-rev (%pact-rev %pact-pending (list (pair names thunk))) ())))))

; --- The API ---
(def-class Pact ()
  (static
    (method join (self (param name SYMBOL "The joining module's stable name")
                       (param value ANY "The published value (typically the type handle)"))
      (doc "Announce NAME as joined, publishing VALUE, and fire every pending when-entry this join completes."
        (returns NIL "Nothing"))
      (%pact-join name value))
    (method when (self (param names LIST "Name symbols this registration needs")
                       (param thunk CALLABLE "(fn (_ . values) ...), applied to the joined values in NAMES order"))
      (doc "Run THUNK once all NAMES have joined: immediately if they already have, else at the completing join. Fires exactly once; never fires if a name never joins."
        (returns NIL "Nothing"))
      (%pact-when names thunk))
    (method get (self (param name SYMBOL "Name to look up"))
      (doc "The value NAME published on join (the newest, if re-joined)."
        (returns ANY "The joined value, or nil if NAME has not joined"))
      (let ((entry (%pact-entry %pact-joined name)))
        (if (null? entry) () (rest entry))))
    (method has? (self (param name SYMBOL "Name to test"))
      (doc "Test whether NAME has joined the pact."
        (returns BOOL "True if NAME has joined"))
      (if (null? (%pact-entry %pact-joined name)) () #t))))

(doc (provide x/sys/pact Pact)
  (note "Modules join as their last load-time act; when-entries fire in registration order.")
  (note "A when-thunk may reference the waited-on module's globals: it only runs once they are bound.")
  "Deferred cross-module registration: run a pairwise setup once every party has loaded, in any load order.")
