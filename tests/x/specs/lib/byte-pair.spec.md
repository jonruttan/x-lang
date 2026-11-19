# BytePair: text to a model's vocabulary ids and back
# @weight 1

`BytePair` cuts text into words and merges each word's bytes by a merge
list's ranks; what is left are items of the vocabulary, and their ids are
the answer. The vocabularies here are small and made in the case. In a
vocabulary an item is written in letters, one for a byte, and the space is
written `Ġ`, U+0120.

## a vocabulary

### size, item and id

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "ab" 2 "Ġ" 3 "Ġa" 4)) (list (list "a" "b") (list "Ġ" "a"))))
  (list (b size) (b item 2) (b item 4) (b id "ab") (b id " a")))
```
---
    (5 "ab" " a" 2 4)

### an id or an item the vocabulary lacks answers nil

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1)) ()))
  (list (b item 9) (b item -1) (b id "zz")))
```
---
    (() () ())

### an item of bytes past ASCII is its bytes

é is the bytes C3 A9, which the files write as the letters Ã and ©.

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "Ã" 0 "©" 1 "Ã©" 2)) (list (list "Ã" "©"))))
  (list (b item 2) (b id "é") (b encode "é")))
```
---
    ("é" 2 (2))

## encode

### neighbours are joined by the merge list

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "c" 2 "ab" 3 "abc" 4))
                        (list (list "a" "b") (list "ab" "c"))))
  (list (b encode "abc") (b encode "cab") (b encode "c")))
```
---
    ((4) (2 3) (2))

### the pair ranked first is joined first

Both a b and b c are in the list; whichever is earlier takes the b.

```x
(do (import x/codec/byte-pair)
  (def ids (Dict from-plist (list "a" 0 "b" 1 "c" 2 "ab" 3 "bc" 4)))
  (list ((BytePair make ids (list (list "a" "b") (list "b" "c"))) encode "abc")
        ((BytePair make ids (list (list "b" "c") (list "a" "b"))) encode "abc")))
```
---
    ((3 2) (0 4))

### every such pair in the word is joined

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "ab" 2)) (list (list "a" "b"))))
  (b encode "ababb"))
```
---
    (2 2 1)

### a space belongs to the word after it, and no pair joins across words

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "Ġ" 2 "Ġa" 3 "aĠ" 4))
                        (list (list "a" "Ġ") (list "Ġ" "a"))))
  (b encode "a ab a"))
```
---
    (0 3 1 3)

### letters, numbers and other characters are words of their own

b 1 is in the merge list, and is not joined: the b ends one word and the
1 begins the next.

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "1" 2 "2" 3 "b1" 4 "12" 5 "!" 6 "?" 7 "!?" 8))
                        (list (list "b" "1") (list "1" "2") (list "!" "?"))))
  (b encode "ab12!?"))
```
---
    (0 1 5 8)

### a contraction is a word of its own

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "i" 0 "t" 1 "'" 2 "s" 3 "'s" 4 "it" 5 "ts" 6 "l" 7 "'l" 8 "'ll" 9))
                        (list (list "t" "s") (list "i" "t") (list "'" "s") (list "'" "l") (list "'l" "l"))))
  (list (b encode "it's") (b encode "it'll") (b encode "it'")))
```
---
    ((5 4) (5 9) (5 2))

### a run of white space keeps its last character for the word that follows

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "Ġ" 1 "Ġa" 2 "ĠĠ" 3 "Ċ" 4))
                        (list (list "Ġ" "a") (list "Ġ" "Ġ"))))
  (list (b encode "a   a") (b encode "a  ") (b encode "a\na")))
```
---
    ((0 3 2) (0 3) (0 4 0))

### a letter past ASCII is a letter

é and a are one word, so the pair that joins them is met; a dash is not a
letter, and the same pair across it is not.

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "Ã" 1 "©" 2 "©a" 3 "â" 4 "Ģ" 5 "Ķ" 6))
                        (list (list "©" "a"))))
  (list (b encode "éa") (b encode "—a")))
```
---
    ((1 3) (4 5 6 0))

### an empty text has no ids

```x
(do (import x/codec/byte-pair)
  (list ((BytePair make (Dict from-plist (list "a" 0)) ()) encode "")))
```
---
    (())

### a byte the vocabulary has no item for raises a label value

```x
(do (import x/codec/byte-pair)
  (guard (e (Err label e)) ((BytePair make (Dict from-plist (list "a" 0)) ()) encode "ab")))
```
---
    'value

## decode

### the items' bytes end to end

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "ab" 2 "Ġ" 3 "Ġa" 4)) (list (list "a" "b") (list "Ġ" "a"))))
  (b decode (list 2 1 3 2 4)))
```
---
    "abb ab a"

### what encode answers, decode reads back

```x
(do (import x/codec/byte-pair)
  (def b (BytePair make (Dict from-plist (list "a" 0 "b" 1 "ab" 2 "Ġ" 3 "Ġa" 4 "Ã" 5 "©" 6 "Ċ" 7))
                        (list (list "a" "b") (list "Ġ" "a"))))
  (def text "ab  a\nbé ab")
  (equal? (b decode (b encode text)) text))
```
---
    #t

### an id the vocabulary lacks raises a label value

```x
(do (import x/codec/byte-pair)
  (guard (e (Err label e)) ((BytePair make (Dict from-plist (list "a" 0)) ()) decode (list 0 5))))
```
---
    'value

## from files

### a vocabulary file and a merge file

The merge file's first line is a comment, and a pair may be of `#`
itself.

```x
(do (import x/codec/byte-pair)
  (def v (File temp "/tmp/x-byte-pair-vocabulary-"))
  (def m (File temp "/tmp/x-byte-pair-merges-"))
  (File close (first v))
  (File close (first m))
  (File write-all (rest v) "{\"a\": 0, \"b\": 1, \"ab\": 2, \"#\": 3, \"##\": 4, \"\\u0120\": 5, \"\\u0120a\": 6}")
  (File write-all (rest m) "#version: 0.2\na b\n# #\nĠ a\n")
  (def b (BytePair from-files (rest v) (rest m)))
  (File unlink (rest v))
  (File unlink (rest m))
  (list (b size) (b encode "ab ## a") (b decode (list 2 5 4))))
```
---
    (7 (2 5 4 6) "ab ##")
