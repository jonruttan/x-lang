# 02-syscall.spec.sh -- Syscall table lookup tests

describe 'x86_64 syscall-id'
  it 'read is 0' \
    '(syscall-id (quote read))' '0'
  it 'write is 1' \
    '(syscall-id (quote write))' '1'
  it 'open is 2' \
    '(syscall-id (quote open))' '2'
  it 'close is 3' \
    '(syscall-id (quote close))' '3'
  it 'fork is 57' \
    '(syscall-id (quote fork))' '57'
  it 'execve is 59' \
    '(syscall-id (quote execve))' '59'
  it 'exit is 60' \
    '(syscall-id (quote exit))' '60'
  it 'socket is 41' \
    '(syscall-id (quote socket))' '41'
  it 'connect is 42' \
    '(syscall-id (quote connect))' '42'
  it 'bind is 49' \
    '(syscall-id (quote bind))' '49'
  it 'listen is 50' \
    '(syscall-id (quote listen))' '50'
  it 'unknown returns -1' \
    '(syscall-id (quote nonexistent))' '-1'

describe 'i386 syscall fallback'
  it 'waitpid falls back to i386 table' \
    '(syscall-id (quote waitpid))' '7'
  it 'nice falls back to i386 table' \
    '(syscall-id (quote nice))' '34'
  it 'signal falls back to i386 table' \
    '(syscall-id (quote signal))' '48'
