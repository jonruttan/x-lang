[← Index](../../index.md)

# x/sys/posix

POSIX system call wrappers via FFI.

> Provides fork, exec, pipe, dup2, wait, open, close, chdir, getenv, setenv.

## Process Control

### `sh-fork`

Fork the current process.

**Returns:** `INTEGER` — PID of child in parent, 0 in child, -1 on error

### `sh-getpid`

Return the current process ID.

**Returns:** `INTEGER` — Process ID

### `sh-exit`

Terminate the process with the given exit status.

**Parameters:**

- **status** : `INTEGER` — Exit status code

### `sh-wait`

Wait for a child process and return its exit status.

**Parameters:**

- **pid** : `INTEGER` — Process ID to wait for

**Returns:** `INTEGER` — Exit status of the child process

### `sh-exec`

Replace the current process with the named program. Does not return on success.

**Parameters:**

- **name** : `STRING` — Program name
- **args** : `LIST` — List of argument strings

## File Descriptors

### `sh-close`

Close a file descriptor.

**Parameters:**

- **fd** : `INTEGER` — File descriptor to close

**Returns:** `INTEGER` — 0 on success, -1 on error

### `sh-dup2`

Duplicate a file descriptor onto another.

**Parameters:**

- **old** : `INTEGER` — Source file descriptor
- **new** : `INTEGER` — Target file descriptor

**Returns:** `INTEGER` — New file descriptor, or -1 on error

### `sh-pipe`

Create a pipe and return a pair of file descriptors.

**Returns:** `PAIR` — Pair of (read-fd . write-fd)

## File I/O

### `sh-open-read`

Open a file for reading.

**Parameters:**

- **path** : `STRING` — File path to open

**Returns:** `INTEGER` — File descriptor, or -1 on error

### `sh-open-write`

Open a file for writing, creating or truncating it.

**Parameters:**

- **path** : `STRING` — File path to open

**Returns:** `INTEGER` — File descriptor, or -1 on error

### `sh-open-append`

Open a file for appending, creating it if necessary.

**Parameters:**

- **path** : `STRING` — File path to open

**Returns:** `INTEGER` — File descriptor, or -1 on error

## Environment

### `sh-chdir`

Change the current working directory.

**Parameters:**

- **path** : `STRING` — Directory path

**Returns:** `INTEGER` — 0 on success, -1 on error

### `sh-setenv`

Set an environment variable, overwriting any existing value.

**Parameters:**

- **name** : `STRING` — Variable name
- **val** : `STRING` — Variable value

**Returns:** `INTEGER` — 0 on success, -1 on error

### `sh-getenv`

Get the value of an environment variable.

**Parameters:**

- **name** : `STRING` — Variable name

**Returns:** `STRING` — Variable value, or nil if not set

## General utilities

### `fd-write`

Write a string to a file descriptor.

**Parameters:**

- **fd** : `NUMBER` — File descriptor
- **s** : `STRING` — String to write

**Returns:** `NUMBER` — Bytes written

### `file-exists?`

Check if a file exists (via access with F_OK=0).

**Parameters:**

- **path** : `STRING` — File path to check

**Returns:** `BOOLEAN` — True if file exists

