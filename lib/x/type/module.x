; module.x -- Module: the module registry as data.
;
; boot/module.x keeps the registry in cells on the include-list chain: the
; names known to the session, loaded or not; the (name . exports) entry each
; provide records; the environment of each scoped module; and the owner of
; each exported name.  (modules) and (help x/some/module) print from them.
; This class answers the same facts as values: the two name cells are shared
; with it, and the owner and environment tables are reached through the
; catalogue doors boot/module.x files under ns `module`.
(module x/type/module)

(import x/type/class)

(def-class Module ()
  (doc "The module registry as data: which modules the session knows and which are loaded, what each exports, which module owns a name, and a module's environment. (modules) and (help x/some/module) print the same facts."
    (example "(Module loaded? 'x/core/fn)" "#t")
    (example "(Module owner 'Fn)" "'x/core/fn"))
  (static
    ; The registry entry (name . exports) a provide recorded, or ().
    (method %entry (self name)
      (doc "The (name . exports) entry provide recorded for name, or ().")
      (Assoc entry name (first %module-registry-cell)))
    (method names (self)
      (doc "Every module name the session knows, sorted: the boot modules registered at boot and every module imported since, loaded or not."
        (returns LIST "Symbols, sorted by name")
        (example "(List includes? 'x/core/fn (Module names))" "#t"))
      ; Sorted first, then the duplicates dropped in one pass, as Doc names
      ; does: (List distinct) walks the whole list for each element.
      (List uniq
        (List sort (fn (_ a b) (Str8 <? (symbol->str a) (symbol->str b)))
          (List map (fn (_ e) (if (pair? e) (first e) e))
                    (first %module-loaded-cell)))))
    (method loaded? (self (param name SYMBOL "A module name, such as 'x/core/fn"))
      (doc "Whether the module has loaded and provided its exports."
        (returns BOOL "#t when the module's provide has run")
        (example "(Module loaded? 'x/core/fn)" "#t")
        (example "(Module loaded? 'x/no/such)" "#f"))
      (not (null? (Module %entry name))))
    (method exports (self (param name SYMBOL "A module name"))
      (doc "The names the module provides, as symbols, in provide order; a (global NAME) export is listed as NAME. () for a module that is not loaded."
        (returns LIST "Symbols")
        (example "(List includes? 'Fn (Module exports 'x/core/fn))" "#t"))
      (def entry (Module %entry name))
      (if (null? entry) () (rest entry)))
    (method owner (self (param name SYMBOL "An exported name"))
      (doc "The module that provided name, or () when no module has."
        (returns SYMBOL "A module name, or ()")
        (example "(Module owner 'Fn)" "'x/core/fn"))
      ((prim-ref (lit module) (lit owner)) name))
    (method env (self (param name SYMBOL "A module name"))
      (doc "The environment the module's names live in: its own for a scoped module, a child of the root; the root for a module loaded by include. () for a module that is not loaded."
        (returns ANY "An environment, or ()")
        (example "(Env has? (Module env 'x/core/fn) 'Fn)" "#t"))
      (if (Module loaded? name)
        ((prim-ref (lit module) (lit env)) name)
        ()))))

(doc (provide x/type/module Module)
  (note "The registry as data: (Module names), (Module loaded? 'name), (Module exports 'name), (Module owner 'sym), (Module env 'name).")
  (example "(Module owner 'Fn)" "'x/core/fn")
  "Module: the module registry as data -- names, loaded state, exports, owners and environments.")
