# x-lang Branch Coverage Tool

Flag-bit coverage analysis for x-lang programs.

## Concept

The `x-cov` binary is a modified build of `x` that sets `X_OBJ_FLAG_2` (0x2) on every AST node at eval time. After evaluating the target code, the coverage reporter walks the original AST and reports which `if`/`match`/`cond` branches were never taken.

## Usage

```sh
# Build the coverage binary
make x-cov

# Run coverage on a file
sh tools/cov.sh FILE

# Example
echo '(def abs (fn (x) (if (< x 0) (- 0 x) x)))
(abs 5)' > /tmp/test.x
sh tools/cov.sh /tmp/test.x
# Branch coverage: 1/2
# Uncovered branches:
#   if-then: (- 0 x)
```

## How It Works

1. **Marking**: The `x-cov` binary adds one line to `x_eval()`:
   ```c
   #ifdef X_COV
   if (p_exp != NULL) x_obj_flags(p_exp) |= X_OBJ_FLAG_2;
   #endif
   ```
   Every expression that passes through `eval` gets bit 0x2 set on its flags field.

2. **Tokenization**: The reporter (`cov.x`) reads the source file as a string, tokenizes it with `token-read-string` using the current base (`(%base)`) so symbols are interned correctly.

3. **Evaluation**: An operative loop evaluates each top-level form. Operatives (not fn closures) are used because closures create scoped environments that discard `def` effects after return.

4. **Walking**: The reporter walks the original AST objects (which were modified in-place by step 1) and checks which branch nodes have the coverage flag set.

5. **Reporting**: Unmarked `if` then/else branches and `match`/`cond` clause bodies are reported.

## Flag Bit

`X_OBJ_FLAG_2` (0x2) is a free flag bit on heap objects. The GC mark phase uses `X_OBJ_FLAG_HEAP` (0x80) and the sweep clears only that bit, so coverage flags survive garbage collection.

## x-lang Flag Access

All flag operations are pure x-lang, built on two C primitives (ns `obj` is
de-registered: fetch with `(prim-ref (lit obj) (lit ->ptr))` or use the Obj class):
- `(Obj ->ptr)` -- returns a raw pointer to any object's base array
- `ptr-ref-word` -- reads `sizeof(long)` bytes from a pointer at an offset

```scheme
(def word-size
  (if (> (ptr->int (int->ptr 4294967296)) 0) 8 4))
(def %flags-offset (* 2 word-size))

(def obj-flags (fn (obj)
  (ptr-ref-word (Obj ->ptr obj) %flags-offset)))
```

## Limitations

- **Interned symbols**: Atoms (symbols, integers) are shared objects. Marking one `x` marks all references to `x`. Coverage tracking is most reliable for compound (pair) branch expressions like `(+ 1 2)`, not bare symbols.
- **No line numbers**: The reporter shows the branch expression, not its source location.
- **Same-binary requirement**: The target code must be evaluated by `x-cov`, not the regular `x` binary.

## Tests

```sh
make test-cov
```
