# 08-chars.spec.sh -- R7RS 6.6 Characters

describe 'char basics'
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

describe 'char comparison'
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

describe 'char classification'
  it 'char-alphabetic? lowercase' \
    '(char-alphabetic? #\a)' 't'
  it 'char-alphabetic? uppercase' \
    '(char-alphabetic? #\Z)' 't'
  it 'char-alphabetic? digit' \
    '(null? (char-alphabetic? #\0))' 't'
  it 'char-alphabetic? space' \
    '(null? (char-alphabetic? #\space))' 't'
  it 'char-numeric? digit' \
    '(char-numeric? #\5)' 't'
  it 'char-numeric? letter' \
    '(null? (char-numeric? #\a))' 't'
  it 'char-whitespace? space' \
    '(char-whitespace? #\space)' 't'
  it 'char-whitespace? newline' \
    '(char-whitespace? #\newline)' 't'
  it 'char-whitespace? letter' \
    '(null? (char-whitespace? #\a))' 't'
  it 'char-upper-case? uppercase' \
    '(char-upper-case? #\A)' 't'
  it 'char-upper-case? lowercase' \
    '(null? (char-upper-case? #\a))' 't'
  it 'char-lower-case? lowercase' \
    '(char-lower-case? #\a)' 't'
  it 'char-lower-case? uppercase' \
    '(null? (char-lower-case? #\A))' 't'

describe 'char case conversion'
  it 'char-upcase lowercase' \
    '(char-upcase #\a)' 'A'
  it 'char-upcase already upper' \
    '(char-upcase #\A)' 'A'
  it 'char-upcase digit unchanged' \
    '(char-upcase #\5)' '5'
  it 'char-downcase uppercase' \
    '(char-downcase #\A)' 'a'
  it 'char-downcase already lower' \
    '(char-downcase #\a)' 'a'
  it 'char-foldcase uppercase' \
    '(char-foldcase #\A)' 'a'
  it 'char-foldcase lowercase' \
    '(char-foldcase #\a)' 'a'

describe 'char case-insensitive comparison'
  it 'char-ci=? same case' \
    '(char-ci=? #\a #\a)' 't'
  it 'char-ci=? different case' \
    '(char-ci=? #\a #\A)' 't'
  it 'char-ci=? not equal' \
    '(null? (char-ci=? #\a #\b))' 't'
  it 'char-ci<? less' \
    '(char-ci<? #\a #\B)' 't'
  it 'char-ci>? greater' \
    '(char-ci>? #\B #\a)' 't'
