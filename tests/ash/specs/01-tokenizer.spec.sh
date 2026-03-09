# 01-tokenizer.spec.sh -- Tests for shell tokenizer

describe 'sh-whitespace'
  it 'discards spaces' \
    '(write (sh-tokenize "a b"))' \
    '((tok-word "a") (tok-word "b"))'
  it 'discards tabs' \
    '(do (def s (string-append (string-append "a" (make-string 1 (integer->char 9))) "b")) (write (sh-tokenize s)))' \
    '((tok-word "a") (tok-word "b"))'
  it 'discards multiple spaces' \
    '(write (sh-tokenize "a   b"))' \
    '((tok-word "a") (tok-word "b"))'

describe 'sh-newline'
  it 'produces a newline token' \
    '(do (def s (string-append (string-append "a" (make-string 1 (integer->char 10))) "b")) (write (sh-tokenize s)))' \
    '((tok-word "a") (tok-newline) (tok-word "b"))'

describe 'sh-comment'
  it 'discards comment to end of line' \
    '(do (def s (string-append (string-append "a # comment" (make-string 1 (integer->char 10))) "b")) (write (sh-tokenize s)))' \
    '((tok-word "a") (tok-newline) (tok-word "b"))'
  it 'discards whole-line comment' \
    '(do (def s (string-append (string-append "# comment" (make-string 1 (integer->char 10))) "b")) (write (sh-tokenize s)))' \
    '((tok-newline) (tok-word "b"))'

describe 'sh-operator single-char'
  it 'tokenizes pipe' \
    '(write (sh-tokenize "a|b"))' \
    '((tok-word "a") (tok-op "|") (tok-word "b"))'
  it 'tokenizes ampersand' \
    '(write (sh-tokenize "a&b"))' \
    '((tok-word "a") (tok-op "&") (tok-word "b"))'
  it 'tokenizes semicolon' \
    '(write (sh-tokenize "a;b"))' \
    '((tok-word "a") (tok-op ";") (tok-word "b"))'
  it 'tokenizes less-than' \
    '(write (sh-tokenize "a<b"))' \
    '((tok-word "a") (tok-op "<") (tok-word "b"))'
  it 'tokenizes greater-than' \
    '(write (sh-tokenize "a>b"))' \
    '((tok-word "a") (tok-op ">") (tok-word "b"))'
  it 'tokenizes open-paren' \
    '(write (sh-tokenize "(a)"))' \
    '((tok-op "(") (tok-word "a") (tok-op ")"))'

describe 'sh-operator double-char'
  it 'tokenizes or-or' \
    '(write (sh-tokenize "a||b"))' \
    '((tok-word "a") (tok-op "||") (tok-word "b"))'
  it 'tokenizes and-and' \
    '(write (sh-tokenize "a&&b"))' \
    '((tok-word "a") (tok-op "&&") (tok-word "b"))'
  it 'tokenizes double-semicolon' \
    '(write (sh-tokenize "a;;b"))' \
    '((tok-word "a") (tok-op ";;") (tok-word "b"))'
  it 'tokenizes here-doc' \
    '(write (sh-tokenize "a<<b"))' \
    '((tok-word "a") (tok-op "<<") (tok-word "b"))'
  it 'tokenizes append' \
    '(write (sh-tokenize "a>>b"))' \
    '((tok-word "a") (tok-op ">>") (tok-word "b"))'
  it 'tokenizes dup-input' \
    '(write (sh-tokenize "a<&b"))' \
    '((tok-word "a") (tok-op "<&") (tok-word "b"))'
  it 'tokenizes dup-output' \
    '(write (sh-tokenize "a>&b"))' \
    '((tok-word "a") (tok-op ">&") (tok-word "b"))'
  it 'tokenizes read-write' \
    '(write (sh-tokenize "a<>b"))' \
    '((tok-word "a") (tok-op "<>") (tok-word "b"))'
  it 'tokenizes clobber' \
    '(write (sh-tokenize "a>|b"))' \
    '((tok-word "a") (tok-op ">|") (tok-word "b"))'

describe 'sh-operator triple-char'
  it 'tokenizes here-strip' \
    '(write (sh-tokenize "a<<-b"))' \
    '((tok-word "a") (tok-op "<<-") (tok-word "b"))'

describe 'sh-sq-string'
  it 'tokenizes single-quoted string' \
    "(write (sh-tokenize \"echo 'hello world'\"))" \
    '((tok-word "echo") (tok-sq "hello world"))'
  it 'tokenizes empty single-quoted string' \
    "(write (sh-tokenize \"echo ''\"))" \
    '((tok-word "echo") (tok-sq ""))'

describe 'sh-dq-string'
  it 'tokenizes double-quoted string' \
    '(write (sh-tokenize "echo \"hello world\""))' \
    '((tok-word "echo") (tok-dq "hello world"))'
  it 'tokenizes empty double-quoted string' \
    '(write (sh-tokenize "echo \"\""))' \
    '((tok-word "echo") (tok-dq ""))'

describe 'sh-word'
  it 'tokenizes simple word' \
    '(write (sh-tokenize "echo"))' \
    '((tok-word "echo"))'
  it 'tokenizes multiple words' \
    '(write (sh-tokenize "echo hello world"))' \
    '((tok-word "echo") (tok-word "hello") (tok-word "world"))'
  it 'tokenizes words with hyphens' \
    '(write (sh-tokenize "apt-get install"))' \
    '((tok-word "apt-get") (tok-word "install"))'
  it 'tokenizes words with dots' \
    '(write (sh-tokenize "file.txt"))' \
    '((tok-word "file.txt"))'
  it 'tokenizes words with slashes' \
    '(write (sh-tokenize "/usr/bin/env"))' \
    '((tok-word "/usr/bin/env"))'
  it 'tokenizes assignments' \
    '(write (sh-tokenize "FOO=bar"))' \
    '((tok-word "FOO=bar"))'

describe 'integration'
  it 'tokenizes a simple pipeline' \
    '(write (sh-tokenize "echo hello | grep h"))' \
    '((tok-word "echo") (tok-word "hello") (tok-op "|") (tok-word "grep") (tok-word "h"))'
  it 'tokenizes a redirect' \
    '(write (sh-tokenize "cat < input.txt > output.txt"))' \
    '((tok-word "cat") (tok-op "<") (tok-word "input.txt") (tok-op ">") (tok-word "output.txt"))'
  it 'tokenizes a compound command' \
    '(write (sh-tokenize "if true; then echo yes; fi"))' \
    '((tok-word "if") (tok-word "true") (tok-op ";") (tok-word "then") (tok-word "echo") (tok-word "yes") (tok-op ";") (tok-word "fi"))'
  it 'tokenizes background job' \
    '(write (sh-tokenize "sleep 10 &"))' \
    '((tok-word "sleep") (tok-word "10") (tok-op "&"))'
  it 'tokenizes and-list' \
    '(write (sh-tokenize "make && make install"))' \
    '((tok-word "make") (tok-op "&&") (tok-word "make") (tok-word "install"))'
  it 'tokenizes empty input' \
    '(null? (sh-tokenize ""))' \
    't'
  it 'tokenizes whitespace-only input' \
    '(null? (sh-tokenize "   "))' \
    't'
