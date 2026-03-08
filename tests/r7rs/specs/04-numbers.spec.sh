# 04-numbers.spec.sh -- R7RS 6.2 Numbers (integer subset)

describe 'number predicates'
  it 'number? on integer' \
    '(number? 42)' 't'
  it 'number? on non-number' \
    '(null? (number? "42"))' 't'
  it 'integer? on integer' \
    '(integer? 42)' 't'
  it 'exact-integer? on integer' \
    '(exact-integer? 42)' 't'
  it 'exact? on integer' \
    '(exact? 42)' 't'
  it 'null? inexact? on integer' \
    '(null? (inexact? 42))' 't'
  it 'zero? true' \
    '(zero? 0)' 't'
  it 'zero? false' \
    '(null? (zero? 1))' 't'
  it 'positive? true' \
    '(positive? 1)' 't'
  it 'negative? true' \
    '(negative? (- 0 1))' 't'
  it 'odd? true' \
    '(odd? 3)' 't'
  it 'even? true' \
    '(even? 4)' 't'
  it 'odd? false' \
    '(null? (odd? 4))' 't'
  it 'even? false' \
    '(null? (even? 3))' 't'

describe 'arithmetic'
  it 'addition' \
    '(+ 3 4)' '7'
  it 'addition multiple' \
    '(+ 1 2 3 4)' '10'
  it 'subtraction' \
    '(- 10 3)' '7'
  it 'multiplication' \
    '(* 2 3 4)' '24'
  it 'integer division' \
    '(/ 10 3)' '3'
  it 'nested arithmetic' \
    '(+ (* 2 3) (- 10 4))' '12'
  it 'abs positive' \
    '(abs 7)' '7'
  it 'abs negative' \
    '(abs (- 0 7))' '7'
  it 'max' \
    '(max 3 4)' '4'
  it 'min' \
    '(min 3 4)' '3'
  it 'square' \
    '(square 5)' '25'
  it 'square negative' \
    '(square (- 0 3))' '9'

describe 'quotient and remainder'
  it 'quotient positive' \
    '(quotient 10 3)' '3'
  it 'remainder positive' \
    '(remainder 10 3)' '1'
  it 'modulo positive' \
    '(modulo 10 3)' '1'
  it 'truncate-quotient' \
    '(truncate-quotient 10 3)' '3'
  it 'truncate-remainder' \
    '(truncate-remainder 10 3)' '1'
  it 'floor-quotient positive' \
    '(floor-quotient 7 2)' '3'
  it 'floor-remainder positive' \
    '(floor-remainder 7 2)' '1'
  it 'floor-quotient negative dividend' \
    '(floor-quotient (- 0 7) 2)' '-4'
  it 'floor-remainder negative dividend' \
    '(floor-remainder (- 0 7) 2)' '1'

describe 'gcd and lcm'
  it 'gcd of two numbers' \
    '(gcd 12 8)' '4'
  it 'gcd with zero' \
    '(gcd 5 0)' '5'
  it 'lcm of two numbers' \
    '(lcm 4 6)' '12'
  it 'lcm with zero' \
    '(lcm 0 5)' '0'

describe 'expt'
  it 'expt basic' \
    '(expt 2 10)' '1024'
  it 'expt zero power' \
    '(expt 5 0)' '1'
  it 'expt power of one' \
    '(expt 7 1)' '7'

describe 'comparison'
  it 'equal numbers' \
    '(= 5 5)' 't'
  it 'not equal' \
    '(null? (= 5 6))' 't'
  it 'less than' \
    '(< 1 2)' 't'
  it 'greater than' \
    '(> 2 1)' 't'
  it 'less or equal' \
    '(<= 2 2)' 't'
  it 'greater or equal' \
    '(>= 3 2)' 't'

describe 'string/number conversion'
  it 'number->string' \
    '(number->string 42)' '"42"'
  it 'string->number valid' \
    '(string->number "42")' '42'
