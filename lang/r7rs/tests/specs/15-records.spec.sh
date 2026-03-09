# 15-records.spec.sh -- R7RS 5.5 Record-type definitions

describe 'define-record-type basics'
  it 'define-record-type returns name' \
    '(define-record-type <point> (make-point x y) point? (x point-x) (y point-y))' '<point>'
  it 'constructor creates record' \
    '(define-record-type <point> (make-point x y) point? (x point-x) (y point-y)) (point? (make-point 1 2))' 't'
  it 'predicate true for record' \
    '(define-record-type <box> (make-box val) box? (val box-val)) (box? (make-box 42))' 't'
  it 'predicate false for non-record' \
    '(define-record-type <box> (make-box val) box? (val box-val)) (null? (box? 42))' 't'
  it 'predicate false for list' \
    '(define-record-type <box> (make-box val) box? (val box-val)) (null? (box? (list 1 2)))' 't'

describe 'record accessors'
  it 'access first field' \
    '(define-record-type <point> (make-point x y) point? (x point-x) (y point-y)) (point-x (make-point 3 4))' '3'
  it 'access second field' \
    '(define-record-type <point> (make-point x y) point? (x point-x) (y point-y)) (point-y (make-point 3 4))' '4'
  it 'access single field' \
    '(define-record-type <box> (make-box val) box? (val box-val)) (box-val (make-box 99))' '99'
  it 'fields with string values' \
    '(define-record-type <person> (make-person name age) person? (name person-name) (age person-age)) (person-name (make-person "Alice" 30))' '"Alice"'
  it 'fields with list values' \
    '(define-record-type <box> (make-box val) box? (val box-val)) (box-val (make-box (list 1 2 3)))' '(1 2 3)'

describe 'record patterns'
  it 'multiple records independent' \
    '(define-record-type <point> (make-point x y) point? (x point-x) (y point-y)) (define-record-type <color> (make-color r g b) color? (r color-r) (g color-g) (b color-b)) (list (point-x (make-point 1 2)) (color-r (make-color 255 0 0)))' '(1 255)'
  it 'record in variable' \
    '(define-record-type <box> (make-box val) box? (val box-val)) (define b (make-box 42)) (box-val b)' '42'
  it 'record with three fields' \
    '(define-record-type <vec3> (make-vec3 x y z) vec3? (x vec3-x) (y vec3-y) (z vec3-z)) (define v (make-vec3 1 2 3)) (list (vec3-x v) (vec3-y v) (vec3-z v))' '(1 2 3)'
