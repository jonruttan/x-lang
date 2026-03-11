
== write

-- writes an integer
(write 42)
---
42

-- writes a string with quotes
(write "hello")
---
"hello"

-- writes a symbol
(write (lit hello))
---
hello

-- writes a list
(write (lit (1 2 3)))
---
(1 2 3)

-- writes a nested list
(write (lit (1 (2 3))))
---
(1 (2 3))

-- returns nil
(do (def r (write 42)) (newline) (null? r))
---
t

== display

-- displays an integer
(display 42)
---
42

-- displays a string without quotes
(display "hello")
---
hello

-- displays a symbol
(display (lit hello))
---
hello

-- displays a list
(display (lit (1 2 3)))
---
(1 2 3)

-- returns nil
(do (def r (display 42)) (newline) (null? r))
---
t

== newline

-- returns nil
(null? (newline))
---
t

== read

-- reads an integer
(do (def x (read)) x) 42
---
42

-- reads a symbol
(do (def x (read)) x) hello
---
hello

-- reads a list
(do (def x (read)) x) (1 2 3)
---
(1 2 3)

-- reads a string
(do (def x (read)) x) "world"
---
"world"

== read-char

-- reads a single character
(do (def c (read-char)) (char? c))
---
t

-- returns nil on end of input
(do (read-char) (null? (read-char)))
---
t

== gc

-- returns nil
(null? (gc))
---
t
