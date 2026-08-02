; loader-frame-fixture.x -- regression fixture for load transparency
;
; A closure captures the env-alist head at definition time. The loaders
; (include wrapper / include-once / import) have formals named `path`,
; `name`, `syms` and a def `%result`, so if their frames were visible
; during the load, this closure would capture them and read them forever
; in place of the global env -- the Logo server's request dispatch once
; read its own module path where its request path should have been.
; x_eval_load strips the includer's lexical frames around the load, so
; every probe below must miss.
(def %loader-frame-probe
  (fn ()
    (list (guard (_ 'unbound) path)
          (guard (_ 'unbound) name)
          (guard (_ 'unbound) syms)
          (guard (_ 'unbound) %result))))
