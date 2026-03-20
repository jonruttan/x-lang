## sh-whitespace

### discards spaces

```sh
(write (sh-tokenize "a b"))
```
---
    ((tok-word "a") (tok-word "b"))

### discards tabs

```sh
(do (def s (string-append (string-append "a" (make-string 1 (convert 9 %char))) "b")) (write (sh-tokenize s)))
```
---
    ((tok-word "a") (tok-word "b"))

### discards multiple spaces

```sh
(write (sh-tokenize "a   b"))
```
---
    ((tok-word "a") (tok-word "b"))

## sh-newline

### produces a newline token

```sh
(do (def s (string-append (string-append "a" (make-string 1 (convert 10 %char))) "b")) (write (sh-tokenize s)))
```
---
    ((tok-word "a") (tok-newline) (tok-word "b"))

## sh-comment

### discards comment to end of line

```sh
(do (def s (string-append (string-append "a # comment" (make-string 1 (convert 10 %char))) "b")) (write (sh-tokenize s)))
```
---
    ((tok-word "a") (tok-newline) (tok-word "b"))

### discards whole-line comment

```sh
(do (def s (string-append (string-append "# comment" (make-string 1 (convert 10 %char))) "b")) (write (sh-tokenize s)))
```
---
    ((tok-newline) (tok-word "b"))

## sh-operator single-char

### tokenizes pipe

```sh
(write (sh-tokenize "a|b"))
```
---
    ((tok-word "a") (tok-op "|") (tok-word "b"))

### tokenizes ampersand

```sh
(write (sh-tokenize "a&b"))
```
---
    ((tok-word "a") (tok-op "&") (tok-word "b"))

### tokenizes semicolon

```sh
(write (sh-tokenize "a;b"))
```
---
    ((tok-word "a") (tok-op ";") (tok-word "b"))

### tokenizes less-than

```sh
(write (sh-tokenize "a<b"))
```
---
    ((tok-word "a") (tok-op "<") (tok-word "b"))

### tokenizes greater-than

```sh
(write (sh-tokenize "a>b"))
```
---
    ((tok-word "a") (tok-op ">") (tok-word "b"))

### tokenizes open-paren

```sh
(write (sh-tokenize "(a)"))
```
---
    ((tok-op "(") (tok-word "a") (tok-op ")"))

## sh-operator double-char

### tokenizes or-or

```sh
(write (sh-tokenize "a||b"))
```
---
    ((tok-word "a") (tok-op "||") (tok-word "b"))

### tokenizes and-and

```sh
(write (sh-tokenize "a&&b"))
```
---
    ((tok-word "a") (tok-op "&&") (tok-word "b"))

### tokenizes double-semicolon

```sh
(write (sh-tokenize "a;;b"))
```
---
    ((tok-word "a") (tok-op ";;") (tok-word "b"))

### tokenizes here-doc

```sh
(write (sh-tokenize "a<<b"))
```
---
    ((tok-word "a") (tok-op "<<") (tok-word "b"))

### tokenizes append

```sh
(write (sh-tokenize "a>>b"))
```
---
    ((tok-word "a") (tok-op ">>") (tok-word "b"))

### tokenizes dup-input

```sh
(write (sh-tokenize "a<&b"))
```
---
    ((tok-word "a") (tok-op "<&") (tok-word "b"))

### tokenizes dup-output

```sh
(write (sh-tokenize "a>&b"))
```
---
    ((tok-word "a") (tok-op ">&") (tok-word "b"))

### tokenizes read-write

```sh
(write (sh-tokenize "a<>b"))
```
---
    ((tok-word "a") (tok-op "<>") (tok-word "b"))

### tokenizes clobber

```sh
(write (sh-tokenize "a>|b"))
```
---
    ((tok-word "a") (tok-op ">|") (tok-word "b"))

## sh-operator triple-char

### tokenizes here-strip

```sh
(write (sh-tokenize "a<<-b"))
```
---
    ((tok-word "a") (tok-op "<<-") (tok-word "b"))

## sh-sq-string

### tokenizes single-quoted string

```sh
(write (sh-tokenize "echo 'hello world'"))
```
---
    ((tok-word "echo") (tok-sq "hello world"))

### tokenizes empty single-quoted string

```sh
(write (sh-tokenize "echo ''"))
```
---
    ((tok-word "echo") (tok-sq ""))

## sh-dq-string

### tokenizes double-quoted string

```sh
(write (sh-tokenize "echo \"hello world\""))
```
---
    ((tok-word "echo") (tok-dq "hello world"))

### tokenizes empty double-quoted string

```sh
(write (sh-tokenize "echo \"\""))
```
---
    ((tok-word "echo") (tok-dq ""))

## sh-word

### tokenizes simple word

```sh
(write (sh-tokenize "echo"))
```
---
    ((tok-word "echo"))

### tokenizes multiple words

```sh
(write (sh-tokenize "echo hello world"))
```
---
    ((tok-word "echo") (tok-word "hello") (tok-word "world"))

### tokenizes words with hyphens

```sh
(write (sh-tokenize "apt-get install"))
```
---
    ((tok-word "apt-get") (tok-word "install"))

### tokenizes words with dots

```sh
(write (sh-tokenize "file.txt"))
```
---
    ((tok-word "file.txt"))

### tokenizes words with slashes

```sh
(write (sh-tokenize "/usr/bin/env"))
```
---
    ((tok-word "/usr/bin/env"))

### tokenizes assignments

```sh
(write (sh-tokenize "FOO=bar"))
```
---
    ((tok-word "FOO=bar"))

## sh-word dollar

### tokenizes dollar variable as word

```sh
(write (sh-tokenize "echo $HOME"))
```
---
    ((tok-word "echo") (tok-word "$HOME"))

### tokenizes dollar-question

```sh
(write (sh-tokenize "echo $?"))
```
---
    ((tok-word "echo") (tok-word "$?"))

### tokenizes dollar-dollar

```sh
(write (sh-tokenize "echo $$"))
```
---
    ((tok-word "echo") (tok-word "$$"))

### tokenizes dollar in assignment

```sh
(write (sh-tokenize "FOO=$BAR"))
```
---
    ((tok-word "FOO=$BAR"))

## integration

### tokenizes a simple pipeline

```sh
(write (sh-tokenize "echo hello | grep h"))
```
---
    ((tok-word "echo") (tok-word "hello") (tok-op "|") (tok-word "grep") (tok-word "h"))

### tokenizes a redirect

```sh
(write (sh-tokenize "cat < input.txt > output.txt"))
```
---
    ((tok-word "cat") (tok-op "<") (tok-word "input.txt") (tok-op ">") (tok-word "output.txt"))

### tokenizes a compound command

```sh
(write (sh-tokenize "if true; then echo yes; fi"))
```
---
    ((tok-word "if") (tok-word "true") (tok-op ";") (tok-word "then") (tok-word "echo") (tok-word "yes") (tok-op ";") (tok-word "fi"))

### tokenizes background job

```sh
(write (sh-tokenize "sleep 10 &"))
```
---
    ((tok-word "sleep") (tok-word "10") (tok-op "&"))

### tokenizes and-list

```sh
(write (sh-tokenize "make && make install"))
```
---
    ((tok-word "make") (tok-op "&&") (tok-word "make") (tok-word "install"))

### tokenizes empty input

```sh
(null? (sh-tokenize ""))
```
---
    #t

### tokenizes whitespace-only input

```sh
(null? (sh-tokenize "   "))
```
---
    #t

