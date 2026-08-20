# x-lang Object System

*Part of the C implementation of x-lang: computational expressions over a minimal, type-agnostic core.*


x-lang ships a small object-oriented class system in the standard library
(`lib/x/type/class.x`). It follows the **message-passing** model made famous by
SICP and Smalltalk: objects own their members, and you interact with an object by
sending it a message — no quoting required.

```scheme
(def-class Point ()
  x y
  (method dist (self) (+ (self x) (self y))))

(def p (new Point x 3 y 4))
(p dist)         ; => 7    call a method
(p x)            ; => 3    read a member
(p x 10)         ; set a member
```

The whole system is written in x-lang with no C code — it is built on the runtime
type system's `call` handler (see [How it works](#how-it-works) and
[Type System](type-system.md)). It supports single inheritance with `super`,
members are mutable, and access is encapsulated: from the outside an object is
reached **only** through `(obj …)` dispatch. **Classes are objects too** — they
carry static methods and class-wide members and double as namespaces (see
[Classes as objects](#classes-as-objects-statics-and-namespaces)).

---

### Defining a class

`def-class` introduces a class and binds it to a name. Member names, method names,
and the class name are all literal — `def-class` is an operative, so nothing is
quoted. Members and methods are declared **directly** in the body — no wrapper: a
form headed by `method` is a method, anything else is a member.

```scheme
(def-class NAME PARENT-SPEC
  member1                                ; instance members, declared directly:
  (member2 default)                      ;   name | (name default) | (name default "desc")
  (member3 default "a description")
  (method m1 (self . args) body...)      ; instance methods
  ...
  (static                                ; optional class-level block
    (CONST value "a description")         ; class-wide members — same member form
    (method s1 (self . args) body...)))   ; static methods
```

- **`NAME`** — the symbol the class is bound to.
- **`PARENT-SPEC`** — `()` for no parent, or `(extends OtherClass)` for single
  inheritance. These are the only two forms: anything else — a bare
  `(OtherClass)` list, a bare symbol, `(extends)` with no class — is refused
  loudly at class-definition time.
- **member** — `name`, or `(name default)`, or `(name default "description")`. The
  optional middle value is the member's default (used when `new` doesn't supply
  one); the optional trailing string documents it and is shown by `(help Class)`.
  Declare as many (or as few) as you like; a class can have none. A
  `(doc DECL "description" …)` body form **also declares** its member (see
  [Documentation](#documentation)), so declare each member exactly once —
  bare *or* doc-form, never both. A member name declared twice in one class
  body is refused loudly: the duplicate used to poison positional
  construction silently (the doubled slot absorbed two values and a later
  member stayed nil). Subclass overrides are unaffected — the check never
  walks the inheritance chain.
- **`(method NAME (self . params) body...)`** — a method. The first parameter is
  always `self`, the receiving instance; any further parameters receive the
  evaluated message arguments.
- **`(static …)`** — optional; a block of class-wide members (same member form) and
  static methods. See [Classes as objects](#classes-as-objects-statics-and-namespaces).

```scheme
(def-class Circle ()
  r
  (method area (self) (* (self r) (self r)))
  (method scale (self k) (self r (* (self r) k)) self))
```

---

### Creating instances

`new` constructs an instance, taking the class followed by literal member names
paired with values (the values are evaluated, the names are not):

```scheme
(def c (new Circle r 5))
(def c2 (new Circle r (* 2 3)))   ; value side is evaluated
```

A member that `new` doesn't initialise takes its declared default (nil, `()`, if
the declaration gave none). Inherited members are included automatically.

```scheme
(def-class Counter () (n 0))      ; n defaults to 0
((new Counter) n)                 ; => 0     the default
((new Counter n 9) n)             ; => 9     new overrides it
```

---

### Members: methods and data

Send a message by applying the instance to a **literal** member name and any
arguments:

```scheme
(c area)         ; => 25   a method
(c scale 2)      ; => the instance (doubles r)
(c r)            ; => 10   a data member (getter)
(c r 7)          ; a data member (setter)
```

Dispatch is uniform: `(obj name)` looks `name` up as a **method** first; if there
is no such method it is treated as a **data member** — `(obj m)` reads it,
`(obj m v)` writes it. A method therefore **shadows** a member of the same name,
which is the basis for computed properties and for private data (below).

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
  v
  (method total (self) (self v)))

(def-class Bonus (extends Base)
  extra
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
  else `name` is a class-wide member that `(Class m)` reads and `(Class m v)` sets.
- Members hold any value — symbols, strings, numbers — useful for class-wide
  constants and state, and they take the same `(name value "desc")` form.
- Static methods are inherited: a subclass calls or overrides its parents'.
- `(Class new member val …)` constructs an instance — equivalent to the global
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
no global member accessor, so external code cannot poke at an instance's storage by
name:

```scheme
(%member p x)           ; error — no such binding
```

Inside methods, two extra accessors are in scope (and *only* in scope there) for
**raw** member access that bypasses any same-named method override:

```scheme
(member 'name)          ; raw read
(set-member! 'name v)   ; raw write
```

They take a **quoted** name — both because they are ordinary functions and because
the quote visually marks "raw, bypass dispatch." This gives you private data:
override a member's public name with a method, and keep using the raw accessors
internally.

```scheme
(def-class Account ()
  balance
  (method balance (self) 'private)                            ; hide the public name
  (method deposit (self amt)
    (set-member! 'balance (+ (member 'balance) amt)) self)    ; raw access inside
  (method statement (self) (member 'balance)))

(def a (new Account balance 100))
(a deposit 50)
(a balance)      ; => private   the public getter is overridden
(a statement)    ; => 150       a method still sees the real value
```

For ENFORCED privacy, declare members and methods inside a `(private ...)` or
`(protected ...)` block (at the body top level, or inside `(static ...)`):

```lisp
(def-class Account ()
  (private balance
    (method %audit (self) ...))            ; private: this class's methods only
  (protected (method helper (self) ...))   ; protected: methods anywhere on the chain
  (method deposit (self n) (self balance (+ (self balance) n)) self))
```

The check runs at the dispatch door -- a violation errors naming the class,
selector, tier, and defining class -- and costs public method calls exactly one
added pair test. Enforcement is opt-in per class: undeclared members stay
public, and the `%` prefix remains a naming convention for protocol hooks, not
a privacy marker.

> **Caveat:** reflection remains the documented escape, exactly as at the C
> level: `(help)` and the introspection functions still list guarded members,
> an instance still stores its payload in slot 0, and `(first a)` or the
> `%obj-*` helpers can reach in. The dispatch door is the contract surface;
> raw reflection is the maintenance hatch.

---

### Introspection

| Function | Result |
|----------|--------|
| `(object? x)` | `#t` if `x` is an object instance |
| `(class? x)` | `#t` if `x` is a class |
| `(class-of inst)` | the (callable) class an instance belongs to |
| `(class-name x)` | the name symbol of a class, or of an instance's class |
| `(instance-of? inst Class)` | `#t` if `inst` is a `Class` or a subclass of it |
| `(class-members c)` / `(class-methods c)` | a class's own instance member / method names |
| `(class-static-members c)` / `(class-static-methods c)` | its own static member / method names |

```scheme
(instance-of? b Bonus)    ; => #t
(instance-of? b Base)     ; => #t   (Bonus extends Base)
(object? 42)              ; => #f
```

`class-name` returns a *symbol*; at the REPL it prints as `'Bonus`, while
`(display (class-name b))` shows `Bonus`.

---

### Documentation

`(help Class)` lists everything a class offers, grouped **static vs instance** and
**members vs methods**, each list merged across the inheritance chain and sorted by
name (a subclass override hides the inherited entry). Members and methods documented
with a description string show it; empty groups are omitted:

```
Counter
  static:
    members:
      LIMIT -- max before reset
    methods:
      reset -- reset the count to zero
  members:
    count -- the running count
    step
  methods:
    bump -- increment the counter
```

A method is documented with a leading `(doc "description" …)` form; a member with
its trailing `"description"` string, or with a body-level
`(doc DECL "description" …)` form — which **declares the member as well as
documenting it**, so a doc-form member needs no separate bare declaration
(and having both is a refused duplicate). `(help Class member-or-method)`
prints the full entry for one of them, and `(help x/type/object)` prints the
module overview.

---

### Printing

Instances print as `#<ClassName member=value ...>`:

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
chain); finding none, it falls back to member get/set. This is the dispatch hook
described in the [Type System](type-system.md) guide — the object system is its
richest example.

There are two callable types. An **instance** (`%object`) stores `(class . member-box)`,
where `member-box` is a one-cell mutable box holding the member alist; a member
write swaps that alist in place. A **class** (`%class`) is itself a callable object
whose payload is a descriptor alist — `name`, members, `methods`, `parent`, plus
`s-methods` (static methods) and a `statics` box (class-wide members). Each type's
`call` handler runs the same method-then-member dispatch — one over an instance's
members, the other over a class's statics. Class identity (used by `instance-of?`
and inheritance) is checked with `same?` (pointer identity), not `eq?` (value
equality), since value-comparing two classes would recurse through their method
closures.

One implementation detail: x-lang binds a function's *first* parameter to the
function itself (the recursion handle). `def-class` prepends a hidden slot to each
method's parameter list so the `self` you write lands in the second slot, which
dispatch fills with the receiver; it also wraps each instance-method body so the raw
`member` / `set-member!` accessors are in scope only inside the method.

---

### One model, four doors

Polymorphism in x-lang is one model with four entry doors, ordered by heat:

1. **Message passing** — `(obj sel ...)` / `(Class sel ...)`. Single receiver,
   resolved in a flat, chain-merged per-class table cached on the class (built
   lazily, invalidated by runtime mutation). *The* hot path: reach for it
   whenever behaviour belongs to one thing. `method-of` is the sanctioned
   de-dispatch door for hot loops -- resolve once, call the bare closure.
2. **Value-call, subject-last** — `(1/2 numerator)`, `("a,b" split ",")`. Not a
   dispatch system: routing *sugar* that rewrites a value-headed call into door
   1 on the value's bound class, receiver appended last. Same tables, same
   semantics.
3. **Generic functions** (`x/type/generic`) — `(num+ a b)`, `(dot u v)`. Open,
   multi-argument, type-directed: `def-generic` + `(on g (SIG...) body)`, with
   pointwise specificity (exact > nearer ancestor > wildcard; no scalar rank),
   the cvt from-lattice as the ambiguity tie-break, and a teaching error naming
   both candidates when the lattice is silent. The cold-path flexibility layer:
   reach for it when behaviour depends on the types of *several* arguments --
   the thing doors 1-2 structurally cannot express. The numeric tower's
   mixed-type policy (`x/num/tower`) is the worked example.
4. **The C ops cell** — exactly seven spellings (`+ - * / % = <`). Not a
   general facility: a fixed door whose per-type handlers are one-line shims
   into door 3's tower generics. Arbitration between two typed operands reads
   the cvt from-lattice -- the same relation door 3 reads, so promotion has one
   authority everywhere. Bitwise and identity (`eq?`/`same?`) never dispatch,
   by ruling.

Doors never fight: a call site is syntactically exactly one door. `(x sel ...)`
with a symbol selector is doors 1-2; `(g v1 v2)` where `g` names a generic is
door 3 -- generics are values called by name, never selectors. The library rule
of thumb: single-receiver concepts are methods; multi-receiver concepts are
generics; methods may delegate down to generics; generics never re-enter
selector dispatch on the same arguments.

Composition and contracts change what lands in the tables, never how a call
routes:

- **`(with Trait...)`** mixes a `def-trait` bundle in at class definition --
  built against the host's chain (`super` works) in the trait's environment
  (free names resolve at the definition site). Own method > trait > inherited;
  two traits on one selector refuse without an own override; `(require ...)`
  names check against the whole chain.
- **`(delegates field (sel... (theirs ours)...))`** states the
  wrapper-forwards-to-a-field relationship once, as generated late-bound
  forwarders.
- **`(interface ...)`** remains the abstract contract on an extends-chain --
  three distinct tools, deliberately not unified.
- **`def-record`** is the data-carrier shorthand: a class with the positional
  constructor plus `with` (functional update, quoted keys) and `=?`
  (structural equality -- a method; `eq?`/`same?` keep identity, by ruling).

Classes are also **open**: `(C def-method! sel fn)` / `(C def-static! sel fn)`
add methods after definition (computed selectors welcome; the cold class data
mutates and every cached table refolds), and a `(method %missing (self sel
args) ...)` protocol hook catches what dispatch cannot resolve.

---

### Worked example

A bank account with a private balance and a savings subclass that adds interest:

```scheme
(def-class Account ()
  balance
  (method balance (self) 'private)                            ; public name hidden
  (method deposit (self amt)
    (set-member! 'balance (+ (member 'balance) amt)) self)
  (method amount (self) (member 'balance)))

(def-class Savings (extends Account)
  rate
  (method add-interest (self)
    (self deposit (* (member 'balance) (member 'rate)))))     ; raw read of inherited member

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
| `(def-class Name (extends P?) member... (method ...) (static ...))` | Define a class |
| `(new Class member val ...)` / `(Class new member val ...)` | Construct an instance |
| `(obj name args...)` | Send a message (instance method, or member if no method) |
| `(obj member)` / `(obj member val)` | Read / write an instance member |
| `(Class name args...)` | Static method, or class-wide member if no method |
| `(Class member)` / `(Class member val)` | Read / write a class-wide member |
| `(super self name args...)` | Call the parent's method |
| `(member 'name)` / `(set-member! 'name v)` | Raw member access — **inside methods only** |
| `(object? x)` / `(class? x)` | Instance / class predicate |
| `(class-of inst)` / `(class-name x)` | Class of an instance / name of a class or instance |
| `(instance-of? inst Class)` | Subtype predicate |

Every form is in the REPL help system — `(help def-class)`, `(help new)`, … — and
`(help x/type/object)` prints the module overview. See also the
[Type System](type-system.md) for the underlying `make-type` mechanism, and the
[Standard Library](standard-library.md) reference.
