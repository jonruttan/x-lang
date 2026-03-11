
== aget

-- retrieves value by key
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (aget (lit b) al))
---
2

-- returns nil for missing key
(do (def al (list (pair (lit a) 1))) (null? (aget (lit z) al)))
---
t

== aget-or

-- returns value when key exists
(do (def al (list (pair (lit a) 1))) (aget-or 99 (lit a) al))
---
1

-- returns default when key missing
(do (def al (list (pair (lit a) 1))) (aget-or 99 (lit z) al))
---
99

== ahas?

-- returns t when key exists
(do (def al (list (pair (lit a) 1))) (ahas? (lit a) al))
---
t

-- returns nil when key missing
(do (def al (list (pair (lit a) 1))) (if (ahas? (lit z) al) "y" "n"))
---
"n"

== aset

-- adds key-value pair
(do (def al (list (pair (lit a) 1))) (aget (lit b) (aset (lit b) 2 al)))
---
2

== adel

-- removes key from alist
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (length (adel (lit a) al)))
---
1

== akeys

-- returns list of keys
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (akeys al))
---
(a b)

== avals

-- returns list of values
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (avals al))
---
(1 2)

== amap

-- applies function to all values
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (aget (lit a) (amap inc al)))
---
2

== afilter

-- filters entries by predicate
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (length (afilter (fn (e) (> (rest e) 1)) al)))
---
1

== amerge

-- merges two alists
(do (def a (list (pair (lit x) 1))) (def b (list (pair (lit y) 2))) (length (amerge a b)))
---
2

== apick

-- selects entries by key list
(do (def al (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))) (length (apick (list (lit a) (lit c)) al)))
---
2

== aomit

-- removes entries by key list
(do (def al (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))) (length (aomit (list (lit a)) al)))
---
2

== from-pairs

-- converts list of lists to alist
(do (def al (from-pairs (list (list (lit a) 1) (list (lit b) 2)))) (aget (lit a) al))
---
1

== to-pairs

-- converts alist to list of lists
(do (def al (list (pair (lit a) 1))) (first (first (to-pairs al))))
---
a

== evolve

-- transforms values by matching keys
(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (aget (lit a) (evolve (list (pair (lit a) inc)) al)))
---
2
