; doctest-literals.x -- the literals a module's doc examples are read with.
;
; A doc example is x-lang as x-lang writes its values, and a library
; installs no literal of its own: x/num/float is the type, and 1.5 is
; x/num/float/literal's.  So a doctest file, once it has loaded its module,
; includes this file, which imports the literal of each such library the
; module loaded.  A module that loads none has none imported for it.
;
; Included by the first case tools/check/doctest-split.awk writes into each
; file.
(List for-each
  (fn (_ m)
    (when (List includes? (first m) (first %module-loaded-cell))
      (eval! (list (lit import) (rest m)))))
  (list (pair (lit x/num/bigint) (lit x/num/bigint/literal))
        (pair (lit x/num/float) (lit x/num/float/literal))
        (pair (lit x/num/rational) (lit x/num/rational/literal))
        (pair (lit x/num/complex) (lit x/num/complex/literal))
        (pair (lit x/num/decimal) (lit x/num/decimal/literal))
        (pair (lit x/num/fixed) (lit x/num/fixed/literal))
        (pair (lit x/type/regex) (lit x/type/regex/literal))))
