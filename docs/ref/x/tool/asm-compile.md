[← Index](../../index.md)

# x/tool/asm-compile

JIT compiler: x-lang to native code via assembler.

### `compile-asm`

JIT compile an x-lang (fn ...) expression to a native prim.
   Accepts optional fvar alist for free variable support.
   The compiled function works with map, fold, closures, etc.

**Returns:** `CALLABLE` — X-lang callable prim

