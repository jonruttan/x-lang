
== x86_64 syscall-id

-- read is 0
(syscall-id (quote read))
---
0

-- write is 1
(syscall-id (quote write))
---
1

-- open is 2
(syscall-id (quote open))
---
2

-- close is 3
(syscall-id (quote close))
---
3

-- fork is 57
(syscall-id (quote fork))
---
57

-- execve is 59
(syscall-id (quote execve))
---
59

-- exit is 60
(syscall-id (quote exit))
---
60

-- socket is 41
(syscall-id (quote socket))
---
41

-- connect is 42
(syscall-id (quote connect))
---
42

-- bind is 49
(syscall-id (quote bind))
---
49

-- listen is 50
(syscall-id (quote listen))
---
50

-- unknown returns -1
(syscall-id (quote nonexistent))
---
-1

== i386 syscall fallback

-- waitpid falls back to i386 table
(syscall-id (quote waitpid))
---
7

-- nice falls back to i386 table
(syscall-id (quote nice))
---
34

-- signal falls back to i386 table
(syscall-id (quote signal))
---
48
