; nul-escape.x -- stdin to stdout, every zero byte as the literal text
; `<<NUL>>`.  The spec runner's escaper; see the NUL_FILTER note in
; tests/spec-runner.sh for why one is needed at all (awk is a C-string
; language, and a NUL terminates the record it reads).
;
;   printf 'a\000b' | sh x.sh --no-pin -q -f tools/dev/nul-escape.x
;   a<<NUL>>b
;
; READS FD 3, NOT FD 0.  The wrapper feeds the engine its program on stdin and
; saves the caller's own stdin on fd 3 (`exec 3<&0` in x.sh), so a filter
; written in x reads there.  Reading fd 0 instead consumes the rest of the
; program text and evaluation stops with no diagnostic at all.
;
; Byte counts are carried explicitly end to end: the read says how many bytes
; landed, the write is told how many to send, and a run is cut out with
; byte-sub.  Nothing here asks a NUL-carrying string for its length, which is
; the one operation that would truncate.

(import x/sys/file)

(def-class NulEscape ()
  (static
    (%make (prim-ref (lit str) (lit make)))
    (%ref  (prim-ref (lit str) (lit byte-ref)))
    (%sub  (prim-ref (lit str) (lit byte-sub)))
    ; fd 3 is the caller's stdin; see the note above
    (%in 3)
    (%out 1)
    (%size 8192)

    ; The bytes of BUF in [START, END) -- a stretch with no zero byte in it,
    ; so cutting it out and measuring it are both safe.
    (method %run! (self buf start end)
      (if (> end start)
        (File write (NulEscape %out)
          ((NulEscape %sub) buf start (- end start))
          (- end start))
        ()))

    ; One chunk: the runs between the zero bytes, and the escape in place of
    ; each one.
    (method %chunk! (self buf n)
      (let ((go (fn (go i start)
                  (if (>= i n) (NulEscape %run! buf start n)
                    (if (= ((NulEscape %ref) buf i) 0)
                      (do (NulEscape %run! buf start i)
                          (File write (NulEscape %out) "<<NUL>>" 7)
                          (go (+ i 1) (+ i 1)))
                      (go (+ i 1) start))))))
        (go 0 0)))

    ; A run meeting the end of a chunk is written in two pieces rather than
    ; joined: the bytes that reach the output are the same either way, and
    ; nothing has to be carried over.
    (method %loop! (self buf)
      (let ((n (File read (NulEscape %in) buf (NulEscape %size))))
        (if (<= n 0) 0
          (do (NulEscape %chunk! buf n) (NulEscape %loop! buf)))))

    (method %filter! (self)
      (NulEscape %loop! ((NulEscape %make) (NulEscape %size))))))

(NulEscape %filter!)
