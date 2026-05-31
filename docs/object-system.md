# Computational Expressions in C

## Object System

x-lang ships a small object-oriented class system in the standard library
(`lib/x/type/object.x`). It follows the **message-passing** model made famous by
SICP and Smalltalk: objects own their members, and you interact with an object by
sending it a message — no quoting required.

```scheme
(def-class Point ()
  (fields x y)
  (method dist (self) (+ (self x) (self y))))

(def p (new Point x 3 y 4))
(p dist)         ; => 7    call a method
(p x)            ; => 3    read a field
(p x 10)         ; set a field
```

The whole system is written in x-lang with no C code — it is built on the runtime
type system's `call` handler (see [How it works](#how-it-works) and
[Type System](type-system.md)). It supports single inheritance with `super`,
fields are mutable, and access is encapsulated: from the outside an object is
reached **only** through `(obj …)` dispatch. **Classes are objects too** — they
carry static methods and class-wide members and double as namespaces (see
[Classes as objects](#classes-as-objects-statics-and-namespaces)).

---

### Defining a class

`def-class` introduces a class and binds it to a name. Field names, method names,
and the class name are all literal — `def-class` is an operative, so nothing is
quoted:

```scheme
(def-class NAME PARENT-SPEC
  (fields f1 f2 ...)
  (method m1 (self . args) body...)
  ...
  (static                                ; optional class-level block
    (member1 value)
    (method s1 (self . args) body...)))
```

- **`NAME`** — the symbol the class is bound to.
- **`PARENT-SPEC`** — `()` for no parent, or `(extends OtherClass)` for single
  inheritance.
- **`(fields ...)`** — the instance field names, in declaration order. Optional;
  omit or use `(fields)` for a class with no fields.
- **`(method NAME (self . params) body...)`** — a method. The first parameter is
  always `self`, the receiving instance; any further parameters receive the
  evaluated message arguments.
- **`(static …)`** — optional; a block of class-wide members `(name value)` and
  static methods. See [Classes as objects](#classes-as-objects-statics-and-namespaces).

```scheme
(def-class Circle ()
  (fields r)
  (method area (self) (* (self r) (self r)))
  (method scale (self k) (self r (* (self r) k)) self))
```

---

### Creating instances

`new` constructs an instance, taking the class followed by literal field names
paired with values (the values are evaluated, the names are not):

```scheme
(def c (new Circle r 5))
(def c2 (new Circle r (* 2 3)))   ; value side is evaluated
```

Fields that are not initialised default to nil (`()`). Inherited fields are
included automatically.

---

### Members: methods and fields

Send a message by applying the instance to a **literal** member name and any
arguments:

```scheme
(c area)         ; => 25   a method
(c scale 2)      ; => the instance (doubles r)
(c r)            ; => 10   a field (getter)
(c r 7)          ; a field (setter)
```

Dispatch is uniform: `(obj name)` looks `name` up as a **method** first; if there
is no such method it is treated as a **field** — `(obj f)` reads it, `(obj f v)`
writes it. A method therefore **shadows** a field of the same name, which is the
basis for computed properties and for private data (below).

> `(obj 'name)` also works — a quoted selector is unwrapped to the bare name — but
> `(obj name)` is idiomatic. The `'` reader is a separate general feature
> (`lib/x/type/lit-reader.x`); objects don't need it.

---

### Inside methods

Within a method, `self` is the receiving instance, and you reach its members the
same way — `(self name)` / `(self name value)`:

```scheme
(method scale (self k)
  (self r (* (self r) k))    ; read r, then write it
  self)
```

---

### Inheritance

A class may extend one parent. Method lookup walks the parent chain, so a subclass
inherits the parent's methods and may override them. `super` invokes the parent's
version of a method (selector literal, as everywhere):

```scheme
(def-class Base ()
  (fields v)
  (method total (self) (self v)))

(def-class Bonus (extends Base)
  (fields extra)
  (method total (self)                 ; override that extends the parent
    (+ (super self total) (self extra))))

(def b (new Bonus v 10 extra 5))
(b total)               ; => 15   (Base.total = 10, plus extra 5)
(instance-of? b Base)   ; => #t
```

`super` resolves to the parent of the method's **defining** class — the level is
baked in when `def-class` builds the method, not computed from the receiver's
runtime class. So an inherited method that calls `super` reaches the correct
ancestor even several levels down a chain, instead of looping back on itself.
Calling `super` outside an instance method (e.g. from a static) is an error.

---

### Classes as objects: statics and namespaces

A class is itself a callable object, so it can hold class-wide members and static
methods — the same dispatch, one level up (`self` is the class). Declare them in a
`(static …)` block:

```scheme
(def-class Math ()
  (static
    (base 10)                                    ; class-wide member (any value)
    (method square (self n) (* n n))             ; static method
    (method scaled (self n) (* n (self base))))) ; static method using (self base)

(Math square 5)    ; => 25     call a static method
(Math base)        ; => 10     read a class-wide member
(Math base 100)    ; write it
(Math scaled 3)    ; => 300     after the write
```

- `(Class name …)` dispatches on the class: a static method named `name` wins,
  else `name` is a class-wide member that `(Class f)` reads and `(Class f v)` sets.
- Members hold any value — symbols, strings, numbers — useful for class-wide
  constants and state.
- Static methods are inherited: a subclass calls or overrides its parents'.
- `(Class new field val …)` constructs an instance — equivalent to the global
  `(new Class …)`.

So a class doubles as a **namespace** of static functions, the way modules do in
Python:

```scheme
(def-class Mathx ()
  (static (method cube (self n) (* n (* n n))) (method double (self n) (* 2 n))))

(Mathx cube 3)     ; => 27
(Mathx double 5)   ; => 10
```

`class?` tests for a class, `class-name` works on a class or an instance, and a
class prints as `#<class Name>`.

---

### Encapsulation and private data

From outside, an object is reached **only** through `(obj …)` dispatch — there is
no global field accessor, so external code cannot poke at an instance's storage by
name:

```scheme
(%field p x)            ; error — no such binding
```

Inside methods, two extra accessors are in scope (and *only* in scope there) for
**raw** field access that bypasses any same-named method override:

```scheme
(field 'name)           ; raw read
(set-field! 'name v)    ; raw write
```

They take a **quoted** name — both because they are ordinary functions and because
the quote visually marks "raw, bypass dispatch." This gives you private data:
override a field's public name with a method, and keep using the raw accessors
internally.

```scheme
(def-class Account ()
  (fields balance)
  (method balance (self) 'private)                          ; hide the public name
  (method deposit (self amt)
    (set-field! 'balance (+ (field 'balance) amt)) self)    ; raw access inside
  (method statement (self) (field 'balance)))

(def a (new Account balance 100))
(a deposit 50)
(a balance)      ; => private   the public getter is overridden
(a statement)    ; => 150       a method still sees the real value
```

> **Caveat:** this is encapsulation by *interface*, not by enforcement. x-lang has
> no private scope, and an instance still stores its payload in slot 0, so
> `(first a)` and the internal `%obj-*` helpers can reach in. Removing the named
> raw API closes the obvious door; full opacity would need a different (closure-
> captured) instance representation.

---

### Introspection

| Function | Result |
|----------|--------|
| `(object? x)` | `#t` if `x` is an object instance |
| `(class? x)` | `#t` if `x` is a class |
| `(class-of inst)` | the (callable) class an instance belongs to |
| `(class-name x)` | the name symbol of a class, or of an instance's class |
| `(instance-of? inst Class)` | `#t` if `inst` is a `Class` or a subclass of it |

```scheme
(instance-of? b Bonus)    ; => #t
(instance-of? b Base)     ; => #t   (Bonus extends Base)
(object? 42)              ; => #f
```

`class-name` returns a *symbol*; at the REPL it prints as `(lit Bonus)`, while
`(display (class-name b))` shows `Bonus`.

---

### Printing

Instances print as `#<ClassName field=value ...>`:

```scheme
(write (new Circle r 4))
; #<Circle r=4>
```

This comes from a `write` handler on the object type; it can be extended to prefer
a user-defined `to-string` method.

---

### How it works

The system defines a single runtime type, `%object`, via `make-type`. Its **`call`
handler is an operative**, so when you write `(obj name args…)` the handler
receives `self` = the instance, `name` **unevaluated** (a literal selector, no
quote needed — like `def`), and the remaining args still evaluatable in the
caller's environment. The handler looks `name` up as a method (walking the parent
chain); finding none, it falls back to field get/set. This is the dispatch hook
described in the [Type System](type-system.md) guide — the object system is its
richest example.

There are two callable types. An **instance** (`%object`) stores `(class . field-box)`,
where `field-box` is a one-cell mutable box holding the field alist; a field write
swaps that alist in place. A **class** (`%class`) is itself a callable object whose
payload is a descriptor alist — `name`, `fields`, `methods`, `parent`, plus
`s-methods` (static methods) and a `statics` box (class-wide members). Each type's
`call` handler runs the same method-then-field dispatch — one over an instance's
members, the other over a class's statics. Class identity (used by `instance-of?`
and inheritance) is checked with `same?` (pointer identity), not `eq?` (value
equality), since value-comparing two classes would recurse through their method
closures.

One implementation detail: x-lang binds a function's *first* parameter to the
function itself (the recursion handle). `def-class` prepends a hidden slot to each
method's parameter list so the `self` you write lands in the second slot, which
dispatch fills with the receiver; it also wraps each instance-method body so the raw
`field` / `set-field!` accessors are in scope only inside the method.

---

### Relationship to CLOS

This is **single-receiver message passing**: dispatch depends only on the
receiver. It is not [CLOS](https://en.wikipedia.org/wiki/Common_Lisp_Object_System)
— there are no generic functions and no multiple dispatch. The path toward
CLOS-style generic functions would introduce function objects that dispatch on the
types of *all* their arguments, generalising the type-keyed dispatch already used
by `convert` (`lib/x/sys/convert.x`), which selects a handler by argument type and
supports a wildcard default. The message-passing layer would remain the simple,
fast common case.

---

### Worked example

A bank account with a private balance and a savings subclass that adds interest:

```scheme
(def-class Account ()
  (fields balance)
  (method balance (self) 'private)                          ; public name hidden
  (method deposit (self amt)
    (set-field! 'balance (+ (field 'balance) amt)) self)
  (method amount (self) (field 'balance)))

(def-class Savings (extends Account)
  (fields rate)
  (method add-interest (self)
    (self deposit (* (field 'balance) (field 'rate)))))     ; raw read of inherited field

(def s (new Savings balance 100 rate 1))
(s deposit 50)        ; balance -> 150
(s add-interest)      ; deposits 150 * 1 = 150 -> balance 300
(s amount)            ; => 300
(s balance)           ; => private   (still hidden)
(instance-of? s Account)   ; => #t
```

---

### API summary

| Form | Purpose |
|------|---------|
| `(def-class Name (extends P?) (fields ...) (method ...) (static ...))` | Define a class |
| `(new Class field val ...)` / `(Class new field val ...)` | Construct an instance |
| `(obj name args...)` | Send a message (instance method, or field if no method) |
| `(obj field)` / `(obj field val)` | Read / write an instance field |
| `(Class name args...)` | Static method, or class-wide member if no method |
| `(Class member)` / `(Class member val)` | Read / write a class-wide member |
| `(super self name args...)` | Call the parent's method |
| `(field 'name)` / `(set-field! 'name v)` | Raw field access — **inside methods only** |
| `(object? x)` / `(class? x)` | Instance / class predicate |
| `(class-of inst)` / `(class-name x)` | Class of an instance / name of a class or instance |
| `(instance-of? inst Class)` | Subtype predicate |

Every form is in the REPL help system — `(help def-class)`, `(help new)`, … — and
`(help x/type/object)` prints the module overview. See also the
[Type System](type-system.md) for the underlying `make-type` mechanism, and the
[Standard Library](standard-library.md) reference.
