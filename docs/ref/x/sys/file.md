[← Index](../../index.md)

# x/sys/file

File I/O via POSIX syscalls with symbolic mode flags.

### `file-modes`

Alist of symbolic file open mode flags to numeric O_* values.

### `stat-flags`

Alist of stat mode flags to numeric S_* values.

### `fopen`

Open a file, returning a file descriptor.

**Returns:** `INTEGER` — File descriptor, or negative on error

### `fclose`

Close a file descriptor.

**Returns:** `INTEGER` — 0 on success, negative on error

### `fread`

Read bytes from a file descriptor into a buffer.

**Returns:** `INTEGER` — Bytes read, 0 at EOF, negative on error

### `fwrite`

Write bytes from a buffer to a file descriptor.

**Returns:** `INTEGER` — Bytes written, or negative on error

### `fgetc`

Read a single character from a file descriptor.

**Returns:** `CHAR` — Character read, or -1 at EOF

