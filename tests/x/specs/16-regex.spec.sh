# 16-regex.spec.sh -- Tests for regex type and operations

describe 'regex constructor'
  it 'creates a regex from a pattern' \
    '(write (regex "abc"))' '#/abc/'
  it 'creates a regex from empty pattern' \
    '(write (regex ""))' '#//'

describe 'regex?'
  it 'returns t for a regex' \
    '(regex? (regex "abc"))' 't'
  it 'returns nil for a string' \
    '(if (regex? "abc") "yes" "no")' '"no"'
  it 'returns nil for a number' \
    '(if (regex? 42) "yes" "no")' '"no"'

describe 'regex literal matching'
  it 'matches exact string' \
    '((regex "abc") "abc")' 't'
  it 'rejects different string' \
    '(if ((regex "abc") "abd") "yes" "no")' '"no"'
  it 'rejects partial match (input too short)' \
    '(if ((regex "abc") "ab") "yes" "no")' '"no"'
  it 'rejects partial match (input too long)' \
    '(if ((regex "abc") "abcd") "yes" "no")' '"no"'
  it 'matches empty pattern against empty string' \
    '((regex "") "")' 't'
  it 'rejects non-empty string against empty pattern' \
    '(if ((regex "") "a") "yes" "no")' '"no"'
  it 'matches single character' \
    '((regex "x") "x")' 't'

describe 'regex dot wildcard'
  it 'matches any single character' \
    '((regex ".") "x")' 't'
  it 'matches dot in middle' \
    '((regex "a.c") "abc")' 't'
  it 'matches dot with different char' \
    '((regex "a.c") "axc")' 't'
  it 'rejects dot against empty' \
    '(if ((regex ".") "") "yes" "no")' '"no"'

describe 'regex star quantifier'
  it 'matches zero occurrences' \
    '((regex "ab*c") "ac")' 't'
  it 'matches one occurrence' \
    '((regex "ab*c") "abc")' 't'
  it 'matches multiple occurrences' \
    '((regex "ab*c") "abbbc")' 't'
  it 'matches star at end' \
    '((regex "ab*") "abbb")' 't'
  it 'matches star at end zero times' \
    '((regex "ab*") "a")' 't'
  it 'matches only stars' \
    '((regex "a*") "aaa")' 't'
  it 'matches empty with star' \
    '((regex "a*") "")' 't'

describe 'regex plus quantifier'
  it 'matches one occurrence' \
    '((regex "ab+c") "abc")' 't'
  it 'matches multiple occurrences' \
    '((regex "ab+c") "abbbc")' 't'
  it 'rejects zero occurrences' \
    '(if ((regex "ab+c") "ac") "yes" "no")' '"no"'
  it 'matches plus at end' \
    '((regex "ab+") "abb")' 't'
  it 'rejects plus with no match' \
    '(if ((regex "ab+") "a") "yes" "no")' '"no"'

describe 'regex optional quantifier'
  it 'matches with the optional char' \
    '((regex "ab?c") "abc")' 't'
  it 'matches without the optional char' \
    '((regex "ab?c") "ac")' 't'
  it 'rejects multiple of optional' \
    '(if ((regex "ab?c") "abbc") "yes" "no")' '"no"'

describe 'regex escape sequences'
  it 'matches literal dot' \
    '((regex "a\.b") "a.b")' 't'
  it 'rejects non-dot for escaped dot' \
    '(if ((regex "a\.b") "axb") "yes" "no")' '"no"'
  it 'matches literal backslash' \
    '((regex "a\\b") "a\b")' 't'
  it 'matches escaped star as literal' \
    '((regex "a\*b") "a*b")' 't'

describe 'regex backtracking'
  it 'backtracks star for correct match' \
    '((regex "a.*b") "axxb")' 't'
  it 'backtracks when greedy over-consumes' \
    '((regex ".*b") "aab")' 't'
  it 'fails when backtracking exhausted' \
    '(if ((regex "a.*b") "axx") "yes" "no")' '"no"'

describe 'regex combined patterns'
  it 'matches dot-star combo' \
    '((regex "a.*") "abcdef")' 't'
  it 'matches complex pattern' \
    '((regex "a.b*c") "axbbc")' 't'
  it 'matches dot-plus combo' \
    '((regex ".+") "abc")' 't'
  it 'rejects dot-plus on empty' \
    '(if ((regex ".+") "") "yes" "no")' '"no"'

describe 'type-name'
  it 'returns REGEX for a regex' \
    '(type-name (regex "abc"))' '"REGEX"'
