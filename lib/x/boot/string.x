; string.x -- Boot string operations (bootstrap)
;
; Basic string functions needed by the module system.
; Uses match instead of if (if not yet available).

(def not (fn (_ x) (match (x #f) (#t #t))))
(def list (fn (_ . args) args))

(def str-ref (fn (_ s i) (s i)))
(def str-length (fn (_ s) (s)))
(def substring (fn (_ s start end) (s start (- end start))))
(def newline (fn (_ ) (display "\n")))

; str=?: string equality using character comparison
(def %str-eq-loop
  (fn (self a b i len)
    (match
      ((= i len) #t)
      ((= (char->integer (a i)) (char->integer (b i)))
        (self a b (+ i 1) len))
      (#t #f))))
(def str=?
  (fn (_ a b)
    (match
      ((= (a) (b)) (%str-eq-loop a b 0 (a)))
      (#t #f))))

; number->str: (number->str n [radix]) -> string
(def %n2s/ /)
(def %n2s% %)
(def number->str
  (fn (self n . rest)
    (def radix (match ((eq? rest ()) 10) (#t (first rest))))
    (def %d "0123456789abcdefghijklmnopqrstuvwxyz")
    (match
      ((= n 0) "0")
      ((< n 0) (str-append "-" (self (- 0 n) radix)))
      (#t
        (do
          (def rem (%n2s% n radix))
          (match
            ((< n radix) (list->str (list (%d rem))))
            (#t (str-append
                  (self (%n2s/ n radix) radix)
                  (list->str (list (%d rem)))))))))))

; str->number: (str->number str [radix]) -> integer or ()
(def str->number
  (fn (_ s . rest)
    (def radix (match ((eq? rest ()) 10) (#t (first rest))))
    (def len (s))
    (match
      ((= len 0) ())
      (#t
        (do
          (def %0 (char->integer ("0" 0)))
          (def %digit
            (fn (_ ch)
              (def c (char->integer ch))
              (match
                ((match ((not (< c %0)) (not (< (+ %0 9) c))) (#t #f))
                  (- c %0))
                ((match ((not (< c (char->integer ("a" 0))))
                         (not (< (+ (char->integer ("a" 0)) 25) c))) (#t #f))
                  (+ 10 (- c (char->integer ("a" 0)))))
                ((match ((not (< c (char->integer ("A" 0))))
                         (not (< (+ (char->integer ("A" 0)) 25) c))) (#t #f))
                  (+ 10 (- c (char->integer ("A" 0)))))
                (#t ()))))
          (def c0 (char->integer (s 0)))
          (def neg (= c0 (char->integer ("-" 0))))
          (def start
            (match
              (neg 1)
              ((= c0 (char->integer ("+" 0))) 1)
              (#t 0)))
          (match
            ((= start len) ())
            (#t
              (do
                (def %parse
                  (fn (self i acc)
                    (match
                      ((= i len) acc)
                      (#t
                        (do
                          (def d (%digit (s i)))
                          (match
                            ((eq? d ()) ())
                            ((< d radix) (self (+ i 1) (+ (* acc radix) d)))
                            (#t ())))))))
                (def result (%parse start 0))
                (match
                  ((eq? result ()) ())
                  (neg (- 0 result))
                  (#t result))))))))))
