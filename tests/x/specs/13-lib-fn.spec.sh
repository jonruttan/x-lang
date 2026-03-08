# 13-lib-fn.spec.sh -- Tests for functional combinators
# Spec: Section 13 - Lib: Combinators

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
