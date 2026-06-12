# @lib ../tests/x/lib/logo.x

## turtle state

### starts at origin

```scheme
(list %turtle-x %turtle-y)
```
---
    (0 0)

### starts heading north

```scheme
%turtle-heading
```
---
    0

### pen starts down

```scheme
%turtle-pen
```
---
    #t

## turtle-forward

### moves north from origin

```scheme
(turtle-forward 100)
(list %turtle-x %turtle-y)
```
---
    (0 -100)

### creates bytecode entries

```scheme
(turtle-clearscreen)
(turtle-forward 50)
(length %turtle-bc)
```
---
    2

## turtle-back

### moves south from origin

```scheme
(turtle-clearscreen)
(turtle-back 100)
(list %turtle-x %turtle-y)
```
---
    (0 100)

## turtle-right

### changes heading clockwise

```scheme
(turtle-clearscreen)
(turtle-right 90)
%turtle-heading
```
---
    90

## turtle-left

### changes heading counterclockwise

```scheme
(turtle-clearscreen)
(turtle-left 45)
%turtle-heading
```
---
    -45

## turtle-penup

### disables drawing

```scheme
(turtle-clearscreen)
(turtle-penup)
%turtle-pen
```
---
    #f

## turtle-pendown

### re-enables drawing

```scheme
(turtle-clearscreen)
(turtle-penup)
(turtle-pendown)
%turtle-pen
```
---
    #t

### pen-up forward emits U then F bytecodes

```scheme
(turtle-clearscreen)
(turtle-penup)
(turtle-forward 50)
(def bc (reverse %turtle-bc))
(first bc)
```
---
    "U"

## turtle-clearscreen

### resets position

```scheme
(turtle-forward 100)
(turtle-clearscreen)
(list %turtle-x %turtle-y)
```
---
    (0 0)

### resets heading

```scheme
(turtle-right 90)
(turtle-clearscreen)
%turtle-heading
```
---
    0

### clears segments

```scheme
(turtle-forward 100)
(turtle-clearscreen)
(length %turtle-bc)
```
---
    0

## tokenizer

### tokenizes uppercase word

```scheme
(turtle-clearscreen)
(def toks (Tok read-str %logo-base "FD "))
(type? (first toks) %logo)
```
---
    #t

### tokenizes lowercase word

```scheme
(def toks (Tok read-str %logo-base "fd "))
(type? (first toks) %logo)
```
---
    #t

### tokenizes mixed case

```scheme
(def toks (Tok read-str %logo-base "Forward "))
(%logo-word (first toks))
```
---
    "Forward"

### tokenizes number

```scheme
(def toks (Tok read-str %logo-base "100 "))
(first toks)
```
---
    100

### tokenizes brackets into block

```scheme
(def toks (Tok read-str %logo-base "[ fd 100 ] "))
(%is-block? (first toks))
```
---
    #t

### block contains tokens

```scheme
(def toks (Tok read-str %logo-base "[ fd 100 ] "))
(length (%block-contents (first toks)))
```
---
    2

## command dispatch

### fd creates segment

```scheme
(turtle-clearscreen)
(def toks (Tok read-str %logo-base "fd 100 "))
(logo-process-tokens toks)
(length %turtle-bc)
```
---
    2

### repeat draws square

```scheme
(turtle-clearscreen)
(def toks (Tok read-str %logo-base "repeat 4 [ fd 100 rt 90 ] "))
(logo-process-tokens toks)
(length %turtle-bc)
```
---
    16

### case insensitive lookup

```scheme
(turtle-clearscreen)
(def toks (Tok read-str %logo-base "Forward 50 "))
(logo-process-tokens toks)
(length %turtle-bc)
```
---
    2

## TO procedure definition

### defines and calls procedure

```scheme
(turtle-clearscreen)
(def t1 (Tok read-str %logo-base "to sq size [ repeat 4 [ fd size rt 90 ] ] "))
(logo-process-tokens t1)
(def t2 (Tok read-str %logo-base "sq 60 "))
(logo-process-tokens t2)
(length %turtle-bc)
```
---
    16

### multi-parameter procedure

```scheme
(turtle-clearscreen)
(def t1 (Tok read-str %logo-base "to arcr r deg [ repeat deg [ fd r rt 1 ] ] "))
(logo-process-tokens t1)
(def t2 (Tok read-str %logo-base "arcr 1 10 "))
(logo-process-tokens t2)
(length %turtle-bc)
```
---
    40

## indent preprocessing

### flat tokens pass through

```scheme
(def toks (Tok read-str %logo-base "fd 100 rt 90 "))
(length (%logo-indent-to-blocks toks))
```
---
    4

### indentation creates block

```scheme
(def toks (Tok read-str %logo-base "\nrepeat 4\n    fd 100\n    rt 90\n "))
(def processed (%logo-indent-to-blocks toks))
(length processed)
```
---
    3

### indented repeat draws square

```scheme
(turtle-clearscreen)
(def toks (Tok read-str %logo-base "\nrepeat 4\n    fd 100\n    rt 90\n "))
(logo-process-tokens (%logo-indent-to-blocks toks))
(length %turtle-bc)
```
---
    16

## JSON output

### bytecode JSON output

```scheme
(turtle-clearscreen)
(turtle-forward 100)
(turtle-bc-str)
```
---
    "[\"F\",100]"

## expressions

### arithmetic precedence

```scheme
(turtle-clearscreen)
(def r (%logo-parse-one-expr (Tok read-str %logo-base "2 + 3 * 4 ")))
(first r)
```
---
    14

### parenthesized expression

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "(2 + 3) * 4 ")))
(first r)
```
---
    20

### power operator

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "2 ^ 3 ")))
(first r)
```
---
    8

### unary minus

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "-5 ")))
(first r)
```
---
    -5

### comparison greater

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "5 > 3 ")))
(first r)
```
---
    #t

### comparison equal

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "5 = 5 ")))
(first r)
```
---
    #t

### string equality

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "\"hello\" = \"hello\" ")))
(first r)
```
---
    #t

### variable in expression

```scheme
(turtle-clearscreen)
(%logo-var-set! "X" 10)
(def r (%logo-parse-one-expr (Tok read-str %logo-base "x + 5 ")))
(first r)
```
---
    15

### function call in expression

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "sqrt(16) ")))
(first r)
```
---
    4

## control flow

### if then true

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "if 5 > 3 then fd 100 "))
(length %turtle-bc)
```
---
    2

### if then false

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "if 5 < 3 then fd 100 "))
(length %turtle-bc)
```
---
    0

### if then else true branch

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "if 5 > 3 then fd 100 else fd 50 "))
%turtle-x
```
---
    0

### if not

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "if not 5 < 3 then fd 100 "))
(length %turtle-bc)
```
---
    2

### stop exits procedure

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to t [ fd 100 stop fd 100 ] "))
(logo-process-tokens (Tok read-str %logo-base "t "))
(length %turtle-bc)
```
---
    2

### return value from procedure

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to add a b [ return a + b ] "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "add(3, 4) ")))
(first r)
```
---
    7

### repeat until

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "x <- 0 repeat [ x <- x + 1 ] until x > 5 "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "x ")))
(first r)
```
---
    6

## assignment

### basic assignment

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "x <- 42 "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "x ")))
(first r)
```
---
    42

### assignment with expression

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "x <- 2 + 3 "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "x ")))
(first r)
```
---
    5

## math functions

### sqrt

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "sqrt(144) ")))
(first r)
```
---
    12

### abs

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "abs(-7) ")))
(first r)
```
---
    7

### sin 90

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "sin(90) ")))
(first r)
```
---
    1

### cos 0

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "cos(0) ")))
(first r)
```
---
    1

### remainder

```scheme
(def r (%logo-parse-one-expr (Tok read-str %logo-base "remainder(17, 5) ")))
(first r)
```
---
    2

### pi constant

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "x <- pi "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "x > 3 ")))
(first r)
```
---
    #t

## turtle state commands

### setxy

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "setxy 100 50 "))
(list %turtle-x %turtle-y)
```
---
    (100 50)

### home

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "fd 100 home "))
(list %turtle-x %turtle-y %turtle-heading)
```
---
    (0 0 0)

### distance

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "setxy 3 4 "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "distance(0, 0) ")))
(first r)
```
---
    5

## pen color and width

### pencolor sets state

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "pencolor \"red\" "))
%turtle-pen-color
```
---
    "red"

### penwidth sets state

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "penwidth 3 "))
%turtle-pen-width
```
---
    3

## repeat forever

### stop breaks repeat forever

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to limited [ repeat forever [ fd 10 stop ] ] "))
(logo-process-tokens (Tok read-str %logo-base "limited "))
(length %turtle-bc)
```
---
    2

## comma-separated args

### two args in parens

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to add a b [ return a + b ] "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "add(2 + 3, 10) ")))
(first r)
```
---
    15

### three args in parens

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to sum3 a b c [ return a + b + c ] "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "sum3(1, 2, 3) ")))
(first r)
```
---
    6

## recursive procedures

### euclid gcd

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to euclid n r [ if n = r then return n if n > r then return euclid(n - r, r) if n < r then return euclid(n, r - n) ] "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "euclid(360, 144) ")))
(first r)
```
---
    72

### factorial

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to fact n [ if n <= 1 then return 1 return n * fact(n - 1) ] "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "fact(6) ")))
(first r)
```
---
    720

## if else

### else branch executes when false

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "if 1 > 5 then fd 100 else fd 50 "))
%turtle-y
```
---
    -50

## execute

### execute runs string as logo

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "execute \"fd 100\" "))
(length %turtle-bc)
```
---
    2

## member

### member finds element in list

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to test.member [ return member(3, [1 2 3 4]) ] "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "test.member() ")))
(first r)
```
---
    #t

### member returns false for missing

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "to test.nomember [ return member(9, [1 2 3]) ] "))
(def r (%logo-parse-one-expr (Tok read-str %logo-base "test.nomember() ")))
(first r)
```
---
    #f

## setheading

### seth sets absolute heading

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "seth 180 "))
%turtle-heading
```
---
    180

## bytecode format

### forward emits F bytecode

```scheme
(turtle-clearscreen)
(turtle-forward 100)
(first (reverse %turtle-bc))
```
---
    "F"

### right emits R bytecode

```scheme
(turtle-clearscreen)
(turtle-right 90)
(first (reverse %turtle-bc))
```
---
    "R"

### pencolor emits K bytecode

```scheme
(turtle-clearscreen)
(turtle-pencolor "red")
(first (reverse %turtle-bc))
```
---
    "K"

## grow and scaled forward

### grow scales s.forward

```scheme
(turtle-clearscreen)
(logo-process-tokens (Tok read-str %logo-base "grow 2 s.fd 50 "))
%turtle-y
```
---
    -100
