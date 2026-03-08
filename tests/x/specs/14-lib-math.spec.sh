# 14-lib-math.spec.sh -- Tests for math library
# Spec: Section 14 - Lib: Math

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
