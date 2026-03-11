
== sh-whitespace

-- discards spaces
(write (sh-tokenize "a b"))
---
((tok-word "a") (tok-word "b"))

-- discards tabs
(do (def s (string-append (string-append "a" (make-string 1 (integer->char 9))) "b")) (write (sh-tokenize s)))
---
((tok-word "a") (tok-word "b"))

-- discards multiple spaces
(write (sh-tokenize "a   b"))
---
((tok-word "a") (tok-word "b"))

== sh-newline

-- produces a newline token
(do (def s (string-append (string-append "a" (make-string 1 (integer->char 10))) "b")) (write (sh-tokenize s)))
---
((tok-word "a") (tok-newline) (tok-word "b"))

== sh-comment

-- discards comment to end of line
(do (def s (string-append (string-append "a # comment" (make-string 1 (integer->char 10))) "b")) (write (sh-tokenize s)))
---
((tok-word "a") (tok-newline) (tok-word "b"))

-- discards whole-line comment
(do (def s (string-append (string-append "# comment" (make-string 1 (integer->char 10))) "b")) (write (sh-tokenize s)))
---
((tok-newline) (tok-word "b"))

== sh-operator single-char

-- tokenizes pipe
(write (sh-tokenize "a|b"))
---
((tok-word "a") (tok-op "|") (tok-word "b"))

-- tokenizes ampersand
(write (sh-tokenize "a&b"))
---
((tok-word "a") (tok-op "&") (tok-word "b"))

-- tokenizes semicolon
(write (sh-tokenize "a;b"))
---
((tok-word "a") (tok-op ";") (tok-word "b"))

-- tokenizes less-than
(write (sh-tokenize "a<b"))
---
((tok-word "a") (tok-op "<") (tok-word "b"))

-- tokenizes greater-than
(write (sh-tokenize "a>b"))
---
((tok-word "a") (tok-op ">") (tok-word "b"))

-- tokenizes open-paren
(write (sh-tokenize "(a)"))
---
((tok-op "(") (tok-word "a") (tok-op ")"))

== sh-operator double-char

-- tokenizes or-or
(write (sh-tokenize "a||b"))
---
((tok-word "a") (tok-op "||") (tok-word "b"))

-- tokenizes and-and
(write (sh-tokenize "a&&b"))
---
((tok-word "a") (tok-op "&&") (tok-word "b"))

-- tokenizes double-semicolon
(write (sh-tokenize "a;;b"))
---
((tok-word "a") (tok-op ";;") (tok-word "b"))

-- tokenizes here-doc
(write (sh-tokenize "a<<b"))
---
((tok-word "a") (tok-op "<<") (tok-word "b"))

-- tokenizes append
(write (sh-tokenize "a>>b"))
---
((tok-word "a") (tok-op ">>") (tok-word "b"))

-- tokenizes dup-input
(write (sh-tokenize "a<&b"))
---
((tok-word "a") (tok-op "<&") (tok-word "b"))

-- tokenizes dup-output
(write (sh-tokenize "a>&b"))
---
((tok-word "a") (tok-op ">&") (tok-word "b"))

-- tokenizes read-write
(write (sh-tokenize "a<>b"))
---
((tok-word "a") (tok-op "<>") (tok-word "b"))

-- tokenizes clobber
(write (sh-tokenize "a>|b"))
---
((tok-word "a") (tok-op ">|") (tok-word "b"))

== sh-operator triple-char

-- tokenizes here-strip
(write (sh-tokenize "a<<-b"))
---
((tok-word "a") (tok-op "<<-") (tok-word "b"))

== sh-sq-string

-- tokenizes single-quoted string
(write (sh-tokenize "echo 'hello world'"))
---
((tok-word "echo") (tok-sq "hello world"))

-- tokenizes empty single-quoted string
(write (sh-tokenize "echo ''"))
---
((tok-word "echo") (tok-sq ""))

== sh-dq-string

-- tokenizes double-quoted string
(write (sh-tokenize "echo \"hello world\""))
---
((tok-word "echo") (tok-dq "hello world"))

-- tokenizes empty double-quoted string
(write (sh-tokenize "echo \"\""))
---
((tok-word "echo") (tok-dq ""))

== sh-word

-- tokenizes simple word
(write (sh-tokenize "echo"))
---
((tok-word "echo"))

-- tokenizes multiple words
(write (sh-tokenize "echo hello world"))
---
((tok-word "echo") (tok-word "hello") (tok-word "world"))

-- tokenizes words with hyphens
(write (sh-tokenize "apt-get install"))
---
((tok-word "apt-get") (tok-word "install"))

-- tokenizes words with dots
(write (sh-tokenize "file.txt"))
---
((tok-word "file.txt"))

-- tokenizes words with slashes
(write (sh-tokenize "/usr/bin/env"))
---
((tok-word "/usr/bin/env"))

-- tokenizes assignments
(write (sh-tokenize "FOO=bar"))
---
((tok-word "FOO=bar"))

== sh-word dollar

-- tokenizes dollar variable as word
(write (sh-tokenize "echo $HOME"))
---
((tok-word "echo") (tok-word "$HOME"))

-- tokenizes dollar-question
(write (sh-tokenize "echo $?"))
---
((tok-word "echo") (tok-word "$?"))

-- tokenizes dollar-dollar
(write (sh-tokenize "echo $$"))
---
((tok-word "echo") (tok-word "$$"))

-- tokenizes dollar in assignment
(write (sh-tokenize "FOO=$BAR"))
---
((tok-word "FOO=$BAR"))

== integration

-- tokenizes a simple pipeline
(write (sh-tokenize "echo hello | grep h"))
---
((tok-word "echo") (tok-word "hello") (tok-op "|") (tok-word "grep") (tok-word "h"))

-- tokenizes a redirect
(write (sh-tokenize "cat < input.txt > output.txt"))
---
((tok-word "cat") (tok-op "<") (tok-word "input.txt") (tok-op ">") (tok-word "output.txt"))

-- tokenizes a compound command
(write (sh-tokenize "if true; then echo yes; fi"))
---
((tok-word "if") (tok-word "true") (tok-op ";") (tok-word "then") (tok-word "echo") (tok-word "yes") (tok-op ";") (tok-word "fi"))

-- tokenizes background job
(write (sh-tokenize "sleep 10 &"))
---
((tok-word "sleep") (tok-word "10") (tok-op "&"))

-- tokenizes and-list
(write (sh-tokenize "make && make install"))
---
((tok-word "make") (tok-op "&&") (tok-word "make") (tok-word "install"))

-- tokenizes empty input
(null? (sh-tokenize ""))
---
t

-- tokenizes whitespace-only input
(null? (sh-tokenize "   "))
---
t
