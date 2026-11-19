# x-lang card

## Run

```sh
x -q -c '(write (+ 1 2))' -> 3
echo '(write (+ 1 2))' | x -q -> 3
x -q -c '(def n 6)' -c '(write (* n 7))' -> 42
x -q -l xe -c '(write (+ 1/3 1/6))' -> 1/2
```

| Command line | Meaning |
|---|---|
| `x` | the session: each result is printed back |
| `x -f FILE` | run a file and exit; it prints only what it writes |
| `x -F FILE` | run a file, then the session with its definitions |
| `x -c EXPR` | run one expression and exit; repeats, in order |
| `x < FILE` | a program on standard input runs as a file does |
| `x -q` | no banner |
| `x -l NAME` | a dialect (`he`, `xe`, `rn`) or an installed lang |
| `x -l NAME -- ARGS` | a tool lang takes its own arguments after `--` |

| Dialect | Adds |
|---|---|
| `he` helium | the default: core, the classes, POSIX, the session |
| `xe` xenon | the numeric tower, regex, `Dict`, `Set`, the compiler |
| `rn` radon | what is experimental and may change: raw system calls |

## Values

| Written | Is |
|---|---|
| `42` `-7` `0xff` | integers |
| `"a\n"` | a string; escapes `\" \\ \n \t \r \0 \xHH` |
| `#"n is {n}"` | a string with holes: each `{expr}` is evaluated |
| `#\a` `#\space` `#\newline` | characters |
| `#t` `#f` | booleans |
| `()` | nil: the empty list |
| `'abc` | a symbol, not looked up |
| `'(1 2 3)` | a list as data; a bare `(f 1 2)` is a call |
| `(1 . 2)` | a pair |
| `#(1 2 3)` | a vector |
| `; text` | a comment, to the end of the line |
| `3.14` `1/3` `3+4i` `1.5d` | float, rational, complex, decimal: xenon |
| `#/ab*c/` | a regular expression: xenon |

```x-repl
(def n 6)
#"n is {n}, twice {(* n 2)}" -> "n is 6, twice 12"
'(1 2 3) -> (1 2 3)
(pair 1 2) -> (1 . 2)
(Type name (Type of "a")) -> "STRING"
```

### What is false

```x-repl
(if () 1 2) -> 2                         ; nil is false
(if #f 1 2) -> 2                         ; #f is false
(if 0 1 2) -> 1                          ; everything else is true
(if "" 1 2) -> 1
```

## Define

| Form | Meaning |
|---|---|
| `(def NAME VALUE)` | bind a name here |
| `(set! NAME VALUE)` | change a binding that exists |
| `(let ((A 1) (B 2)) BODY)` | names for the body only |
| `(do A B C)` | each in order; the value of the last |
| `(fn (SELF A B) BODY)` | a function; slot 0 is the function itself |
| `(fn (_ A . REST) BODY)` | the remaining arguments as a list |
| `(fn () BODY)` | a function of no arguments |

```x-repl
(def n 10)
(def sq (fn (_ x) (* x x)))
(sq n) -> 100
(set! n 11)
n -> 11
(let ((a 1) (b 2)) (+ a b)) -> 3
(do (def t 1) (+ t 1)) -> 2
```

### Functions

```x-repl
(def fact (fn (self n) (if (= n 0) 1 (* n (self (- n 1))))))
(fact 5) -> 120                          ; self is the function: recursion
(def others (fn (_ a . more) more))
(others 1 2 3) -> (2 3)
(def adder (fn (_ n) (fn (_ x) (+ n x))))
((adder 10) 5) -> 15                     ; a function keeps what it closed over
(apply + (list 1 2 3)) -> 6
```

## Control flow

| Form | Meaning |
|---|---|
| `(if TEST THEN ELSE)` | one of two; without ELSE a false test gives `()` |
| `(when TEST BODY...)` | the body when true |
| `(unless TEST BODY...)` | the body when false |
| `(match (TEST VALUE)...)` | the value beside the first true test |
| `(and A B...)` | the last when all are true, else `#f` |
| `(or A B...)` | the first true one |
| `(not A)` | `#t` or `#f` |
| `(error MESSAGE)` | raise |
| `(guard (E HANDLER) BODY)` | the body; on a raise, HANDLER with E bound |

```x-repl
(def grade (fn (_ n) (match ((> n 100) "big") ((> n 10) "mid") (#t "small"))))
(grade 50) -> "mid"
(when (> 3 2) "yes") -> "yes"
(unless (> 3 2) "no") -> ()
(and 1 2 3) -> 3
(or () #f 3) -> 3
(guard (e e) (error "oops")) -> "oops"
(guard (e "caught") (+ 1 2)) -> 3
```

### Loops

```x-repl
(def down (fn (self n) (if (= n 0) "done" (self (- n 1)))))
(down 100000) -> "done"                 ; a tail call does not grow the stack
(List fold + 0 (List range 1 5)) -> 10
(List times 4 (fn (_ i) (* i i))) -> (0 1 4 9)
```

## Numbers

| Call | Gives |
|---|---|
| `+ - * / %` | arithmetic, any number of arguments |
| `= < > <= >=` | comparison |
| `& \| ^ ~ << >>` | bits |
| `(Num abs N)` `(Num negate N)` | magnitude, sign |
| `(Num min A B)` `(Num max A B)` | the smaller, the larger |
| `(Num clamp LO HI N)` | N held between the two |
| `(Num even? N)` `(Num odd? N)` `(Num zero? N)` | tests |
| `(Convert to VALUE (Type of 0))` | a string to a number; `()` if it is none |
| `(Convert to VALUE (Type of ""))` | a number to a string |

```x-repl
(+ 1 2 3) -> 6
(- 5) -> -5
(/ 7 2) -> 3                             ; integers divide to an integer
(% 10 3) -> 1
(<< 1 4) -> 16
(Num clamp 0 10 15) -> 10
(Convert to "0xff" (Type of 0)) -> 255
(Convert to 42 (Type of "")) -> "42"
```

## Lists

| Call | Gives |
|---|---|
| `(list A B)` `(pair A LIST)` | a list; one more on the front |
| `(first L)` `(rest L)` | the head; all but the head |
| `(L I)` `(L I N)` | the item at I, from the end if negative; N items |
| `(List length L)` `(List reverse L)` | |
| `(List append L M)` `(List flatten L)` | |
| `(List map F L)` `(List filter F L)` `(List reject F L)` | |
| `(List fold F INIT L)` `(List reduce F L)` | F takes the total and the item |
| `(List for-each F L)` | F on each, for its effect |
| `(List find F L)` `(List index-of X L)` | `()` when there is none |
| `(List includes? X L)` `(List any? F L)` `(List all? F L)` | |
| `(List take N L)` `(List drop N L)` `(List slice A B L)` | |
| `(List sort LESS L)` `(List sort-by KEY L)` `(List uniq L)` | |
| `(List range A B)` `(List repeat N X)` | A up to B, B not included |
| `(List zip L M)` `(List group-by KEY L)` | pairs; lists under each key |
| `(List sum L)` `(List product L)` | |

```x-repl
(def xs (list 30 10 20))
(first xs) -> 30
(rest xs) -> (10 20)
(xs 1) -> 10
(xs -1) -> 20
(pair 0 xs) -> (0 30 10 20)
(List length xs) -> 3
(List sort < xs) -> (10 20 30)
(List map (fn (_ x) (* x x)) (list 1 2 3)) -> (1 4 9)
(List filter (fn (_ x) (> x 15)) xs) -> (30 20)
(List fold + 0 xs) -> 60
(List find (fn (_ x) (< x 15)) xs) -> 10
(List take 2 xs) -> (30 10)
(List range 0 5) -> (0 1 2 3 4)
(List zip (list 1 2) (list "a" "b")) -> ((1 . "a") (2 . "b"))
```

## Strings

| Call | Gives |
|---|---|
| `(Str8 length S)` | bytes |
| `(Str8 append S T...)` | joined end to end |
| `(Str8 sub START LENGTH S)` | a piece |
| `(Str8 ref I S)` | the character at I |
| `(Str8 split SEP S)` | a list of the pieces |
| `(Str join SEP LIST)` | the pieces with SEP between |
| `(Str8 upcase S)` `(Str8 downcase S)` | |
| `(Str includes? T S)` `(Str starts? T S)` `(Str ends? T S)` | |
| `(Str repeat N S)` `(Str reverse S)` `(Str empty? S)` | |
| `(str=? S T)` | the same text |
| `(Str8 ->sym S)` `(symbol->str SYM)` | to a symbol and back |
| `(Char ->int C)` `(Char from-int N)` | a character's code and back |

```x-repl
(def s "hello world")
(Str8 length s) -> 11
(Str8 sub 0 5 s) -> "hello"
(Str8 ref 4 s) -> #\o
(Str8 split " " s) -> ("hello" "world")
(s split " ") -> ("hello" "world")
(Str join ", " (list "a" "b" "c")) -> "a, b, c"
(Str8 upcase s) -> "HELLO WORLD"
(Str starts? "he" s) -> #t
(Str8 append s "!" "!") -> "hello world!!"
(Char ->int #\a) -> 97
```

## Vectors and tables

| Call | Gives |
|---|---|
| `(Vector of A B)` `#(A B)` | a vector |
| `(Vector make N FILL)` | N slots |
| `(Vector ref I V)` `(Vector length V)` | |
| `(Vector ->list V)` `(Vector from-list L)` | |
| `'((a . 1) (b . 2))` | an association list: pairs of key and value |
| `(Assoc get KEY AL)` `(Assoc get-or DEFAULT KEY AL)` | `()` on a miss |
| `(Assoc put KEY VALUE AL)` `(Assoc del KEY AL)` | a new list |
| `(Assoc has? KEY AL)` `(Assoc keys AL)` `(Assoc vals AL)` | |

```x-repl
(def v (Vector of 10 20 30))
(Vector ref 1 v) -> 20
(Vector length v) -> 3
(Vector ->list v) -> (10 20 30)
(Vector make 3 0) -> #(0 0 0)
(def ages '((ann . 30) (bob . 25)))
(Assoc get 'bob ages) -> 25
(Assoc get 'eve ages) -> ()
(Assoc keys (Assoc put 'eve 41 ages)) -> ('eve 'ann 'bob)
```

## Calls

| Written | Meaning |
|---|---|
| `(Class method ARG... SUBJECT)` | a method: the thing worked on is last |
| `(SUBJECT method ARG...)` | the same call, from the value |
| `(method-ref Class method)` | the method as a value, to pass |
| `(Fn partial F A)` | F with its first argument fixed |
| `(Fn compose F G)` | G, then F |
| `(Fn pipe F G)` | F, then G |

```x-repl
(Str8 split "," "a,b") -> ("a" "b")
("a,b" split ",") -> ("a" "b")
(List map (method-ref Num inc) (list 1 2)) -> (2 3)
((Fn partial + 10) 5) -> 15
((Fn pipe (method-ref Num inc) (method-ref Num abs)) -5) -> 4
```

## Classes

| Form | Meaning |
|---|---|
| `(def-class NAME () FIELD... METHOD...)` | a class |
| `(def-class NAME (extends PARENT) ...)` | a class with one parent |
| `(method NAME (self ARG...) BODY)` | a method, inside `def-class` |
| `(new NAME FIELD VALUE ...)` | an instance |
| `(OBJ FIELD)` `(OBJ FIELD VALUE)` | read a field; set it |
| `(OBJ METHOD ARG...)` | call a method |
| `(super self METHOD ARG...)` | the parent's version |

```x-repl
(def-class Point ()
  x y
  (method sum (self) (+ (self x) (self y))))
(def p (new Point x 3 y 4))
(p x) -> 3
(p sum) -> 7
(def-class Point3 (extends Point)
  z
  (method sum (self) (+ (super self sum) (self z))))
((new Point3 x 1 y 2 z 3) sum) -> 6
```

## Code as data

| Form | Meaning |
|---|---|
| `'X` | X itself, not its value |
| `` `(a ,X ,@XS) `` | a template: `,X` is filled in, `,@XS` spliced in |
| `(eval FORM)` | run a form |
| `(op (A B) ENV BODY)` | like `fn`, but the arguments arrive unevaluated |
| `(wrap OP)` | an operative as a function: arguments evaluated first |

```x-repl
(def x 1)
(def xs (list 2 3))
`(a ,x b) -> ('a 1 'b)
`(0 ,@xs 4) -> (0 2 3 4)
(eval '(+ 1 2)) -> 3
(def my-if (op (c t f) e (if (eval c e) (eval t e) (eval f e))))
(my-if (= 1 1) "yes" "no") -> "yes"
```

## Modules

| Form | Meaning |
|---|---|
| `(import x/type/hash)` | load a module once |
| `(import MODULE NAME...)` | load it and bind those exports here |
| `(provide MODULE NAME...)` | in a module's file: what it exports |
| `(modules)` | every module, the loaded ones marked |

```x-repl
(import x/type/hash)
(Hash ->hex (Hash fnv-1a "hello")) -> "a430d84680aabd0b"
```

## Differs

| From a Lisp or Scheme | Here |
|---|---|
| `car` `cdr` `cons` | `first` `rest` `pair` |
| `lambda` | `fn`, and slot 0 of its parameters is the function itself |
| `define` `begin` `cond` | `def` `do` `match` |
| `(string-split s ",")` | the subject is last: `(Str8 split "," s)` |
| `0` and `""` | true: only `()` and `#f` are false |
| `(car '())` | an error: `first` and `rest` refuse `()` |
| macros | `op`: an operative receives its arguments unevaluated |
| a printed symbol `a` | `'a`: what the session prints reads back |

```x-repl
((fn (_ a b) (+ a b)) 1 2) -> 3
(guard (e e) (first ())) -> "first: () has no first"
(list 'a 'b) -> ('a 'b)
```

## More

| Call | Shows |
|---|---|
| `(apropos "split")` | every documented name that mentions it |
| `(help Str8/split)` | one method: signature, arguments, return, example |
| `(help x/core/math)` | one module: its exports |
| `(modules)` | every module |
| `(help)` | the overview |
