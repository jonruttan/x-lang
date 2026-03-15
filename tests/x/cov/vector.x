; Coverage tests for lib/x/vector.x
; Exercises all branches

; vector creation + write (triggers write handler with list iteration)
(write (vector 1 2 3))
(write (vector 42))
(write (vector))

; vector? -- type check
(vector? (vector 1))
(vector? 42)

; make-vector -- recursion + base case
(make-vector 3 0)
(make-vector 0 0)

; vector->list + list->vector
(vector->list (vector 1 2 3))
(list->vector (list 4 5 6))

; vector-ref + vector-length
(vector-ref (vector 10 20 30) 1)
(vector-length (vector 1 2 3))
(vector-length (vector))

; vector indexing (call handler)
((vector 10 20 30) 0)
((vector 10 20 30) -1)
