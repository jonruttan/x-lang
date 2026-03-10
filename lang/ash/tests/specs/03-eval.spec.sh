# 03-eval.spec.sh -- Tests for shell evaluator

describe 'sh-eval echo'
  it 'echoes a word' \
    '(do (sh-eval "echo hello") ())' \
    'hello'
  it 'echoes multiple words' \
    '(do (sh-eval "echo hello world") ())' \
    'hello world'
  it 'echoes empty line returns 0' \
    '(sh-eval "echo")' \
    '0'

describe 'sh-eval builtins'
  it 'true returns 0' \
    '(sh-eval "true")' \
    '0'
  it 'false returns 1' \
    '(sh-eval "false")' \
    '1'
  it 'colon returns 0' \
    '(sh-eval ":")' \
    '0'

describe 'sh-eval test'
  it 'test string equality true' \
    '(sh-eval "test hello = hello")' \
    '0'
  it 'test string equality false' \
    '(sh-eval "test hello = world")' \
    '1'
  it 'test string inequality true' \
    '(sh-eval "test hello != world")' \
    '0'
  it 'test -n non-empty' \
    '(sh-eval "test -n hello")' \
    '0'
  it 'test -z empty' \
    '(sh-eval "test -z \"\"")' \
    '0'

describe 'sh-eval sequence'
  it 'runs two commands in sequence' \
    '(do (sh-eval "echo a; echo b") %sh-status)' \
    '0'
  it 'last command in sequence sets status' \
    '(do (sh-eval "true; false") %sh-status)' \
    '1'

describe 'sh-eval and-list'
  it 'and runs second if first succeeds' \
    '(do (sh-eval "true && echo yes") ())' \
    'yes'
  it 'and skips second if first fails' \
    '(sh-eval "false && echo no")' \
    '1'

describe 'sh-eval or-list'
  it 'or skips second if first succeeds' \
    '(sh-eval "true || echo no")' \
    '0'
  it 'or runs second if first fails' \
    '(do (sh-eval "false || echo fallback") ())' \
    'fallback'

describe 'sh-eval if'
  it 'if true then branch' \
    '(do (sh-eval "if true; then echo yes; fi") ())' \
    'yes'
  it 'if false else branch' \
    '(do (sh-eval "if false; then echo yes; else echo no; fi") ())' \
    'no'

describe 'sh-eval for'
  it 'iterates and sets variable' \
    '(do (sh-eval "for i in a b c; do :; done") (string=? (sh-getenv "i") "c"))' \
    't'
  it 'for loop returns 0' \
    '(sh-eval "for i in x y z; do :; done")' \
    '0'

describe 'sh-eval variable'
  it 'expands environment variable' \
    '(do (sh-eval "export FOO=hello; echo $FOO") ())' \
    'hello'
  it 'expands dollar-question' \
    '(do (sh-eval "true; echo $?") ())' \
    '0'
  it 'expands dollar-question after false' \
    '(do (sh-eval "false; echo $?") ())' \
    '1'

describe 'sh-eval external'
  it 'runs external command' \
    '(do (sh-eval "/bin/echo ext-ok") ())' \
    'ext-ok'

describe 'sh-eval pipeline'
  it 'pipes two commands' \
    '(do (sh-eval "/bin/echo hello | /usr/bin/tr h H") ())' \
    'Hello'

describe 'sh-eval empty'
  it 'empty input returns 0' \
    '(sh-eval "")' \
    '0'
