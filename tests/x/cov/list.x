; Coverage tests for lib/x/list.x
; Exercises all branches

; --- Folds ---
(fold + 0 (list 1 2 3))
(fold + 0 ())
(scan + 0 (list 1 2 3))
(scan + 0 ())

; --- Basics ---
(nth 0 (list 10 20 30))
(nth 2 (list 10 20 30))
(last (list 1 2 3))
(last (list 42))
(init (list 1 2 3))
(init (list 42))
(append (list 1 2) (list 3 4))
(append () (list 1))
(reverse (list 1 2 3))

; --- flatten -- all 3 clauses ---
(flatten ())
(flatten (list (list 1 2) (list 3)))
(flatten (list 1 2 3))

; --- map -- single and multi-list ---
(map inc (list 1 2 3))
(map inc ())
(map + (list 1 2) (list 10 20))
(map + (list 1) ())

; --- filter -- all 3 clauses ---
(filter even? ())
(filter even? (list 2 3 4))

; --- for-each -- single and multi-list ---
(for-each (fn (x) x) (list 1 2 3))
(for-each (fn (a b) a) (list 1 2) (list 3 4))
(for-each (fn (a b) a) () (list 3 4))

; --- flat-map ---
(flat-map (fn (x) (list x x)) (list 1 2))
(flat-map (fn (x) (list x)) ())

; --- Predicates ---
(any? even? (list 1 3 5))
(any? even? (list 1 2 3))
(any? even? ())
(every? even? (list 2 4 6))
(every? even? (list 2 3 4))
(every? even? ())

; --- Combinators ---
(def both-pos-even (both positive? even?))
(both-pos-even 4)
(both-pos-even -2)
(def either-neg-even (either negative? even?))
(either-neg-even -1)
(either-neg-even 3)

; --- Search ---
(find even? (list 1 3 4 6))
(find even? (list 1 3 5))
(find even? ())
(find-index even? (list 1 3 4))
(find-index even? (list 1 3 5))
(index-of 20 (list 10 20 30))
(index-of 99 (list 10 20))
(includes? 2 (list 1 2 3))
(includes? 9 (list 1 2 3))
(includes? 1 ())

; --- count ---
(count even? (list 1 2 3 4))
(count even? (list 1 3))

; --- Slicing ---
(take 2 (list 1 2 3 4))
(take 0 (list 1 2 3))
(take 5 (list 1 2))
(drop 2 (list 1 2 3 4))
(drop 0 (list 1 2 3))
(take-while positive? (list 1 2 -3 4))
(take-while negative? (list 1 2 3))
(take-while positive? ())
(drop-while positive? (list 1 2 -3 4))
(drop-while positive? ())

; --- Generators ---
(range 0 5)
(range 5 5)
(repeat 0 3)
(repeat 0 0)
(times identity 4)
(times identity 0)
(unfold (fn (x) (> x 3)) identity inc 1)
(unfold (fn (x) t) identity inc 1)
(iterate inc 4 1)
(iterate inc 0 1)

; --- zip ---
(zip (list 1 2) (list 3 4))
(zip () (list 1))
(zip (list 1) ())
(zip-with + (list 1 2) (list 10 20))
(zip-with + () (list 1))
(zip-with + (list 1) ())

; --- Transformation ---
(partition even? (list 1 2 3 4 5 6))
(group-by even? (list 1 2 3 4 5))
(sort < (list 5 3 1 4 2))
(sort < (list 1))
(sort < ())

; --- uniq ---
(uniq (list 1 1 2 2 3))
(uniq (list 1 2 3))
(uniq (list 1))
(uniq ())

; --- uniq-by ---
(uniq-by abs (list 1 -1 2 -2 3))
(uniq-by abs (list 1 2 3))
(uniq-by abs (list 1))
(uniq-by abs ())

; --- intersperse ---
(intersperse 0 (list 1 2 3))
(intersperse 0 (list 1))
(intersperse 0 ())

; --- transpose ---
(transpose (list (list 1 2) (list 3 4)))
(transpose ())
(transpose (list (list 1) ()))

; --- Mutation ---
(update 1 99 (list 10 20 30))
(update 0 99 (list 10 20))
(update 5 99 ())
(insert 0 99 (list 10 20))
(insert 1 99 (list 10 20))
(remove 1 2 (list 10 20 30 40))
(remove 0 1 (list 10 20))
(remove 0 0 (list 10 20))
(adjust 0 inc (list 10 20 30))
(adjust 1 inc (list 10 20 30))
(adjust 5 inc ())
