; doc-prims.x -- Documentation for C primitives and x-core operatives
;
; Uses bare-symbol doc form: (doc name "description" (param ...) ...)

; === Core forms ===

(note "Core forms")

(doc lit "Return the argument unevaluated (quote)."
  (param form ANY "Any expression")
  (returns ANY "The expression itself")
  (example "(lit x)" "'x")
  (example "(lit (1 2 3))" "(1 2 3)"))

(doc def "Bind a name to a value in the current environment."
  (param name SYMBOL "Name to bind")
  (param value ANY "Expression to evaluate and bind")
  (note "Value is evaluated before the name is bound. Use the self parameter (first arg to fn) for recursion.")
  (example "(def x 42)" "42")
  (see set!))

(doc set! "Mutate an existing binding."
  (param name SYMBOL "Bound name to update")
  (param value ANY "New value")
  (note "Signals an error if name is not already bound.")
  (see def))

(doc fn "Create a closure (applicative: arguments are evaluated before the body runs)."
  (param params LIST "Parameter list: (a b), (a . rest), or args for variadic")
  (param body ANY "Body expression(s)")
  (returns PROCEDURE "A new closure")
  (example "(def add (fn (_ a b) (+ a b)))" "")
  (example "((fn (_ x) (* x x)) 5)" "25")
  (see op))

(doc op "Create an operative (fexpr: arguments are NOT evaluated)."
  (param params LIST "Formal parameters for unevaluated args")
  (param env-param SYMBOL "Name bound to caller's environment")
  (param body ANY "Body expression(s)")
  (returns OPERATIVE "A new operative")
  (note "Use eval with the env parameter to evaluate arguments selectively.")
  (example "(def my-if (op (test then else) e (if (eval test e) (eval then e) (eval else e))))" "")
  (see fn))

(doc apply "Apply a function to a list of arguments."
  (param f CALLABLE "Function to apply")
  (param args LIST "Argument list")
  (returns ANY "Result of application")
  (example "(apply + '(1 2))" "3"))

(doc eval "Evaluate an expression, optionally in a given environment."
  (param expr ANY "Expression to evaluate")
  (param env LIST "Environment alist (optional)")
  (returns ANY "Result of evaluation")
  (note "With one arg: uses TCO (tail-call safe). With env arg: saves/restores env after.")
  (see eval!))

(doc eval! "Evaluate in current environment, returning the result immediately."
  (param expr ANY "Expression to evaluate")
  (returns ANY "Result of evaluation")
  (note "No TCO, no env save/restore. Use for non-tail evaluation of computed forms.")
  (see eval))

(doc match "Pattern matching: evaluate clauses until a test succeeds."
  (param clauses LIST "((test result) ...) pairs — first truthy test wins")
  (example "(match ((= x 0) \"zero\") ((< x 0) \"neg\") (#t \"pos\"))" "")
  (note "Similar to cond but a C primitive. Tests are evaluated in order."))

(doc guard "Error handler: evaluate body with an error guard."
  (param var SYMBOL "Name bound to the error value")
  (param handler ANY "Expression evaluated if error occurs (var is bound)")
  (param body ANY "Expression to evaluate")
  (example "(guard (e (list 'error e)) (+ 1 \"x\"))" "('error \"...\")"))

(doc error "Signal an error with a message."
  (param message STRING "Error message")
  (param value ANY "Associated value (optional)")
  (example "(error \"bad input\" 42)" ""))

(doc wrap "Create an applicative from a combiner (evaluates args before calling)."
  (param combiner CALLABLE "An operative or procedure")
  (returns CALLABLE "An applicative"))

(doc unwrap "Extract the underlying combiner from an applicative."
  (param applicative CALLABLE "A wrapped combiner")
  (returns CALLABLE "The underlying combiner"))

; === Pair operations ===

(note "Pair operations")

(doc pair "Create a new pair (cons cell) from two values."
  (param a ANY "First element (head)")
  (param d ANY "Second element (tail)")
  (returns PAIR "A new pair")
  (example "(pair 1 2)" "(1 . 2)")
  (example "(pair 1 (pair 2 ()))" "(1 2)")
  (see first) (see rest))

(doc first "Return the first element (head) of a pair."
  (param p PAIR "A pair")
  (returns ANY "The first element")
  (example "(first '(1 2 3))" "1")
  (see rest) (see pair))

(doc rest "Return the second element (tail) of a pair."
  (param p PAIR "A pair")
  (returns ANY "The second element")
  (example "(rest '(1 2 3))" "(2 3)")
  (see first) (see pair))

(doc set-first! "Mutate the first element of a pair."
  (param p PAIR "A pair")
  (param val ANY "New value"))

(doc set-rest! "Mutate the second element of a pair."
  (param p PAIR "A pair")
  (param val ANY "New value"))

(doc first-int "Return the first element as a raw integer."
  (param p PAIR "A pair"))

(doc rest-int "Return the second element as a raw integer."
  (param p PAIR "A pair"))

(doc set-first-int! "Mutate the first element as a raw integer."
  (param p PAIR "A pair")
  (param val INT "Integer value"))

(doc set-rest-int! "Mutate the second element as a raw integer."
  (param p PAIR "A pair")
  (param val INT "Integer value"))

; === Arithmetic ===

(note "Arithmetic")

(doc + "Variadic addition. Returns the sum of all arguments."
  (param args NUMBER "Zero or more numbers")
  (returns NUMBER "Sum of all arguments, or 0 with no arguments")
  (example "(+ 1 2 3)" "6")
  (example "(+)" "0"))

(doc - "Variadic subtraction. With one argument, negates. With multiple, folds left."
  (param args NUMBER "One or more numbers")
  (returns NUMBER "Difference, or negation with one argument")
  (example "(- 10 3 2)" "5")
  (example "(- 5)" "-5"))

(doc * "Variadic multiplication. Returns the product of all arguments."
  (param args NUMBER "Zero or more numbers")
  (returns NUMBER "Product of all arguments, or 1 with no arguments")
  (example "(* 2 3 4)" "24")
  (example "(*)" "1"))

(doc / "Variadic integer division. Folds left."
  (param args NUMBER "One or more numbers")
  (returns NUMBER "Quotient from left fold")
  (example "(/ 100 5 2)" "10"))

(doc % "Variadic modulo. Folds left."
  (param args NUMBER "Two or more numbers")
  (returns NUMBER "Remainder from left fold")
  (example "(% 10 3)" "1"))

(doc ~ "Bitwise NOT."
  (param n INT "Integer")
  (returns INT "Bitwise complement"))

(doc & "Bitwise AND."
  (param a INT "First operand")
  (param b INT "Second operand")
  (returns INT "Bitwise AND"))

(doc | "Bitwise OR."
  (param a INT "First operand")
  (param b INT "Second operand")
  (returns INT "Bitwise OR"))

(doc ^ "Bitwise XOR."
  (param a INT "First operand")
  (param b INT "Second operand")
  (returns INT "Bitwise XOR"))

(doc << "Left shift."
  (param n INT "Value to shift")
  (param count INT "Number of bits")
  (returns INT "Shifted value"))

(doc >> "Arithmetic right shift."
  (param n INT "Value to shift")
  (param count INT "Number of bits")
  (returns INT "Shifted value"))

; === Predicates ===

(note "Predicates")

(doc eq? "Test identity equality (pointer equality for objects, value for atoms)."
  (param a ANY "First value")
  (param b ANY "Second value")
  (returns BOOL "t if identical"))

(doc = "Test numeric equality."
  (param a INT "First number")
  (param b INT "Second number")
  (returns BOOL "t if equal"))

(doc < "Test numeric less-than."
  (param a INT "First number")
  (param b INT "Second number")
  (returns BOOL "t if a < b"))

; char->integer (ns char) and integer->char (ns int) are de-registered (R5);
; the Char class (->int / from-int) carries their docs. Reader-hot consumers
; fetch the prim directly.

; === Strings ===

(note "Strings")

(doc symbol->str "Convert a symbol to a string."
  (param sym SYMBOL "A symbol")
  (returns STRING "The symbol's name"))

(doc bytes->str "Pack a list of characters into a string, one low byte per char."
  (param bytes LIST "List of byte-valued characters")
  (returns STRING "A string of those bytes"))

; === I/O ===

(note "I/O")

; write/display stay bare (the keep-list); their entries remain here. The rest
; of ns `io` (read, read-char, write-to-str, display-to-str, error-line,
; repl-read) is de-registered (R5) -- the Io class (lib/x/type/io.x) docs them.
(doc write "Write a value in machine-readable form."
  (param val ANY "Value to write")
  (note "Strings are quoted, characters show read syntax. Use for serialization.")
  (see display))

(doc display "Display a value in human-readable form."
  (param val ANY "Value to display")
  (note "Strings are unquoted, characters are bare. Use for user output.")
  (see write))

; === Memory ===

(note "Memory management")

(doc alloc-limit! "Set the allocation ceiling (runaway-memory guard): the process stops rather than allocate past n objects. 0 disables."
  (param n INT "Object-count ceiling; 0 = unlimited"))

; === Type system ===

; Type system: make/make-instance/?/of/name are de-registered (ns `type`, R5);
; the Type class (lib/x/type/type.x) carries their docs.

; === FFI ===

(note "Foreign function interface")

; dlopen/dlsym/ffi-call (ns ffi) and ptr-call/ptr->int/... (ns ptr) are
; de-registered (R5); the Ffi and Ptr classes (lib/x/type/ptr.x) carry their
; docs. int->ptr (ns int) is de-registered (R5) too -- (Ptr from-int) is the
; surface; reader/hot callers fetch (prim-ref 'int '->ptr).

; === Continuations ===

(note "Continuations")

(doc call/cc "Call a function with the current continuation."
  (param f CALLABLE "Function receiving the continuation")
  (returns ANY "Result of f, or value passed to continuation"))

; === x-core operatives ===

(note "x-core operatives")

(doc null? "Test if a value is nil (the empty list)."
  (param x ANY "Value to test")
  (returns BOOL "t if nil"))

(doc pair? "Test if a value is a pair (cons cell)."
  (param x ANY "Value to test")
  (returns BOOL "t if pair"))

(doc atom? "Test if a value is an atom (not a pair)."
  (param x ANY "Value to test")
  (returns BOOL "t if not a pair"))

(doc number? "Test if a value is an integer."
  (param x ANY "Value to test")
  (returns BOOL "t if integer"))

(doc str? "Test if a value is a string."
  (param x ANY "Value to test")
  (returns BOOL "t if string"))

(doc symbol? "Test if a value is a symbol."
  (param x ANY "Value to test")
  (returns BOOL "t if symbol"))

(doc char? "Test if a value is a character."
  (param x ANY "Value to test")
  (returns BOOL "t if character"))

(doc procedure? "Test if a value is callable (procedure or primitive)."
  (param x ANY "Value to test")
  (returns BOOL "t if procedure or primitive"))

(doc if "Conditional: evaluate test, then branch."
  (param test ANY "Condition expression")
  (param then ANY "True branch")
  (param else ANY "False branch (optional)")
  (example "(if (> 3 2) \"yes\" \"no\")" "\"yes\"")
  (see match) (see cond))

(doc let "Bind local variables and evaluate body."
  (param bindings LIST "((name value) ...) binding pairs")
  (param body ANY "Body expression")
  (note "Named let: (let name ((var init) ...) body) creates a loop.")
  (example "(let ((x 1) (y 2)) (+ x y))" "3")
  (example "(let loop ((n 5) (acc 1)) (if (= n 0) acc (loop (- n 1) (* acc n))))" "120")
  (see letrec))

(doc do "Evaluate expressions sequentially, return last result."
  (param exprs ANY "One or more expressions")
  (example "(do (display \"hi\") 42)" "42"))

(doc begin "Alias for do."
  (see do))

(doc not "Logical negation."
  (param x ANY "Value to negate")
  (returns BOOL "t if x is falsy"))

(doc list "Create a list from arguments."
  (param args ANY "Zero or more values")
  (returns LIST "A new list")
  (example "(list 1 2 3)" "(1 2 3)"))

(doc and "Short-circuit logical AND."
  (param args ANY "Zero or more expressions")
  (returns ANY "Last truthy value, or #f")
  (example "(and 1 2 3)" "3"))

(doc or "Short-circuit logical OR."
  (param args ANY "Zero or more expressions")
  (returns ANY "First truthy value, or nil")
  (example "(or #f 42)" "42"))

(doc time "Time an expression's evaluation in microseconds."
  (param expr ANY "Expression to time")
  (returns ANY "Result of expr (prints elapsed time as side effect)")
  (example "(time (fold + 0 (List range 0 1000)))" "499500"))

(doc newline "Display a newline character.")

(doc quasi "Quasiquote: template with unquote and splicing."
  (param template ANY "Template expression with , and ,@ escapes")
  (note "Use , to unquote a single expression, ,@ to splice a list.")
  (example "(let ((x 42)) (quasi (a ,x b)))" "('a 42 'b)"))

(doc repl "Start the read-eval-print loop."
  (note "Customizable: %repl-prompt and %repl-print control display."))

(doc include-once "Load and evaluate a file, skipping if already loaded."
  (param path STRING "File path to include"))

(doc provide "Register a module's exported symbols."
  (param name SYMBOL "Module name, e.g. x/list")
  (param exports SYMBOL "Exported symbol names (variadic)"))

(doc import "Import a module (include its file if not yet loaded)."
  (param name SYMBOL "Module name to import"))

(doc atom? "Test if a value is an atom (not a pair or nil)."
  (param x ANY "Value to test")
  (returns BOOL "t if atom"))

(doc number->str "Convert an integer to a string."
  (param n INT "Integer to convert")
  (param radix INT "Base (optional, default 10)")
  (returns STRING "String representation"))

(doc str->number "Parse a string as an integer."
  (param s STRING "String to parse")
  (returns INT "Parsed integer, or nil on failure"))

(doc str-ref "Return the character at an index in a string."
  (param s STRING "A string")
  (param i INT "Zero-based index")
  (returns CHAR "Character at index"))

(doc str-length "Return the length of a string."
  (param s STRING "A string")
  (returns INT "Number of characters"))

(doc substring "Extract a substring."
  (param s STRING "Source string")
  (param start INT "Start index (inclusive)")
  (param end INT "End index (exclusive)")
  (returns STRING "The substring"))

(doc str=? "Test string equality."
  (param a STRING "First string")
  (param b STRING "Second string")
  (returns BOOL "t if equal"))


(doc require-once "Include a file only if it has not been loaded before. Alias for include-once."
  (param path STRING "File path to include")
  (see include-once))

(doc peek-char "Return the next character from stdin without consuming it."
  (returns CHAR "The next character, or () at EOF"))

(doc current-line "Return the current source line number."
  (returns INT "Line number in the current input"))

; === Documentation system (x/doc/doc) ===

(doc doc "Attach documentation metadata to a definition, provide, or bare symbol."
  (note "Three forms: (doc (def name val) meta... desc), (doc (provide name syms) meta... desc), (doc name meta... desc)")
  (note "Meta forms: (param name TYPE desc), (returns TYPE desc), (example expr result), (see name), (note text)"))

(doc note "Section marker for documentation grouping. No-op at runtime."
  (param text STRING "Section description"))

(doc help "Look up documentation in the REPL."
  (note "(help) shows overview. (help name) shows function or module docs. (help modules) lists all modules."))

(doc apropos "Search documentation by name substring."
  (param str STRING "Substring to search for"))

(doc modules "List all known modules with load status and descriptions.")

; === Primitives catalog (the registry protocol) ===

(note "Primitives catalog")

(doc prims "The primitives catalog: an alist of (ns . ((method . impl) ...)) domains."
  (note "The registry of stable implementation identities; modules fetch dependencies")
  (note "from it at load instead of assuming ambient global names.")
  (returns LIST "The live catalog alist")
  (see prim-ref))

(doc prim-domain "The method alist filed under a catalog namespace, or nil."
  (param ns SYMBOL "Namespace symbol, e.g. 'int")
  (returns LIST "((method . impl) ...) for the namespace, or nil")
  (see prims))

(doc prim-ref "Fetch the implementation filed under ns/method, or nil."
  (note "The consumer half of the registry protocol. Fetch at module load and")
  (note "cache in a lexical (hot paths) or call inline (cold paths).")
  (param ns SYMBOL "Namespace symbol, e.g. 'iter")
  (param method SYMBOL "Method symbol, e.g. 'next")
  (returns ANY "The registered implementation, or nil if absent")
  (example "(prim-ref 'int '+)" "#<prim>")
  (see prim-reg!))

(doc prim-reg! "File an x-lang value into the catalog under ns/method."
  (note "The producer half of the registry protocol: library implementations register")
  (note "under the same stable identities as C prims. Registration prepends, so a")
  (note "re-registration shadows the older entry on lookup. Returns nil.")
  (param ns SYMBOL "Namespace symbol, e.g. 'float")
  (param method SYMBOL "Method symbol, e.g. '+")
  (param value ANY "The implementation to register (fn, op, or any value)")
  (example "(do (prim-reg! 'float '+ %f+) (prim-ref 'float '+))" "#<fn>")
  (see prim-ref))

; (`use` -- the qualified fetch+define convenience -- is retired: it had no
; callers.  The registry protocol itself is pure x-lang now: boot/registry.x
; reads the catalog, boot/reflect.x writes it.)

; === Pre-doc module descriptions ===
; These modules are included before x/doc/doc.x exists, so they cannot wrap
; their own (provide ...) in (doc ...). Their descriptions are registered here
; instead, keyed by module name -- the same key %display-overview looks up.
(doc x/core/predicates
  "Type predicates (null?, pair?, number?, str?, symbol?, char?, ...) built from C primitives.")
(doc x/core/control
  "Core control flow: if and let, as operatives built on match.")

(doc (provide x/doc/doc-prims)
  "Retroactive documentation for C primitives, boot forms, and type system functions.")
