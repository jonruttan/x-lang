# 18-lib-string.spec.sh -- Tests for string utility library
# Spec: Section 18 - Lib: Strings

describe 'string-empty?'
  it 'true for empty string' '(string-empty? "")' 't'
  it 'false for non-empty' '(if (string-empty? "hi") "y" "n")' '"n"'

describe 'string-join'
  it 'joins with separator' \
    '(string-join ", " (list "a" "b" "c"))' '"a, b, c"'
  it 'joins single element' '(string-join ", " (list "a"))' '"a"'
  it 'joins empty list' '(string-join ", " ())' '""'

describe 'string-repeat'
  it 'repeats a string' '(string-repeat "ab" 3)' '"ababab"'
  it 'repeats zero times' '(string-repeat "ab" 0)' '""'

describe 'string-contains?'
  it 'finds substring' '(string-contains? "ll" "hello")' 't'
  it 'returns nil for missing' \
    '(if (string-contains? "xyz" "hello") "y" "n")' '"n"'
  it 'empty substring always found' '(string-contains? "" "hello")' 't'

describe 'string-starts?'
  it 'true when starts with prefix' '(string-starts? "he" "hello")' 't'
  it 'false for non-prefix' \
    '(if (string-starts? "lo" "hello") "y" "n")' '"n"'

describe 'string-ends?'
  it 'true when ends with suffix' '(string-ends? "lo" "hello")' 't'
  it 'false for non-suffix' \
    '(if (string-ends? "he" "hello") "y" "n")' '"n"'

describe 'string-reverse'
  it 'reverses a string' '(string-reverse "hello")' '"olleh"'
  it 'reverses empty string' '(string-reverse "")' '""'
