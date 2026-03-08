# 20-lib-regex.spec.sh -- Tests for regex type and operations
# Spec: Section 20 - Lib: Regex

describe 'regex literal'
  it 'writes exact pattern' \
    '(write #/abc/)' '#/abc/'
  it 'writes empty pattern' \
    '(write #//)' '#//'
  it 'writes pattern with star' \
    '(write #/ab*c/)' '#/ab*c/'
  it 'writes pattern with plus' \
    '(write #/a+b/)' '#/a+b/'
  it 'writes pattern with optional' \
    '(write #/a?b/)' '#/a?b/'
  it 'writes pattern with dot' \
    '(write #/a.b/)' '#/a.b/'
  it 'writes pattern with escaped dot' \
    '(write #/a\.b/)' '#/a\.b/'
  it 'writes pattern with escaped backslash' \
    '(write #/a\\b/)' '#/a\\b/'

describe 'regex?'
  it 'returns t for a regex' \
    '(regex? #/abc/)' 't'
  it 'returns nil for a string' \
    '(if (regex? "abc") "yes" "no")' '"no"'
  it 'returns nil for a number' \
    '(if (regex? 42) "yes" "no")' '"no"'

describe 'regex literal matching'
  it 'matches exact string' \
    '(#/abc/ "abc")' 't'
  it 'rejects different string' \
    '(if (#/abc/ "abd") "yes" "no")' '"no"'
  it 'rejects partial match (input too short)' \
    '(if (#/abc/ "ab") "yes" "no")' '"no"'
  it 'rejects partial match (input too long)' \
    '(if (#/abc/ "abcd") "yes" "no")' '"no"'
  it 'matches empty pattern against empty string' \
    '(#// "")' 't'
  it 'rejects non-empty string against empty pattern' \
    '(if (#// "a") "yes" "no")' '"no"'
  it 'matches single character' \
    '(#/x/ "x")' 't'

describe 'regex dot wildcard'
  it 'matches any single character' \
    '(#/./ "x")' 't'
  it 'matches dot in middle' \
    '(#/a.c/ "abc")' 't'
  it 'matches dot with different char' \
    '(#/a.c/ "axc")' 't'
  it 'rejects dot against empty' \
    '(if (#/./ "") "yes" "no")' '"no"'

describe 'regex star quantifier'
  it 'matches zero occurrences' \
    '(#/ab*c/ "ac")' 't'
  it 'matches one occurrence' \
    '(#/ab*c/ "abc")' 't'
  it 'matches multiple occurrences' \
    '(#/ab*c/ "abbbc")' 't'
  it 'matches star at end' \
    '(#/ab*/ "abbb")' 't'
  it 'matches star at end zero times' \
    '(#/ab*/ "a")' 't'
  it 'matches only stars' \
    '(#/a*/ "aaa")' 't'
  it 'matches empty with star' \
    '(#/a*/ "")' 't'

describe 'regex plus quantifier'
  it 'matches one occurrence' \
    '(#/ab+c/ "abc")' 't'
  it 'matches multiple occurrences' \
    '(#/ab+c/ "abbbc")' 't'
  it 'rejects zero occurrences' \
    '(if (#/ab+c/ "ac") "yes" "no")' '"no"'
  it 'matches plus at end' \
    '(#/ab+/ "abb")' 't'
  it 'rejects plus with no match' \
    '(if (#/ab+/ "a") "yes" "no")' '"no"'

describe 'regex optional quantifier'
  it 'matches with the optional char' \
    '(#/ab?c/ "abc")' 't'
  it 'matches without the optional char' \
    '(#/ab?c/ "ac")' 't'
  it 'rejects multiple of optional' \
    '(if (#/ab?c/ "abbc") "yes" "no")' '"no"'

describe 'regex escape sequences'
  it 'matches literal dot' \
    '(#/a\.b/ "a.b")' 't'
  it 'rejects non-dot for escaped dot' \
    '(if (#/a\.b/ "axb") "yes" "no")' '"no"'
  it 'matches literal backslash' \
    '(#/a\\b/ "a\b")' 't'
  it 'matches escaped star as literal' \
    '(#/a\*b/ "a*b")' 't'

describe 'regex backtracking'
  it 'backtracks star for correct match' \
    '(#/a.*b/ "axxb")' 't'
  it 'backtracks when greedy over-consumes' \
    '(#/.*b/ "aab")' 't'
  it 'fails when backtracking exhausted' \
    '(if (#/a.*b/ "axx") "yes" "no")' '"no"'

describe 'regex combined patterns'
  it 'matches dot-star combo' \
    '(#/a.*/ "abcdef")' 't'
  it 'matches complex pattern' \
    '(#/a.b*c/ "axbbc")' 't'
  it 'matches dot-plus combo' \
    '(#/.+/ "abc")' 't'
  it 'rejects dot-plus on empty' \
    '(if (#/.+/ "") "yes" "no")' '"no"'

describe 'type-name'
  it 'returns REGEX for a regex' \
    '(type-name #/abc/)' '"REGEX"'
