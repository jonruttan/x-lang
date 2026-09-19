(module scoped/gamma)
; gamma.x -- exports a class under the name alpha's class has.  A class is
; bound in the root, where alpha already owns the name.
(import x/type/class)
(def-class Alpha ()
  (static (method twice (self n) n)))
(provide scoped/gamma Alpha)
