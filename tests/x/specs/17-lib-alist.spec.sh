# 17-lib-alist.spec.sh -- Tests for association list library
# Spec: Section 17 - Lib: Alists

describe 'aget'
  it 'retrieves value by key' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (aget (lit b) al))' '2'
  it 'returns nil for missing key' \
    '(do (def al (list (pair (lit a) 1))) (null? (aget (lit z) al)))' 't'

describe 'aget-or'
  it 'returns value when key exists' \
    '(do (def al (list (pair (lit a) 1))) (aget-or 99 (lit a) al))' '1'
  it 'returns default when key missing' \
    '(do (def al (list (pair (lit a) 1))) (aget-or 99 (lit z) al))' '99'

describe 'ahas?'
  it 'returns t when key exists' \
    '(do (def al (list (pair (lit a) 1))) (ahas? (lit a) al))' 't'
  it 'returns nil when key missing' \
    '(do (def al (list (pair (lit a) 1))) (if (ahas? (lit z) al) "y" "n"))' '"n"'

describe 'aset'
  it 'adds key-value pair' \
    '(do (def al (list (pair (lit a) 1))) (aget (lit b) (aset (lit b) 2 al)))' '2'

describe 'adel'
  it 'removes key from alist' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (length (adel (lit a) al)))' '1'

describe 'akeys'
  it 'returns list of keys' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (akeys al))' '(a b)'

describe 'avals'
  it 'returns list of values' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (avals al))' '(1 2)'

describe 'amap'
  it 'applies function to all values' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (aget (lit a) (amap inc al)))' '2'

describe 'afilter'
  it 'filters entries by predicate' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (length (afilter (fn (e) (> (rest e) 1)) al)))' '1'

describe 'amerge'
  it 'merges two alists' \
    '(do (def a (list (pair (lit x) 1))) (def b (list (pair (lit y) 2))) (length (amerge a b)))' '2'

describe 'apick'
  it 'selects entries by key list' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))) (length (apick (list (lit a) (lit c)) al)))' '2'

describe 'aomit'
  it 'removes entries by key list' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2) (pair (lit c) 3))) (length (aomit (list (lit a)) al)))' '2'

describe 'from-pairs'
  it 'converts list of lists to alist' \
    '(do (def al (from-pairs (list (list (lit a) 1) (list (lit b) 2)))) (aget (lit a) al))' '1'

describe 'to-pairs'
  it 'converts alist to list of lists' \
    '(do (def al (list (pair (lit a) 1))) (first (first (to-pairs al))))' 'a'

describe 'evolve'
  it 'transforms values by matching keys' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (aget (lit a) (evolve (list (pair (lit a) inc)) al)))' '2'
