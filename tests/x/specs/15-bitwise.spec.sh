# 15-bitwise.spec.sh -- Tests for bitwise operations

describe '~ (bitwise NOT)'
  it 'inverts zero' '(~ 0)' '-1'
  it 'inverts one' '(~ 1)' '-2'
  it 'inverts negative' '(~ -1)' '0'
  it 'double invert is identity' '(~ (~ 42))' '42'

describe '& (bitwise AND)'
  it 'ands with zero' '(& 255 0)' '0'
  it 'ands with self' '(& 42 42)' '42'
  it 'masks low bits' '(& 255 15)' '15'
  it 'masks high nibble' '(& 170 240)' '160'

describe '| (bitwise OR)'
  it 'ors with zero' '(| 42 0)' '42'
  it 'ors complementary bits' '(| 170 85)' '255'
  it 'ors with self' '(| 42 42)' '42'

describe '^ (bitwise XOR)'
  it 'xors with zero' '(^ 42 0)' '42'
  it 'xors with self gives zero' '(^ 42 42)' '0'
  it 'xors complementary bits' '(^ 170 85)' '255'
  it 'double xor is identity' '(^ (^ 42 99) 99)' '42'

describe '<< (shift left)'
  it 'shifts by 0' '(<< 1 0)' '1'
  it 'shifts by 1' '(<< 1 1)' '2'
  it 'shifts by 4' '(<< 1 4)' '16'
  it 'shifts value' '(<< 5 3)' '40'

describe '>> (shift right)'
  it 'shifts by 0' '(>> 16 0)' '16'
  it 'shifts by 1' '(>> 16 1)' '8'
  it 'shifts by 4' '(>> 255 4)' '15'
  it 'shifts to zero' '(>> 1 1)' '0'

describe 'char?'
  it 'returns nil for number' '(null? (char? 42))' 't'
  it 'returns nil for string' '(null? (char? "hello"))' 't'
  it 'returns nil for symbol' '(null? (char? (lit a)))' 't'

describe 'gc'
  it 'returns nil' '(null? (gc))' 't'
