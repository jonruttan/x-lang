[← Index](../../index.md)

# x/tool/compile

Native code compiler: JIT assembler (default) with C compiler fallback.

> Default compile uses JIT assembler. compile-c falls back to C compiler. compile-asm is the pure JIT path.

### `compile-emitters`

### `compile-add-emitter!`

Register a new C code emitter for a form. The handler receives the argument list.

**Parameters:**

- **op** : `SYMBOL` — Operator symbol to handle
- **handler** : `CALLABLE` — Emitter function: (fn (_ args) ...)

**Returns:** `LIST` — Updated emitter alist

### `compile-with-writers`

Push C code-generation write handlers, call thunk, pop handlers. Use for custom C generation.

**Parameters:**

- **thunk** : `CALLABLE` — Zero-arg function to call with C emitters active

**Returns:** `ANY` — Result of calling thunk

## Pipeline stages

### `compile-to-c`

Generate C source code from an (fn ...) expression.

**Parameters:**

- **expr** : `LIST` — A (fn (_ params...) body) expression

**Returns:** `STRING` — Generated C source code

### `compile-write`

Write a string to a file. Returns the path.

**Parameters:**

- **path** : `STRING` — Output file path
- **source** : `STRING` — Content to write

**Returns:** `STRING` — The path written to

### `compile-cc`

Invoke the C compiler on a source file to produce a shared library.

**Parameters:**

- **src-path** : `STRING` — C source file
- **lib-path** : `STRING` — Output shared library path

### `compile-load`

Load a compiled shared library and return fn_0 as a callable primitive.

**Parameters:**

- **lib-path** : `STRING` — Path to shared library

**Returns:** `PRIM` — Native function

### `compile-cc-flags`

Compiler flags for the current platform.

**Returns:** `LIST` — Platform-specific cc flags

### `compile-ext`

Shared library file extension for the current platform.

**Returns:** `STRING` — .bundle or .so

## Compilation

### `compile-c`

Compile an (fn ...) expression to a native primitive via C compiler. Caches by expression hash.

**Parameters:**

- **expr** : `LIST` — A (fn (_ params...) body) expression

**Returns:** `PRIM` — Compiled native function

### `compile`

Compile an (fn ...) expression to native code. Pure expressions use JIT assembler; fvar expressions use C compiler with persistent caching.

**Parameters:**

- **expr** : `LIST` — A (fn (_ params...) body) expression

**Returns:** `PRIM` — Compiled native function

### `compile-batch`

Compile multiple (fn ...) expressions in a single cc invocation.

**Returns:** `LIST` — List of compiled native primitives

