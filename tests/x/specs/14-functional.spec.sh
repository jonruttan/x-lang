# 14-functional.spec.sh -- Tests for x.x standard library functions

# =========================================================
# Functional combinators
# =========================================================

describe 'identity'
  it 'returns its argument' '(identity 42)' '42'
  it 'returns a list' '(identity (list 1 2))' '(1 2)'

describe 'const'
  it 'returns a constant function' '((const 5) 99)' '5'

describe 'compose'
  it 'composes two functions' '((compose inc inc) 3)' '5'
  it 'applies right-to-left' '((compose (fn (x) (* x 2)) inc) 3)' '8'

describe 'pipe'
  it 'pipes two functions left-to-right' '((pipe inc (fn (x) (* x 2))) 3)' '8'

describe 'curry'
  it 'partially applies first argument' '((curry + 10) 5)' '15'

describe 'flip'
  it 'swaps argument order' '((flip -) 3 10)' '7'

describe 'tap'
  it 'returns original value' '((tap identity) 42)' '42'

describe 'complement'
  it 'negates a predicate' '((complement even?) 3)' 't'
  it 'negates a true result' '(if ((complement even?) 4) "odd" "even")' '"even"'

describe 'partial'
  it 'partially applies one argument' '((partial * 3) 4)' '12'
  it 'partially applies with subtract' '((partial - 100) 30)' '70'

describe 'juxt'
  it 'applies multiple functions' '((juxt inc dec) 5)' '(6 4)'

describe 'both'
  it 'returns t when both pass' '((both positive? even?) 4)' 't'
  it 'returns nil when one fails' '(if ((both positive? even?) 3) "y" "n")' '"n"'

describe 'either'
  it 'returns t when one passes' '((either positive? even?) -2)' 't'
  it 'returns nil when both fail' '(if ((either positive? even?) -3) "y" "n")' '"n"'

describe 'all-pass'
  it 'all predicates pass' '((all-pass (list positive? even?)) 4)' 't'
  it 'fails when one fails' '(if ((all-pass (list positive? even?)) 3) "y" "n")' '"n"'

describe 'any-pass'
  it 'one predicate passes' '((any-pass (list negative? even?)) 4)' 't'
  it 'fails when all fail' '(if ((any-pass (list negative? even?)) 3) "y" "n")' '"n"'

# =========================================================
# Math
# =========================================================

describe 'inc'
  it 'increments by one' '(inc 5)' '6'

describe 'dec'
  it 'decrements by one' '(dec 5)' '4'

describe 'negate'
  it 'negates positive' '(negate 5)' '-5'
  it 'negates negative' '(negate -3)' '3'

describe 'abs'
  it 'positive stays positive' '(abs 5)' '5'
  it 'negative becomes positive' '(abs -5)' '5'
  it 'zero stays zero' '(abs 0)' '0'

describe 'min'
  it 'returns smaller' '(min 3 7)' '3'
  it 'returns smaller when first is larger' '(min 7 3)' '3'

describe 'max'
  it 'returns larger' '(max 3 7)' '7'
  it 'returns larger when first is larger' '(max 7 3)' '7'

describe 'clamp'
  it 'clamps below minimum' '(clamp 0 10 -5)' '0'
  it 'clamps above maximum' '(clamp 0 10 15)' '10'
  it 'passes through in range' '(clamp 0 10 5)' '5'

describe 'min-by'
  it 'returns min by key function' '(min-by abs 3 -5)' '3'

describe 'max-by'
  it 'returns max by key function' '(max-by abs 3 -5)' '-5'

describe 'sum'
  it 'sums a list' '(sum (list 1 2 3 4))' '10'
  it 'sum of empty is zero' '(sum ())' '0'

describe 'product'
  it 'multiplies a list' '(product (list 1 2 3 4))' '24'
  it 'product of empty is one' '(product ())' '1'

# =========================================================
# Number predicates
# =========================================================

describe 'zero?'
  it 'true for zero' '(zero? 0)' 't'
  it 'false for non-zero' '(if (zero? 5) "y" "n")' '"n"'

describe 'positive?'
  it 'true for positive' '(positive? 5)' 't'
  it 'false for negative' '(if (positive? -1) "y" "n")' '"n"'

describe 'negative?'
  it 'true for negative' '(negative? -5)' 't'
  it 'false for positive' '(if (negative? 1) "y" "n")' '"n"'

describe 'even?'
  it 'true for even' '(even? 4)' 't'
  it 'false for odd' '(if (even? 3) "y" "n")' '"n"'

describe 'odd?'
  it 'true for odd' '(odd? 3)' 't'
  it 'false for even' '(if (odd? 4) "y" "n")' '"n"'

# =========================================================
# Boolean / Logic
# =========================================================

describe 'boolean?'
  it 'true for t' '(boolean? t)' 't'
  it 'true for nil' '(boolean? ())' 't'
  it 'false for number' '(if (boolean? 42) "y" "n")' '"n"'

describe 'default-to'
  it 'returns value when non-nil' '(default-to 0 42)' '42'
  it 'returns default when nil' '(default-to 0 ())' '0'

describe 'until'
  it 'iterates until predicate holds' \
    '(until (fn (x) (> x 10)) inc 1)' '11'

describe 'equal?'
  it 'compares numbers' '(equal? 5 5)' 't'
  it 'compares different numbers' '(if (equal? 5 6) "y" "n")' '"n"'
  it 'compares strings' '(equal? "hi" "hi")' 't'
  it 'compares nil' '(equal? () ())' 't'

# =========================================================
# List folds
# =========================================================

describe 'fold'
  it 'folds left' '(fold + 0 (list 1 2 3))' '6'
  it 'fold with subtraction' '(fold - 10 (list 1 2 3))' '4'

describe 'reduce'
  it 'reduces without initial value' '(reduce + (list 1 2 3 4))' '10'

describe 'scan'
  it 'returns intermediate values' \
    '(scan + 0 (list 1 2 3))' '(0 1 3 6)'

# =========================================================
# List basics
# =========================================================

describe 'length'
  it 'counts elements' '(length (list 1 2 3))' '3'
  it 'empty list is zero' '(length ())' '0'

describe 'nth'
  it 'gets element at index' '(nth 1 (list 10 20 30))' '20'
  it 'gets first element' '(nth 0 (list 10 20 30))' '10'

describe 'last'
  it 'returns last element' '(last (list 1 2 3))' '3'
  it 'returns only element' '(last (list 42))' '42'

describe 'init'
  it 'returns all but last' '(init (list 1 2 3))' '(1 2)'

describe 'append'
  it 'concatenates two lists' '(append (list 1 2) (list 3 4))' '(1 2 3 4)'
  it 'appends to empty' '(append () (list 1 2))' '(1 2)'

describe 'prepend'
  it 'adds to front' '(prepend 0 (list 1 2))' '(0 1 2)'

describe 'reverse'
  it 'reverses a list' '(reverse (list 1 2 3))' '(3 2 1)'
  it 'reverses empty' '(null? (reverse ()))' 't'

describe 'flatten'
  it 'flattens nested lists' '(flatten (list 1 (list 2 (list 3))))' '(1 2 3)'
  it 'flat list unchanged' '(flatten (list 1 2 3))' '(1 2 3)'

# =========================================================
# List iteration
# =========================================================

describe 'map'
  it 'applies function to each' '(map inc (list 1 2 3))' '(2 3 4)'
  it 'maps over empty' '(null? (map inc ()))' 't'

describe 'filter'
  it 'keeps matching elements' '(filter even? (list 1 2 3 4))' '(2 4)'
  it 'filters to empty' '(null? (filter negative? (list 1 2 3)))' 't'

describe 'reject'
  it 'removes matching elements' '(reject even? (list 1 2 3 4))' '(1 3)'

describe 'flat-map'
  it 'maps and flattens' \
    '(flat-map (fn (x) (list x (* x 10))) (list 1 2 3))' '(1 10 2 20 3 30)'

describe 'concat'
  it 'concatenates multiple lists' \
    '(concat (list 1) (list 2 3) (list 4))' '(1 2 3 4)'
  it 'concatenates with empty' '(concat () (list 1) ())' '(1)'

# =========================================================
# List search
# =========================================================

describe 'find'
  it 'finds first match' '(find even? (list 1 3 4 6))' '4'
  it 'returns nil when not found' '(null? (find negative? (list 1 2 3)))' 't'

describe 'find-index'
  it 'returns index of first match' '(find-index even? (list 1 3 4 6))' '2'
  it 'returns -1 when not found' '(find-index negative? (list 1 2 3))' '-1'

describe 'index-of'
  it 'finds element index' '(index-of 30 (list 10 20 30))' '2'
  it 'returns -1 when not found' '(index-of 99 (list 10 20 30))' '-1'

describe 'includes?'
  it 'finds element in list' '(includes? 3 (list 1 2 3))' 't'
  it 'returns nil when not found' '(if (includes? 9 (list 1 2 3)) "y" "n")' '"n"'

describe 'count'
  it 'counts matching elements' '(count even? (list 1 2 3 4 5 6))' '3'
  it 'returns zero for no matches' '(count negative? (list 1 2 3))' '0'

# =========================================================
# List slicing
# =========================================================

describe 'take'
  it 'takes first n elements' '(take 2 (list 1 2 3 4))' '(1 2)'
  it 'takes zero' '(null? (take 0 (list 1 2 3)))' 't'
  it 'takes more than available' '(take 5 (list 1 2))' '(1 2)'

describe 'drop'
  it 'drops first n elements' '(drop 2 (list 1 2 3 4))' '(3 4)'
  it 'drops zero' '(drop 0 (list 1 2 3))' '(1 2 3)'

describe 'take-while'
  it 'takes while predicate holds' \
    '(take-while positive? (list 1 2 -3 4))' '(1 2)'
  it 'takes nothing when first fails' \
    '(null? (take-while negative? (list 1 2 3)))' 't'

describe 'drop-while'
  it 'drops while predicate holds' \
    '(drop-while positive? (list 1 2 -3 4))' '(-3 4)'

describe 'split-at'
  it 'splits list at index' \
    '(split-at 2 (list 1 2 3 4))' '((1 2) (3 4))'

describe 'slice'
  it 'extracts sublist' '(slice 1 3 (list 10 20 30 40 50))' '(20 30)'

# =========================================================
# List generators
# =========================================================

describe 'range'
  it 'generates ascending range' '(range 0 5)' '(0 1 2 3 4)'
  it 'empty when start >= end' '(null? (range 5 5))' 't'

describe 'repeat'
  it 'repeats a value' '(repeat 0 3)' '(0 0 0)'
  it 'repeats zero times' '(null? (repeat 0 0))' 't'

describe 'times'
  it 'calls function n times' '(times identity 4)' '(0 1 2 3)'
  it 'applies function to indices' '(times (fn (i) (* i i)) 4)' '(0 1 4 9)'

describe 'unfold'
  it 'builds a list from seed' \
    '(unfold (fn (x) (> x 5)) identity inc 1)' '(1 2 3 4 5)'

describe 'iterate'
  it 'generates repeated applications' \
    '(iterate (fn (x) (* x 2)) 4 1)' '(1 2 4 8)'

describe 'zip'
  it 'zips two lists' \
    '(zip (list 1 2 3) (list 4 5 6))' '((1 4) (2 5) (3 6))'
  it 'stops at shorter list' \
    '(zip (list 1 2) (list 3 4 5))' '((1 3) (2 4))'

describe 'zip-with'
  it 'zips with combining function' \
    '(zip-with + (list 1 2 3) (list 10 20 30))' '(11 22 33)'

# =========================================================
# List predicates
# =========================================================

describe 'any?'
  it 'returns t when one matches' '(any? even? (list 1 2 3))' 't'
  it 'returns nil when none match' '(if (any? negative? (list 1 2 3)) "y" "n")' '"n"'

describe 'every?'
  it 'returns t when all match' '(every? positive? (list 1 2 3))' 't'
  it 'returns nil when one fails' '(if (every? even? (list 2 3 4)) "y" "n")' '"n"'

describe 'none?'
  it 'returns t when none match' '(none? negative? (list 1 2 3))' 't'
  it 'returns nil when one matches' '(if (none? even? (list 1 2 3)) "y" "n")' '"n"'

describe 'empty?'
  it 'true for empty list' '(empty? ())' 't'
  it 'false for non-empty' '(if (empty? (list 1)) "y" "n")' '"n"'

# =========================================================
# List transformation
# =========================================================

describe 'partition'
  it 'splits by predicate' \
    '(partition even? (list 1 2 3 4 5 6))' '((2 4 6) (1 3 5))'

describe 'group-by'
  it 'groups by key function' \
    '(length (group-by even? (list 1 2 3 4 5)))' '2'

describe 'sort'
  it 'sorts ascending' '(sort < (list 5 3 1 4 2))' '(1 2 3 4 5)'
  it 'sorts descending' '(sort > (list 1 3 2))' '(3 2 1)'
  it 'sorts single element' '(sort < (list 1))' '(1)'
  it 'sorts empty' '(null? (sort < ()))' 't'

describe 'sort-by'
  it 'sorts by key function' \
    '(sort-by abs (list 3 -1 -2))' '(-1 -2 3)'

describe 'uniq'
  it 'removes consecutive duplicates' \
    '(uniq (list 1 1 2 2 3 3))' '(1 2 3)'
  it 'keeps non-consecutive duplicates' \
    '(uniq (list 1 2 1 2))' '(1 2 1 2)'

describe 'uniq-by'
  it 'removes consecutive duplicates by key' \
    '(length (uniq-by abs (list 1 -1 2 -2 3)))' '3'

describe 'intersperse'
  it 'inserts separator between elements' \
    '(intersperse 0 (list 1 2 3))' '(1 0 2 0 3)'
  it 'single element unchanged' '(intersperse 0 (list 1))' '(1)'

describe 'transpose'
  it 'transposes a matrix' \
    '(transpose (list (list 1 2 3) (list 4 5 6)))' '((1 4) (2 5) (3 6))'

describe 'update'
  it 'updates element at index' \
    '(update 1 99 (list 10 20 30))' '(10 99 30)'

describe 'insert'
  it 'inserts at index' \
    '(insert 1 99 (list 10 20 30))' '(10 99 20 30)'

describe 'remove'
  it 'removes n elements at start index' \
    '(remove 1 2 (list 10 20 30 40))' '(10 40)'

describe 'adjust'
  it 'applies function at index' \
    '(adjust 1 inc (list 10 20 30))' '(10 21 30)'

# =========================================================
# Association list operations
# =========================================================

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

describe 'amerge'
  it 'merges two alists' \
    '(do (def a (list (pair (lit x) 1))) (def b (list (pair (lit y) 2))) (length (amerge a b)))' '2'

describe 'from-pairs'
  it 'converts list of lists to alist' \
    '(do (def al (from-pairs (list (list (lit a) 1) (list (lit b) 2)))) (aget (lit a) al))' '1'

describe 'to-pairs'
  it 'converts alist to list of lists' \
    '(do (def al (list (pair (lit a) 1))) (first (first (to-pairs al))))' 'a'

describe 'evolve'
  it 'transforms values by matching keys' \
    '(do (def al (list (pair (lit a) 1) (pair (lit b) 2))) (aget (lit a) (evolve (list (pair (lit a) inc)) al)))' '2'

# =========================================================
# String utilities
# =========================================================

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
