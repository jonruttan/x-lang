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

### creates one segment

```scheme
(turtle-clearscreen)
(turtle-forward 50)
(length %turtle-segments)
```
---
    1

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

### pen-up forward creates segment with pen=#f

```scheme
(turtle-clearscreen)
(turtle-penup)
(turtle-forward 50)
(def seg (first %turtle-segments))
(first (rest (rest (rest (rest seg)))))
```
---
    #f

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
(length %turtle-segments)
```
---
    0

## tokenizer

### tokenizes uppercase word

```scheme
(turtle-clearscreen)
(def toks (token-read-string %logo-base "FD "))
(type? (first toks) %logo)
```
---
    #t

### tokenizes lowercase word

```scheme
(def toks (token-read-string %logo-base "fd "))
(type? (first toks) %logo)
```
---
    #t

### tokenizes mixed case

```scheme
(def toks (token-read-string %logo-base "Forward "))
(%logo-word (first toks))
```
---
    "Forward"

### tokenizes number

```scheme
(def toks (token-read-string %logo-base "100 "))
(first toks)
```
---
    100

### tokenizes brackets into block

```scheme
(def toks (token-read-string %logo-base "[ fd 100 ] "))
(%is-block? (first toks))
```
---
    #t

### block contains tokens

```scheme
(def toks (token-read-string %logo-base "[ fd 100 ] "))
(length (%block-contents (first toks)))
```
---
    2

## command dispatch

### fd creates segment

```scheme
(turtle-clearscreen)
(def toks (token-read-string %logo-base "fd 100 "))
(logo-process-tokens toks)
(length %turtle-segments)
```
---
    1

### repeat draws square

```scheme
(turtle-clearscreen)
(def toks (token-read-string %logo-base "repeat 4 [ fd 100 rt 90 ] "))
(logo-process-tokens toks)
(length %turtle-segments)
```
---
    4

### case insensitive lookup

```scheme
(turtle-clearscreen)
(def toks (token-read-string %logo-base "Forward 50 "))
(logo-process-tokens toks)
(length %turtle-segments)
```
---
    1

## TO procedure definition

### defines and calls procedure

```scheme
(turtle-clearscreen)
(def t1 (token-read-string %logo-base "to sq size [ repeat 4 [ fd size rt 90 ] ] "))
(logo-process-tokens t1)
(def t2 (token-read-string %logo-base "sq 60 "))
(logo-process-tokens t2)
(length %turtle-segments)
```
---
    4

### multi-parameter procedure

```scheme
(turtle-clearscreen)
(def t1 (token-read-string %logo-base "to arcr r deg [ repeat deg [ fd r rt 1 ] ] "))
(logo-process-tokens t1)
(def t2 (token-read-string %logo-base "arcr 1 10 "))
(logo-process-tokens t2)
(length %turtle-segments)
```
---
    10

## indent preprocessing

### flat tokens pass through

```scheme
(def toks (token-read-string %logo-base "fd 100 rt 90 "))
(length (%logo-indent-to-blocks toks))
```
---
    4

### indentation creates block

```scheme
(def toks (token-read-string %logo-base "\nrepeat 4\n    fd 100\n    rt 90\n "))
(def processed (%logo-indent-to-blocks toks))
(length processed)
```
---
    3

### indented repeat draws square

```scheme
(turtle-clearscreen)
(def toks (token-read-string %logo-base "\nrepeat 4\n    fd 100\n    rt 90\n "))
(logo-process-tokens (%logo-indent-to-blocks toks))
(length %turtle-segments)
```
---
    4

## JSON output

### single segment JSON

```scheme
(turtle-clearscreen)
(turtle-forward 100)
(turtle-json-str)
```
---
    "[\n{\"x1\":0,\"y1\":0,\"x2\":0,\"y2\":-100,\"pen\":true,\"heading\":0}\n]\n"
