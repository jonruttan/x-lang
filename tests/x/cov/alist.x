; Coverage tests for lib/x/alist.x
; Exercises all branches

; aget -- all 3 match clauses
(aget (lit a) ())                                    ; null → ()
(aget (lit a) (list (pair (lit a) 1)))               ; key match → val
(aget (lit b) (list (pair (lit a) 1) (pair (lit b) 2)))  ; recurse, then match

; aget-or -- both branches
(aget-or 99 (lit a) (list (pair (lit a) 1)))   ; found → value
(aget-or 99 (lit z) (list (pair (lit a) 1)))   ; not found → default

; ahas? -- all 3 match clauses
(ahas? (lit a) ())                               ; null → ()
(ahas? (lit a) (list (pair (lit a) 1)))          ; match → t
(ahas? (lit b) (list (pair (lit a) 1) (pair (lit b) 2)))  ; recurse

; adel -- all 3 match clauses
(adel (lit a) ())                                          ; null → ()
(adel (lit a) (list (pair (lit a) 1) (pair (lit b) 2)))    ; match → skip + recurse
(adel (lit c) (list (pair (lit a) 1) (pair (lit b) 2)))    ; no match → keep + recurse

; aset
(aset (lit a) 1 ())
(aset (lit a) 2 (list (pair (lit a) 1)))  ; overwrites existing

; amerge -- both branches of fold callback
(amerge (list (pair (lit a) 1)) (list (pair (lit a) 2) (pair (lit b) 3)))
; (pair (lit a) 2) is already in acc → skip
; (pair (lit b) 3) is not in acc → add

; evolve -- both branches (transform found, transform missing)
(evolve (list (pair (lit a) inc)) (list (pair (lit a) 1) (pair (lit b) 2)))
