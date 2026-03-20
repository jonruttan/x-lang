; --- Records (R7RS §5.5) ---

(define
  define-record-type
  (op (name constructor-spec pred . field-specs)
    env
    (eval
      (cons
        (lit begin)
        (append
          (list
            (list
              (lit def)
              name
              (list
                (lit make-type)
                (list (lit quote) name)
                (list
                  (lit list)
                  (list
                    (lit pair)
                    (list (lit quote) (lit write))
                    (list
                      (lit fn)
                      (list (lit self))
                      (list
                        (lit display)
                        (string-append "#<" (convert name %string) ">")))))))
            (list
              (lit def)
              (car constructor-spec)
              (list
                (lit fn)
                (cdr constructor-spec)
                (list
                  (lit make-instance)
                  name
                  (cons
                    (lit list)
                    (map
                      (lambda (f) (list (lit pair) (list (lit quote) f) f))
                      (cdr constructor-spec))))))
            (list
              (lit def)
              pred
              (list
                (lit fn)
                (list (lit x))
                (list (lit type?) (lit x) name))))
          (append
            (map
              (lambda
                (spec)
                (list
                  (lit def)
                  (list-ref spec 1)
                  (list
                    (lit fn)
                    (list (lit x))
                    (list
                      (lit cdr)
                      (list
                        (lit assq)
                        (list (lit quote) (car spec))
                        (list (lit first) (lit x)))))))
              field-specs)
            (list (list (lit quote) name))))))))
