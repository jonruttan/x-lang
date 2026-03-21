## x86_64 syscall-id

### read is 0

```scheme
(syscall-id (lit read))
```
---
    0

### write is 1

```scheme
(syscall-id (lit write))
```
---
    1

### open is 2

```scheme
(syscall-id (lit open))
```
---
    2

### close is 3

```scheme
(syscall-id (lit close))
```
---
    3

### fork is 57

```scheme
(syscall-id (lit fork))
```
---
    57

### execve is 59

```scheme
(syscall-id (lit execve))
```
---
    59

### exit is 60

```scheme
(syscall-id (lit exit))
```
---
    60

### socket is 41

```scheme
(syscall-id (lit socket))
```
---
    41

### connect is 42

```scheme
(syscall-id (lit connect))
```
---
    42

### bind is 49

```scheme
(syscall-id (lit bind))
```
---
    49

### listen is 50

```scheme
(syscall-id (lit listen))
```
---
    50

### unknown returns -1

```scheme
(syscall-id (lit nonexistent))
```
---
    -1

## i386 syscall fallback

### waitpid falls back to i386 table

```scheme
(syscall-id (lit waitpid))
```
---
    7

### nice falls back to i386 table

```scheme
(syscall-id (lit nice))
```
---
    34

### signal falls back to i386 table

```scheme
(syscall-id (lit signal))
```
---
    48
