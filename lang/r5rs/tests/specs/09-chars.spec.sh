# 09-chars.spec.sh -- Character operations

describe 'character basics'
  it 'char? on char' \
    '(char? #\a)' 't'
  it 'char? on string' \
    '(null? (char? "a"))' 't'
  it 'char? on number' \
    '(null? (char? 65))' 't'
  it 'char->integer uppercase' \
    '(char->integer #\A)' '65'
  it 'char->integer lowercase' \
    '(char->integer #\a)' '97'
  it 'char->integer digit' \
    '(char->integer #\0)' '48'
  it 'integer->char' \
    '(integer->char 65)' 'A'
  it 'roundtrip char->int->char' \
    '(integer->char (char->integer #\z))' 'z'
  it 'char->integer space' \
    '(char->integer #\space)' '32'
  it 'char->integer newline' \
    '(char->integer #\newline)' '10'

describe 'character comparison'
  it 'char=? equal' \
    '(char=? #\a #\a)' 't'
  it 'char=? not equal' \
    '(null? (char=? #\a #\b))' 't'
  it 'char<? less' \
    '(char<? #\a #\b)' 't'
  it 'char<? not less' \
    '(null? (char<? #\b #\a))' 't'
  it 'char>? greater' \
    '(char>? #\b #\a)' 't'
  it 'char<=? equal' \
    '(char<=? #\a #\a)' 't'
  it 'char<=? less' \
    '(char<=? #\a #\b)' 't'
  it 'char>=? equal' \
    '(char>=? #\a #\a)' 't'
  it 'char>=? greater' \
    '(char>=? #\b #\a)' 't'
  it 'char>=? not greater' \
    '(null? (char>=? #\a #\b))' 't'
