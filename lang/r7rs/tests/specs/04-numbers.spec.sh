# 04-numbers.spec.sh -- R7RS 6.2 Numbers

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

describe 'float predicates'
  it 'number? on float' \
    '(number? 3.14)' 't'
  it 'real? on float' \
    '(real? 3.14)' 't'
  it 'real? on integer' \
    '(real? 42)' 't'
  it 'complex? on float' \
    '(complex? 3.14)' 't'
  it 'complex? on integer' \
    '(complex? 42)' 't'
  it 'integer? on inexact integer' \
    '(integer? 3.0)' 't'
  it 'integer? on non-integer float' \
    '(null? (integer? 3.5))' 't'
  it 'exact? on float is false' \
    '(null? (exact? 3.14))' 't'
  it 'inexact? on float' \
    '(inexact? 3.14)' 't'
  it 'exact-integer? on float is false' \
    '(null? (exact-integer? 3.0))' 't'
  it 'rational? on integer' \
    '(rational? 42)' 't'
  it 'rational? on float is false' \
    '(null? (rational? 3.14))' 't'
  it 'float? on float' \
    '(float? 3.14)' 't'
  it 'float? on integer is false' \
    '(null? (float? 42))' 't'

describe 'IEEE 754 predicates'
  it 'nan? on NaN' \
    '(nan? (/ 0.0 0.0))' 't'
  it 'nan? on regular float' \
    '(null? (nan? 3.14))' 't'
  it 'nan? on integer' \
    '(null? (nan? 42))' 't'
  it 'infinite? on positive infinity' \
    '(infinite? (/ 1.0 0.0))' 't'
  it 'infinite? on negative infinity' \
    '(infinite? (/ (- 0 1.0) 0.0))' 't'
  it 'infinite? on regular float' \
    '(null? (infinite? 3.14))' 't'
  it 'finite? on regular float' \
    '(finite? 3.14)' 't'
  it 'finite? on integer' \
    '(finite? 42)' 't'
  it 'finite? on NaN' \
    '(null? (finite? (/ 0.0 0.0)))' 't'
  it 'finite? on infinity' \
    '(null? (finite? (/ 1.0 0.0)))' 't'

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

describe 'float arithmetic'
  it 'float addition' \
    '(number->string (+ 1.5 2.5))' '"4"'
  it 'float subtraction' \
    '(number->string (- 5.5 2.0))' '"3.5"'
  it 'float multiplication' \
    '(number->string (* 2.5 4.0))' '"10"'
  it 'float division' \
    '(number->string (/ 7.0 2.0))' '"3.5"'
  it 'mixed int+float addition' \
    '(float? (+ 1 2.5))' 't'
  it 'mixed int+float result' \
    '(number->string (+ 1 2.5))' '"3.5"'
  it 'mixed subtraction' \
    '(number->string (- 10 2.5))' '"7.5"'
  it 'mixed multiplication' \
    '(number->string (* 3 2.5))' '"7.5"'
  it 'exactness contagion: int+float is float' \
    '(inexact? (+ 1 2.0))' 't'
  it 'unary negation of float' \
    '(number->string (- 3.5))' '"-3.5"'

describe 'float math functions'
  it 'abs on negative float' \
    '(number->string (abs (- 0 2.5)))' '"2.5"'
  it 'abs on positive float' \
    '(number->string (abs 2.5))' '"2.5"'
  it 'zero? on 0.0' \
    '(zero? 0.0)' 't'
  it 'zero? on non-zero float' \
    '(null? (zero? 0.1))' 't'
  it 'positive? on positive float' \
    '(positive? 3.14)' 't'
  it 'positive? on negative float' \
    '(null? (positive? (- 0 3.14)))' 't'
  it 'negative? on negative float' \
    '(negative? (- 0 3.14))' 't'
  it 'min with mixed types' \
    '(= (min 5 2.5) 2.5)' 't'
  it 'max with mixed types' \
    '(= (max 1 2.5) 2.5)' 't'
  it 'square on float' \
    '(number->string (square 2.5))' '"6.25"'

describe 'mixed comparisons'
  it 'int = float (equal values)' \
    '(= 3 3.0)' 't'
  it 'int = float (unequal)' \
    '(null? (= 3 3.5))' 't'
  it 'int < float' \
    '(< 1 2.5)' 't'
  it 'float < int' \
    '(< 0.5 1)' 't'
  it 'int > float' \
    '(> 3 2.5)' 't'
  it 'int <= float (equal)' \
    '(<= 3 3.0)' 't'
  it 'int >= float' \
    '(>= 3 2.5)' 't'
  it 'float <= float' \
    '(<= 2.5 3.0)' 't'

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

describe 'rounding'
  it 'floor of positive float' \
    '(floor 3.7)' '3'
  it 'floor of negative float' \
    '(floor (- 0 3.3))' '-4'
  it 'floor of integer' \
    '(floor 5)' '5'
  it 'floor returns exact' \
    '(exact? (floor 3.7))' 't'
  it 'ceiling of positive float' \
    '(ceiling 3.2)' '4'
  it 'ceiling of negative float' \
    '(ceiling (- 0 3.7))' '-3'
  it 'ceiling of integer' \
    '(ceiling 5)' '5'
  it 'ceiling returns exact' \
    '(exact? (ceiling 3.2))' 't'
  it 'truncate of positive float' \
    '(truncate 3.7)' '3'
  it 'truncate of negative float' \
    '(truncate (- 0 3.7))' '-3'
  it 'truncate of integer' \
    '(truncate 5)' '5'
  it 'round of 3.5' \
    '(round 3.5)' '4'
  it 'round of 2.5' \
    '(round 2.5)' '2'
  it 'round of 3.2' \
    '(round 3.2)' '3'
  it 'round of negative' \
    '(round (- 0 3.7))' '-4'
  it 'round returns exact' \
    '(exact? (round 3.7))' 't'

describe 'sqrt'
  it 'sqrt of perfect square' \
    '(sqrt 9)' '3'
  it 'sqrt of perfect square returns exact' \
    '(exact? (sqrt 9))' 't'
  it 'sqrt of 25' \
    '(sqrt 25)' '5'
  it 'sqrt of non-perfect square returns float' \
    '(inexact? (sqrt 2))' 't'
  it 'sqrt of non-perfect square value' \
    '(> (sqrt 2) 1.4)' 't'
  it 'sqrt of zero' \
    '(sqrt 0)' '0'
  it 'sqrt of float' \
    '(number->string (sqrt 2.0))' '"1.4142135623731"'

describe 'expt'
  it 'expt basic' \
    '(expt 2 10)' '1024'
  it 'expt zero power' \
    '(expt 5 0)' '1'
  it 'expt power of one' \
    '(expt 7 1)' '7'
  it 'expt with float base' \
    '(number->string (expt 2.0 3.0))' '"8"'
  it 'expt with float returns float' \
    '(inexact? (expt 2.0 3.0))' 't'
  it 'expt integer result stays exact' \
    '(exact? (expt 2 10))' 't'

describe 'exact/inexact conversion'
  it 'inexact converts int to float' \
    '(inexact? (inexact 42))' 't'
  it 'inexact value' \
    '(= (inexact 42) 42.0)' 't'
  it 'exact converts float to int' \
    '(exact? (exact 3.0))' 't'
  it 'exact value' \
    '(= (exact 3.0) 3)' 't'
  it 'exact->inexact converts int to float' \
    '(inexact? (exact->inexact 5))' 't'
  it 'inexact->exact converts float to int' \
    '(exact? (inexact->exact 5.0))' 't'

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
  it 'number->string integer' \
    '(number->string 42)' '"42"'
  it 'string->number integer' \
    '(string->number "42")' '42'
  it 'number->string float' \
    '(number->string 3.14)' '"3.14"'
  it 'string->number float' \
    '(number->string (string->number "3.14"))' '"3.14"'
  it 'string->number returns float for dotted' \
    '(inexact? (string->number "3.14"))' 't'
  it 'string->number returns int for non-dotted' \
    '(exact? (string->number "42"))' 't'
  it 'number->string negative' \
    '(number->string (- 0 7))' '"-7"'
  it 'number->string negative float' \
    '(number->string (- 0 3.14))' '"-3.14"'
