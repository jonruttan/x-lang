# x-lang card

## Run

```sh
x -q -c '(write (+ 1 2))' -> 3
echo '(write (+ 1 2))' | x -q -> 3
x -q -c '(def n 6)' -c '(write (* n 7))' -> 42
x -q -l xe -c '(write (+ 1/3 1/6))' -> 1/2        # -l: a dialect or a lang
x -q -f FILE                                     # a file
x                                                # the session
```

## Print

```sh
x -q -c '(write "a b")' -> "a b"
x -q -c '(display "a b")' -> a b
x -q -c '(display 1) (newline) (display 2)' | wc -l | tr -d ' ' -> 1
```

## Define

```x-repl
(def n 10)
(def sq (fn (_ x) (* x x)))
(sq n) -> 100
((fn (self n) (if (= n 0) 1 (* n (self (- n 1))))) 5) -> 120
(let ((a 1) (b 2)) (+ a b)) -> 3
```

## Lists

```x-repl
(list 1 2 3) -> (1 2 3)
(pair 0 '(1 2)) -> (0 1 2)
(first '(1 2 3)) -> 1
(rest '(1 2 3)) -> (2 3)
((list 10 20 30) 1) -> 20
((list 10 20 30) -1) -> 30
(List length (list 1 2 3)) -> 3
(List map (fn (_ x) (* x x)) (list 1 2 3)) -> (1 4 9)
```

## Strings

```x-repl
("a,b" split ",") -> ("a" "b")
(Str8 split "," "a,b,c") -> ("a" "b" "c")
(Str8 append "a" "b" "c") -> "abc"
(Str8 upcase "abc") -> "ABC"
(Str8 length "abc") -> 3
```

## Differs

```x-repl
(first '(1 2)) -> 1                      ; not car
(rest '(1 2)) -> (2)                     ; not cdr
(pair 1 2) -> (1 . 2)                    ; not cons
("a,b" split ",") -> ("a" "b")           ; the subject is last
((fn (_ a b) (+ a b)) 1 2) -> 3          ; not lambda; slot 0 is the closure
(if 0 1 2) -> 1                          ; only nil and #f are false
(if "" 1 2) -> 1
```

## More

```x
(apropos "split")        ; every documented name that mentions it
(help Str8/split)        ; one method: signature, arguments, return, example
(help x/core/math)       ; one module: its exports
(modules)                ; every module
(help)                   ; the overview
```
