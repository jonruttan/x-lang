# 22-type-convert.spec.sh -- Tests for type-of, write-to-string, and convert system
# Spec: Section 22 - Type Conversion System
LANG_LIB="$SCRIPT_DIR/../../lib/x.x"

describe 'type-of basics'
  it 'returns a handle for integers' \
    '(not (null? (type-of 42)))' 't'
  it 'returns a handle for strings' \
    '(not (null? (type-of "hello")))' 't'
  it 'returns nil for nil' \
    '(null? (type-of ()))' 't'

describe 'type-of equality (same type)'
  it 'same type handle for two ints' \
    '(eq? (type-of 1) (type-of 999))' 't'
  it 'same type handle for two strings' \
    '(eq? (type-of "a") (type-of "zzz"))' 't'
  it 'same type handle for two pairs' \
    '(do (def a (type-of (pair 1 2))) (def b (type-of (pair 3 4))) (eq? a b))' 't'
  it 'same type handle for two floats' \
    '(eq? (type-of 1.0) (type-of 2.5))' 't'
  it 'same type handle for two booleans' \
    '(eq? (type-of t) (type-of t))' 't'
  it 'same type handle for two chars' \
    '(eq? (type-of #\a) (type-of #\z))' 't'

describe 'type-of inequality (different types)'
  it 'int differs from string' \
    '(null? (eq? (type-of 1) (type-of "x")))' 't'
  it 'int differs from float' \
    '(null? (eq? (type-of 1) (type-of 1.0)))' 't'
  it 'string differs from pair' \
    '(do (def a (type-of "x")) (def b (type-of (pair 1 2))) (null? (eq? a b)))' 't'
  it 'int differs from char' \
    '(null? (eq? (type-of 1) (type-of #\a)))' 't'
  it 'float differs from string' \
    '(null? (eq? (type-of 1.0) (type-of "1.0")))' 't'

describe 'type-of custom types'
  it 'custom type returns a handle' \
    '(do (def %t (make-type "TEST-T" (list))) (def obj (make-instance %t 1)) (not (null? (type-of obj))))' 't'
  it 'same custom type returns same handle' \
    '(do (def %t (make-type "TEST-T" (list))) (def a (make-instance %t 1)) (def b (make-instance %t 2)) (eq? (type-of a) (type-of b)))' 't'
  it 'different custom types differ' \
    '(do (def %t1 (make-type "T1" (list))) (def %t2 (make-type "T2" (list))) (null? (eq? (type-of (make-instance %t1 1)) (type-of (make-instance %t2 1)))))' 't'
  it 'custom type differs from int' \
    '(do (def %t (make-type "TEST-T" (list))) (null? (eq? (type-of (make-instance %t 1)) (type-of 42))))' 't'

describe 'type-of used in convert alist key'
  it 'type-of key matches int for int convert' \
    '(float? (convert 42 %float))' 't'
  it 'type-of key does not match for string' \
    '(null? (convert "hello" %float))' 't'

describe 'write-to-string'
  it 'integer to string' \
    '(write-to-string 42)' '"42"'
  it 'negative integer to string' \
    '(write-to-string -7)' '"-7"'
  it 'zero to string' \
    '(write-to-string 0)' '"0"'
  it 'string to quoted string' \
    '(write-to-string "hello")' '"\"hello\""'
  it 'symbol to string' \
    '(write-to-string (lit foo))' '"foo"'
  it 'boolean to string' \
    '(write-to-string t)' '"t"'
  it 'nil to empty string' \
    '(write-to-string ())' '""'
  it 'pair to string' \
    '(write-to-string (pair 1 2))' '"(1 . 2)"'
  it 'list to string' \
    '(write-to-string (list 1 2 3))' '"(1 2 3)"'
  it 'char to string' \
    '(write-to-string #\a)' '"a"'
  it 'float to string' \
    '(write-to-string 3.14)' '"3.14"'
  it 'nested list to string' \
    '(write-to-string (list (list 1 2) 3))' '"((1 2) 3)"'
  it 'returns a string type' \
    '(string? (write-to-string 42))' 't'

describe 'convert nil handling'
  it 'convert nil returns nil' \
    '(null? (convert () %float))' 't'
  it 'convert nil to custom type returns nil' \
    '(do (def %t (make-type "CNV-T" (list (pair (lit convert) (list (pair (type-of 42) (fn (v) (make-instance %t v)))))))) (null? (convert () %t)))' 't'

describe 'convert short-circuit (already target type)'
  it 'float to float is identity' \
    '(def x 3.14) (eq? (convert x %float) x)' 't'
  it 'custom type to same type is identity' \
    '(do (def %t (make-type "ID-T" (list (pair (lit convert) (list))))) (def obj (make-instance %t 42)) (eq? (convert obj %t) obj))' 't'

describe 'convert alist dispatch'
  it 'exact match calls converter' \
    '(convert 42 %float)' '42'
  it 'exact match result has target type' \
    '(float? (convert 42 %float))' 't'
  it 'no match returns nil' \
    '(null? (convert "hello" %float))' 't'
  it 'convert negative int to float' \
    '(convert -5 %float)' '-5'
  it 'convert zero to float' \
    '(convert 0 %float)' '0'
  it 'convert zero result is float' \
    '(float? (convert 0 %float))' 't'

describe 'convert wildcard t entry'
  it 'wildcard matches any type' \
    '(do (def %t (make-type "WILD-T" (list (pair (lit convert) (list (pair t (fn (v) (make-instance %t v)))))))) (type? (convert 42 %t) %t))' 't'
  it 'wildcard catches string' \
    '(do (def %t (make-type "WILD-T" (list (pair (lit convert) (list (pair t (fn (v) (make-instance %t v)))))))) (type? (convert "hello" %t) %t))' 't'
  it 'exact match takes priority over wildcard' \
    '(do (def %t (make-type "PRIO-T" (list (pair (lit convert) (list (pair (type-of 42) (fn (v) (make-instance %t "exact"))) (pair t (fn (v) (make-instance %t "wild")))))))) (first (convert 42 %t)))' '"exact"'
  it 'wildcard used when no exact match' \
    '(do (def %t (make-type "PRIO-T" (list (pair (lit convert) (list (pair (type-of 42) (fn (v) (make-instance %t "exact"))) (pair t (fn (v) (make-instance %t "wild")))))))) (first (convert "hello" %t)))' '"wild"'

describe 'convert with no convert alist'
  it 'type with empty convert returns nil' \
    '(do (def %t (make-type "EMPTY-T" (list (pair (lit convert) (list))))) (null? (convert 42 %t)))' 't'
  it 'type with no convert field returns nil' \
    '(do (def %t (make-type "NO-CVT" (list))) (null? (convert 42 %t)))' 't'

describe 'convert multi-type alist'
  it 'int converter works' \
    '(do (def %t (make-type "MULTI-T" (list (pair (lit convert) (list (pair (type-of 42) (fn (v) (make-instance %t (+ v 100)))) (pair (type-of "") (fn (v) (make-instance %t v)))))))) (first (convert 5 %t)))' '105'
  it 'string converter works' \
    '(do (def %t (make-type "MULTI-T" (list (pair (lit convert) (list (pair (type-of 42) (fn (v) (make-instance %t (+ v 100)))) (pair (type-of "") (fn (v) (make-instance %t v)))))))) (first (convert "hello" %t)))' '"hello"'
  it 'unregistered type returns nil' \
    '(do (def %t (make-type "MULTI-T" (list (pair (lit convert) (list (pair (type-of 42) (fn (v) (make-instance %t v)))))))) (null? (convert #\a %t)))' 't'
