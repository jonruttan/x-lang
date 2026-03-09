# 10-math.spec.sh -- Arithmetic and math operations

describe 'arithmetic'
  it 'addition' \
    '(+ 1 2 3)' '6'
  it 'subtraction' \
    '(- 10 3)' '7'
  it 'multiplication' \
    '(* 2 3 4)' '24'
  it 'integer division' \
    '(/ 10 3)' '3'
  it 'nested arithmetic' \
    '(+ (* 2 3) (- 10 4))' '12'
  it 'unary minus' \
    '(- 0 5)' '-5'
  it 'multiplication by zero' \
    '(* 42 0)' '0'

describe 'comparison'
  it 'equal numbers' \
    '(= 5 5)' 't'
  it 'not equal' \
    '(null? (= 5 6))' 't'
  it 'less than true' \
    '(< 1 2)' 't'
  it 'less than false' \
    '(null? (< 2 1))' 't'
  it 'greater than true' \
    '(> 2 1)' 't'
  it 'greater than false' \
    '(null? (> 1 2))' 't'
  it 'less or equal on equal' \
    '(<= 2 2)' 't'
  it 'less or equal on less' \
    '(<= 1 2)' 't'
  it 'greater or equal on equal' \
    '(>= 2 2)' 't'
  it 'greater or equal on greater' \
    '(>= 3 2)' 't'

describe 'quotient and remainder'
  it 'quotient positive' \
    '(quotient 10 3)' '3'
  it 'quotient exact' \
    '(quotient 9 3)' '3'
  it 'remainder positive' \
    '(remainder 10 3)' '1'
  it 'remainder zero' \
    '(remainder 9 3)' '0'
  it 'modulo positive' \
    '(modulo 10 3)' '1'

describe 'gcd and lcm'
  it 'gcd of two numbers' \
    '(gcd 12 8)' '4'
  it 'gcd with zero' \
    '(gcd 5 0)' '5'
  it 'gcd zero with number' \
    '(gcd 0 7)' '7'
  it 'gcd coprime' \
    '(gcd 7 13)' '1'
  it 'lcm of two numbers' \
    '(lcm 4 6)' '12'
  it 'lcm with zero' \
    '(lcm 0 5)' '0'
  it 'lcm same numbers' \
    '(lcm 5 5)' '5'

describe 'expt'
  it 'expt basic' \
    '(expt 2 10)' '1024'
  it 'expt zero power' \
    '(expt 5 0)' '1'
  it 'expt power of one' \
    '(expt 7 1)' '7'
  it 'expt small base' \
    '(expt 3 4)' '81'
