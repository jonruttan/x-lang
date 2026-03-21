; doc-prims.x -- Documentation for C primitives and x-core operatives
;
; Uses bare-symbol doc form: (doc name "description" (param ...) ...)

; === Core forms ===

(note "Core forms")

(doc lit "Return the argument unevaluated (quote)."
  (param form ANY "Any expression")
  (returns ANY "The expression itself")
  (example "(lit x)" "x")
  (example "(lit (1 2 3))" "(1 2 3)"))

(doc def "Bind a name to a value in the current environment."
  (param name SYMBOL "Name to bind")
  (param value ANY "Expression to evaluate and bind")
  (note "Supports recursive definitions: name is pre-bound before value is evaluated.")
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
  (example "(def my-if (op (_ test then else) e (if (eval test e) (eval then e) (eval else e))))" "")
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
  (example "(guard (e (list (lit error) e)) (+ 1 \"x\"))" "(error \"...\")"))

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

(doc + "Add two integers."
  (param a INT "First operand")
  (param b INT "Second operand")
  (returns INT "Sum"))

(doc - "Subtract two integers."
  (param a INT "First operand")
  (param b INT "Second operand")
  (returns INT "Difference"))

(doc * "Multiply two integers."
  (param a INT "First operand")
  (param b INT "Second operand")
  (returns INT "Product"))

(doc / "Integer division."
  (param a INT "Dividend")
  (param b INT "Divisor")
  (returns INT "Quotient"))

(doc % "Integer modulo."
  (param a INT "Dividend")
  (param b INT "Divisor")
  (returns INT "Remainder"))

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
  (returns BOOLEAN "t if identical"))

(doc = "Test numeric equality."
  (param a INT "First number")
  (param b INT "Second number")
  (returns BOOLEAN "t if equal"))

(doc < "Test numeric less-than."
  (param a INT "First number")
  (param b INT "Second number")
  (returns BOOLEAN "t if a < b"))

(doc char->integer "Convert a character to its integer code point."
  (param c CHAR "A character")
  (returns INT "Code point"))

(doc integer->char "Convert an integer code point to a character."
  (param n INT "Code point")
  (returns CHAR "A character"))

; === Strings ===

(note "Strings")

(doc string-append "Concatenate two strings."
  (param a STRING "First string")
  (param b STRING "Second string")
  (returns STRING "Concatenated string"))

(doc string->symbol "Convert a string to a symbol (interned)."
  (param s STRING "A string")
  (returns SYMBOL "An interned symbol"))

(doc symbol->string "Convert a symbol to a string."
  (param sym SYMBOL "A symbol")
  (returns STRING "The symbol's name"))

(doc list->string "Convert a list of characters to a string."
  (param chars LIST "List of characters")
  (returns STRING "A string"))

; === I/O ===

(note "I/O")

(doc write "Write a value in machine-readable form."
  (param val ANY "Value to write")
  (note "Strings are quoted, characters show read syntax. Use for serialization.")
  (see display) (see write-to-string))

(doc display "Display a value in human-readable form."
  (param val ANY "Value to display")
  (note "Strings are unquoted, characters are bare. Use for user output.")
  (see write) (see display-to-string))

(doc read "Read and parse one expression from stdin."
  (returns ANY "Parsed expression"))

(doc read-char "Read one character from stdin."
  (returns CHAR "A character, or nil at EOF"))

(doc write-to-string "Capture write output as a string."
  (param val ANY "Value to write")
  (returns STRING "The written representation"))

(doc display-to-string "Capture display output as a string."
  (param val ANY "Value to display")
  (returns STRING "The displayed representation"))

; === Memory ===

(note "Memory management")

(doc heap-mark "Mark all reachable objects in the heap."
  (returns INT "Number of marked objects"))

(doc heap-sweep "Sweep unmarked objects from the heap."
  (returns INT "Number of freed objects"))

(doc heap-count "Return the number of live objects on the heap."
  (returns INT "Object count"))

(doc gc-pin! "Pin an object to prevent garbage collection."
  (param obj ANY "Object to pin"))

; === Type system ===

(note "Type system")

(doc make-type "Create a new custom type with handlers."
  (param name STRING "Type name")
  (param handlers LIST "Alist of handler functions")
  (returns ATOM "Type handle")
  (note "Handlers: call, eval, write, display, read, analyse, first-chars, from, to, iter.")
  (see make-instance) (see type?) (see type-of))

(doc make-instance "Create an instance of a custom type."
  (param type ATOM "Type handle from make-type")
  (param data ANY "Instance data")
  (returns ANY "A new type instance"))

(doc type? "Test if a value is an instance of a type."
  (param type ATOM "Type handle")
  (param val ANY "Value to test")
  (returns BOOLEAN "t if val is of the given type"))

(doc type-of "Return the type handle of a value."
  (param val ANY "Any value")
  (returns ATOM "Type handle"))

(doc type-name "Return the name string of a type handle."
  (param type ATOM "Type handle")
  (returns STRING "Type name"))

(doc make-base "Create a new base object (execution context)."
  (returns BASE "A fresh base with types and primitives"))

(doc iter "Create an iterator for a value."
  (param val ANY "Iterable value")
  (returns CALLABLE "Iterator function: () -> next value or nil"))

(doc token-read-string "Tokenize a string using a base's type system."
  (param base BASE "Base object with type alist")
  (param s STRING "Source string to tokenize")
  (returns LIST "List of parsed tokens"))

; === FFI ===

(note "Foreign function interface")

(doc dlopen "Load a shared library."
  (param path STRING "Library file path")
  (param mode INT "dlopen mode flags")
  (returns PTR "Library handle"))

(doc dlsym "Look up a symbol in a loaded library."
  (param lib PTR "Library handle from dlopen")
  (param name STRING "Symbol name")
  (returns PTR "Function or data pointer"))

(doc ptr-call "Call a C function pointer with string args."
  (param ptr PTR "Function pointer")
  (param args STRING "Arguments (variadic)")
  (returns INT "Return value"))

(doc obj->ptr "Get the raw pointer of an x-lang object."
  (param obj ANY "Any object")
  (returns PTR "Raw pointer"))

(doc ptr->int "Convert a pointer to an integer."
  (param p PTR "A pointer")
  (returns INT "Integer representation"))

(doc int->ptr "Convert an integer to a pointer."
  (param n INT "Integer value")
  (returns PTR "A pointer"))

; === Continuations ===

(note "Continuations")

(doc call/cc "Call a function with the current continuation."
  (param f CALLABLE "Function receiving the continuation")
  (returns ANY "Result of f, or value passed to continuation"))

; === x-core operatives ===

(note "x-core operatives")

(doc null? "Test if a value is nil (the empty list)."
  (param x ANY "Value to test")
  (returns BOOLEAN "t if nil"))

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
  (see let*) (see letrec))

(doc do "Evaluate expressions sequentially, return last result."
  (param exprs ANY "One or more expressions")
  (example "(do (display \"hi\") 42)" "42"))

(doc begin "Alias for do."
  (see do))

(doc not "Logical negation."
  (param x ANY "Value to negate")
  (returns BOOLEAN "t if x is falsy"))

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

(doc convert "Convert a value between types."
  (param val ANY "Value to convert")
  (param type ATOM "Target type handle")
  (returns ANY "Converted value"))

(doc newline "Display a newline character.")

(doc quasi "Quasiquote: template with unquote and splicing."
  (param template ANY "Template expression with , and ,@ escapes")
  (note "Use , to unquote a single expression, ,@ to splice a list.")
  (example "(let ((x 42)) (quasi (a ,x b)))" "(a 42 b)"))

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
  (returns BOOLEAN "t if atom"))

(doc number->string "Convert an integer to a string."
  (param n INT "Integer to convert")
  (param radix INT "Base (optional, default 10)")
  (returns STRING "String representation"))

(doc string->number "Parse a string as an integer."
  (param s STRING "String to parse")
  (returns INT "Parsed integer, or nil on failure"))

(doc string-ref "Return the character at an index in a string."
  (param s STRING "A string")
  (param i INT "Zero-based index")
  (returns CHAR "Character at index"))

(doc string-length "Return the length of a string."
  (param s STRING "A string")
  (returns INT "Number of characters"))

(doc substring "Extract a substring."
  (param s STRING "Source string")
  (param start INT "Start index (inclusive)")
  (param end INT "End index (exclusive)")
  (returns STRING "The substring"))

(doc string=? "Test string equality."
  (param a STRING "First string")
  (param b STRING "Second string")
  (returns BOOLEAN "t if equal"))

(doc make-string "Create a string of repeated characters."
  (param n INT "Length")
  (param c CHAR "Fill character")
  (returns STRING "A new string"))

(doc gcd "Greatest common divisor."
  (param a INT "First integer")
  (param b INT "Second integer")
  (returns INT "GCD"))

(doc lcm "Least common multiple."
  (param a INT "First integer")
  (param b INT "Second integer")
  (returns INT "LCM"))

(doc heap-collect "Run a full garbage collection cycle."
  (returns INT "Number of freed objects"))
