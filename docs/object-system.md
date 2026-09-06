# x-lang Object System

*x-lang: computational expressions over a minimal, type-agnostic engine.*


x-lang ships a small object-oriented class system in the standard library
(`lib/x/type/class.x`). It follows the **message-passing** model made famous by
SICP and Smalltalk: objects own their members, and you interact with an object by
sending it a message — no quoting required.

```x
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

```x
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

```x
(def-class Circle ()
  r
  (method area (self) (* (self r) (self r)))
  (method scale (self k) (self r (* (self r) k)) self))
```

---

### Creating instances

`new` constructs an instance, taking the class followed by literal member names
paired with values (the values are evaluated, the names are not):

```x
(def c (new Circle r 5))
(def c2 (new Circle r (* 2 3)))   ; value side is evaluated
```

A member that `new` doesn't initialise takes its declared default (nil, `()`, if
the declaration gave none). Inherited members are included automatically.

```x
(def-class Counter () (n 0))      ; n defaults to 0
((new Counter) n)                 ; => 0     the default
((new Counter n 9) n)             ; => 9     new overrides it
```

---

### Members: methods and data

Send a message by applying the instance to a **literal** member name and any
arguments:

```x
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

```x
(method scale (self k)
  (self r (* (self r) k))    ; read r, then write it
  self)
```

---

### Inheritance

A class may extend one parent. Method lookup walks the parent chain, so a subclass
inherits the parent's methods and may override them. `super` invokes the parent's
version of a method (selector literal, as everywhere):

```x
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

```x
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
- Static methods **and class-wide members** are inherited: a read reaches the
  nearest ancestor that declares the member, and a write through a subclass
  **shadows** into the subclass's own storage — the parent's value is never
  mutated through a child (write to the parent by naming it: `(Parent m v)`).
- `(Class new member val …)` constructs an instance — equivalent to the global
  `(new Class …)`.

So a class doubles as a **namespace** of static functions, the way modules do in
Python:

```x
(def-class Mathx ()
  (static (method cube (self n) (* n (* n n))) (method double (self n) (* 2 n))))

(Mathx cube 3)     ; => 27
(Mathx double 5)   ; => 10
```

`class?` tests for a class, `class-name` works on a class or an instance, and a
class prints as `#<class Name>`.

---

### Records: `def-record`

For plain data carriers — a handful of named fields, no behaviour to speak of —
`def-record` is the shorthand. A record **is** a class (instances are ordinary
objects; construction, access, writes, and printing all ride the doors above)
plus the two methods a data carrier wants:

```x
(def-record Span start len (colour ()))

(def s (new Span 3 5))       ; the ordinary positional/keyword constructor
(s start)                    ; => 3       field access, the ordinary door
(def s2 (s with 'len 9))     ; functional update -> a NEW record; s untouched
(s =? (new Span 3 5))        ; => #t      structural equality, field by field
```

`with` keys are **quoted** — `with` is a method, so its arguments evaluate
(`new`'s bare keys work because `new` is an operative). `=?` compares same
class then `equal?` per field; it is a *method* by design — `eq?` and `same?`
keep identity semantics, by ruling. Records are leaves: to extend one, write
the `def-class` out.

---

### Generic functions: `def-generic` and `on`

When behaviour depends on the types of **several** arguments — the thing
single-receiver dispatch structurally cannot express — define a generic
(`(import x/type/generic)`):

```x
(def-generic area)
(on area ((c Circle)) (* 3 (* (c r) (c r))))     ; a CLASS key: instances,
(on area ((s Square)) (* (s side) (s side)))     ;   subclasses included
(on area (x) 'dunno)                             ; bare name = wildcard

(area (new Circle r 2))     ; => 12
(%map (fn (_ v) (area v)) shapes)   ; a generic is a callable VALUE
```

Signature keys are values: a class (nearer definitions win down a chain), a
type handle from `(Type of v)` (exact), or a bare name (wildcard). Selection
is pointwise — exact beats a nearer ancestor beats the wildcard, position by
position, with no scalar rank — and two incomparable candidates fall to the
cvt from-lattice, then to an error naming both. A total miss errors naming the
generic and the argument types, unless the generic carries a
`(Generic miss! g handler)` — the numeric tower's promotion rides exactly
there (`x/num/tower` is the worked example).

---

### Traits: `def-trait` and `(with ...)`

A trait is a named bundle of methods (and requirements) mixed in at class
definition (`(import x/type/trait)`):

```x
(def-trait Comparable
  (require cmp)                              ; the host chain must provide these
  (method <? (self other) (< (self cmp other) 0))
  (method >? (self other) (< 0 (self cmp other))))

(def-class Version ()
  (with Comparable)
  parts
  (method cmp (self other) ...))
```

Trait bodies close over their **definition site** (free names resolve where
the trait was written) but build against the **host's** chain — `super` and
member access work as if written in the class. Precedence is explicit, no
linearization: the class's own method beats a trait's beats an inherited one;
two traits supplying one selector refuse at definition time unless the class
overrides it; an unmet `(require ...)` refuses at definition, and
trait-supplied methods satisfy `(interface ...)` contracts. Traits are for
shared *behaviour*; for the wrapper-over-a-field relationship use
`delegates`:

```x
(def-class Bag ()
  (d)
  (delegates d (has? length (keys names)))   ; forwarders, rename pairs allowed
  (method %init (self) (self d (Dict make))))
```

Each entry forwards to the field's value **per call** (a swapped delegate is
honoured). Methods only — a delegate's plain field read stays a one-line hand
method. `interface` remains the third tool: the abstract contract on an
extends-chain.

---

### Open classes and `%missing`

Classes accept new methods after definition:

```x
(Logo def-static! 'square (fn (_ self n) ...))   ; selector may be computed
((new P) ...)                                    ; every instance sees it
```

`(C def-method! sel fn)` adds an instance method, `(C def-static! sel fn)` a
static; both are built-in class selectors (shadowable by a same-named static,
like `new`). The fn is stored as-is — it receives `(self . args)` and uses
`(self f)` member access. The class's data mutates (so `(help)` sees the
addition immediately) and every cached dispatch table refolds.

---

### Block-form methods

A higher-order method normally takes a callable. `Block method!` gives one a
second call shape where the callback's parameter names and body are written at
the call site:

```x
(List map (fn (_ x) (* x 10)) xs)   ; applicative -- always available
(List map (x) (* x 10) xs)          ; block form
(List map (x i) (list i x) xs)      ; a second name is the 0-based index
```

Both forms stay live on the same selector; `(help List/map)` keeps answering
with the applicative signature. Each class wires its own selectors beside the
methods being wrapped, so `x/type/block` is the mechanism and never reaches
down into a collection:

| Class | Wrapped selectors |
|---|---|
| `List` | `map` `filter` `for-each` `find` `flat-map` `sort-by` `take-while` `any?` `all?` `group-by` `partition` `fold` `sort` `reduce` |
| `Vector` | `map` `filter` `for-each` `fold` |
| `Iter` | `for-each` `fold` |
| `Seq` | `for-each` `fold` — inherited by every subclass, `Str8` included |
| `Gen` | `map` `filter` `for-each` `find` `take-while` `any?` `all?` `fold` `reduce` |
| `Dict` | `for-each` `map` (pair shape) |
| `Set` | `map` `filter` `for-each` `fold` |

Adding another is one `(Block method! Class sel ...)` line, plus its selector
name in the linter's table (`Lint %lint-block-selectors`) so the block's names
are not reported undefined.

The mechanism is an ordinary stored method that happens to be an `op`, so
nothing in the dispatch path changes and an unwrapped selector pays nothing.
Because an operative receives its argument *forms*, it can see how many names
the block declared — which is what makes the optional index possible at all:
the language has no arity introspection, and calls are lenient, so an
applicative method handed a two-parameter callback would silently bind nil.

What a second name means is declared per selector, because callback shapes
differ:

| Shape | One name | Two names | Three names |
|---|---|---|---|
| `element` (default) | element | element, index | — |
| `pair` | the `(k . v)` pair | key, value | — |
| `fold` | — | acc, element | acc, element, index |
| `binary` | — | a, b | — |

The second option is how many argument forms follow the callback: `1` for a
static method (the subject, spliced last by the value handler), `0` for an
instance method (the receiver is `self`), `2` for `fold` (init, then subject).
`Dict`'s `for-each` is an instance method and `List`'s is a static — the two
conventions differ in argument layout, and `Block method!` probes the static
table first, then the instance table, so the caller does not have to know
which a given class uses.

```x
(Block method! Dict 'for-each 'pair 0)
(Block method! List 'fold 'fold 2)
```

Two limits are worth knowing. A binding list is recognised structurally — a
non-empty list of symbols in the callback seat — so a *computed* callable built
only from symbols, `(List map (make-f x) a b)`, reads as a block; spell that one
with an explicit `(fn ...)`. And after wrapping, the stored method **is** the
operative, so `(method-of Class sel)` on a block-enabled selector returns
something that must not be called directly.

The `%missing` protocol hook catches what dispatch cannot resolve — instance
and static sides, inherited like any method:

```x
(def-class Logo ()
  (static
    (method %missing (self sel args)
      (Str8 str "I don't know how to " sel))))
(Logo spiral 3)     ; => "I don't know how to spiral"
```

Without a hook, a miss errors naming the class and selector.

---

### Encapsulation and private data

From outside, an object is reached **only** through `(obj …)` dispatch — there is
no global member accessor, so external code cannot poke at an instance's storage by
name:

```x
(%member p x)           ; error — no such binding
```

Privacy is declared, per class, with a `(private ...)` or `(protected ...)`
block (at the body top level, or inside `(static ...)`):

```x
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

Inside methods, two extra accessors are in scope (and *only* in scope there)
for **raw** member access:

```x
(member 'name)          ; raw read
(set-member! 'name v)   ; raw write
```

They take a **quoted** name — both because they are ordinary functions and
because the quote visually marks "raw, bypass dispatch." They read the field's
storage directly, so a method can reach a member even when a same-named method
shadows its public door (a method shadows a member of the same name — the
basis for computed properties). Being method-local by construction, they are
the strictest private door of all: no code outside a method body has them.

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

```x
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
prints the full entry for one of them, and `(help x/type/class)` prints the
module overview.

---

### Printing

Instances print as `#<ClassName member=value ...>`:

```x
(write (new Circle r 4))
; #<Circle r=4>
```

This is the default dump. A class overrides it with the `%repr` / `%str`
protocol hooks (mirroring Python's `__repr__`/`__str__`): `write` prefers a
`%repr` method returning a string; `display` prefers `%str`, falling back to
`write`. The `%` marks them as runtime-invoked hooks, like `%init` (the
initialize hook that runs after every construction) and `%missing` (below).

```x
(def-class Vec2 () x y
  (method %repr (self) (Str8 str "<" (self x) "," (self y) ">")))
(write (new Vec2 x 1 y 2))
; <1,2>
```

---

### How it works

The system defines two runtime types via `make-type`, with **operative `call`
handlers**: when you write `(obj name args…)` the handler receives the instance,
`name` **unevaluated** (a literal selector, no quote needed — like `def`), and
the raw argument forms, which evaluate once in the caller's environment. This is
the dispatch hook described in the [Type System](type-system.md) guide — the
object system is its richest example.

An **instance** (`%object`) stores `(class . member-box)` in its first slot,
where `member-box` is a one-cell mutable box holding the member alist; a member
write mutates its entry **in place** (no copying, and field order stays
construction order). A **class** (`%class`) is a callable object whose first
slot is the cold, authoritative descriptor alist — `name`, `fields`, `methods`,
`parent`, `s-methods`, the visibility alists, and a `statics` box — the single
source of truth that `(help)` and introspection read.

Dispatch does not walk that alist per call. Each class lazily builds a **hot
record** in its second slot: flat, chain-merged instance and static tables
(most-derived wins; a method beats a same-named member, exactly as dispatch
always resolved) plus cached construction data. One table walk decides method
vs member vs miss; the table self-organizes, promoting a hot selector toward
the front; a method hit is re-driven through `tail-eval`, so the closure runs
on the caller's raw argument forms with no per-argument closure and no `apply`
frame. Runtime mutation — `def-method!`, a static shadow-write, trait mixing —
edits the cold alist and clears every class's hot slot through a class
registry; tables refold on next dispatch, so the hot path itself carries zero
staleness checks. A total miss resolves the `%missing` hook through the same
tables (so it inherits, and cannot recurse into itself) before erroring with
the class and selector named.

Class identity (used by `instance-of?` and inheritance) is checked with `same?`
(pointer identity), not `eq?` (value equality), since value-comparing two
classes would recurse through their method closures.

Two implementation details: x-lang binds a function's *first* parameter to the
function itself (the recursion handle), so `def-class` prepends a hidden slot to
each method's parameter list — the `self` you write lands in the second slot,
which dispatch fills with the receiver. And every method body is wrapped in a
`let` that binds the raw `member` / `set-member!` accessors (instance methods
only) plus `%this-class`, a box holding the method's **defining** class — the
channel `super` derives its parent from and the privacy check reads the
caller's identity from.

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

A bank account with an enforced-protected balance and a savings subclass that
adds interest:

```x
(def-class Account ()
  (protected balance)                        ; enforced: chain methods only
  (method deposit (self amt)
    (self balance (+ (self balance) amt))
    self)
  (method amount (self) (self balance)))

(def-class Savings (extends Account)
  rate
  (method add-interest (self)
    (self deposit (* (self balance) (self rate)))))   ; protected: a chain method may read

(def s (new Savings balance 100 rate 1))   ; construction may initialise it
(s deposit 50)        ; balance -> 150
(s add-interest)      ; deposits 150 * 1 = 150 -> balance 300
(s amount)            ; => 300   the public reader
(s balance)           ; => ERROR: Savings: balance is protected to Account
(instance-of? s Account)   ; => #t
```

`balance` is an ordinary member — methods read and write it with the ordinary
`(self balance)` door — but because it is declared inside a `(protected ...)`
block, only methods on `Account`'s chain may. From the outside, `(s balance)`
is a named error, and `(s amount)` is the interface. Construction is not
member dispatch, so `(new Savings balance 100 ...)` may still initialise it;
declare a default (or set it in `%init`) and omit the key to seal that door
too.

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
| `(private DECL...)` / `(protected DECL...)` | Enforced visibility blocks in a class body |
| `(def-record Name field...)` | Data-carrier class with `with` / `=?` built in |
| `(def-generic g)` / `(on g (SIG...) body...)` | Define a generic / add a method to it |
| `(def-trait T ...)` / `(with T...)` | Define a trait / mix it into a class |
| `(delegates field (sel...))` | Generate forwarders to a field's value |
| `(C def-method! sel fn)` / `(C def-static! sel fn)` | Add a method at runtime |
| `(Block method! C sel [shape] [trailing])` | Give a method a `(names…) body…` call shape |
| `(method %init/%repr/%str/%missing ...)` | Protocol hooks: construction, printing, miss |
| `(method-of Class sel)` | Resolve a static once for hot-loop direct calls |

Every form is in the REPL help system — `(help def-class)`, `(help new)`, … — and
`(help x/type/class)` prints the module overview. See also the
[Type System](type-system.md) for the underlying `make-type` mechanism, and the
[Standard Library](standard-library.md) reference.
