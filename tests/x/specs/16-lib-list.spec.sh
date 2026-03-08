# 16-lib-list.spec.sh -- Tests for list library
# Spec: Section 16 - Lib: Lists

# ---------------------------------------------------------
# Folds
# ---------------------------------------------------------

describe 'fold'
  it 'folds left' '(fold + 0 (list 1 2 3))' '6'
  it 'fold with subtraction' '(fold - 10 (list 1 2 3))' '4'

describe 'reduce'
  it 'reduces without initial value' '(reduce + (list 1 2 3 4))' '10'

describe 'scan'
  it 'returns intermediate values' \
    '(scan + 0 (list 1 2 3))' '(0 1 3 6)'

# ---------------------------------------------------------
# Basics
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# Iteration
# ---------------------------------------------------------

describe 'map'
  it 'applies function to each' '(map inc (list 1 2 3))' '(2 3 4)'
  it 'maps over empty' '(null? (map inc ()))' 't'

describe 'filter'
  it 'keeps matching elements' '(filter even? (list 1 2 3 4))' '(2 4)'
  it 'filters to empty' '(null? (filter negative? (list 1 2 3)))' 't'

describe 'for-each'
  it 'applies function for side effects' \
    '(null? (for-each (fn (x) x) (list 1 2 3)))' 't'

describe 'reject'
  it 'removes matching elements' '(reject even? (list 1 2 3 4))' '(1 3)'

describe 'flat-map'
  it 'maps and flattens' \
    '(flat-map (fn (x) (list x (* x 10))) (list 1 2 3))' '(1 10 2 20 3 30)'

describe 'concat'
  it 'concatenates multiple lists' \
    '(concat (list 1) (list 2 3) (list 4))' '(1 2 3 4)'
  it 'concatenates with empty' '(concat () (list 1) ())' '(1)'

# ---------------------------------------------------------
# Predicates
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# Search
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# Slicing
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# Generators
# ---------------------------------------------------------

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

# ---------------------------------------------------------
# Transformation
# ---------------------------------------------------------

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
