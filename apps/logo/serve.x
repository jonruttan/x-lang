; serve.x -- Minimal HTTP server for turtle graphics viewer
;
; Serves turtle.html on / and segment JSON on /segments.
; Uses FFI to wrap socket syscalls.
;
; Usage:
;   (import logo/turtle)
;   (import logo/serve)
;   ; ... run Logo commands to populate segments ...
;   (turtle-serve 8080)
;   ; Open http://localhost:8080 in browser

(import x/sys/posix)
; Socket plumbing is homed on the Socket class (#29) -- this app is its
; first consumer; the Darwin-only constants that used to live here moved
; there and grew their Linux column.
(import x/sys/socket)
; Fetch the ptr/ffi prims from the catalog (ns `ptr`/`ffi` are de-registered, R5).
(def %ptr-call (prim-ref 'ptr 'call))
(def %ptr->str (prim-ref 'ptr '->str))
(def %ptr-set! (prim-ref 'ptr 'set!))
(def %dlopen (prim-ref 'ffi 'dlopen))
(def %dlsym (prim-ref 'ffi 'dlsym))
; Fetch the io plumbing prims from the catalog (ns `io` partly de-registered, R5).
(def %write-to-str (prim-ref 'io 'write-to-str))
; Fetch the char/int casts from the catalog (ns `char`/`int` utility members de-registered, R5).
(def %int->ptr (prim-ref 'int '->ptr))

; libc read for file slurping (socket traffic rides the Socket class).
(def %libc (%dlopen () 1))
(def %resolve (fn (_ name) (%dlsym %libc name)))
(def %c-read     (%resolve "read"))
(def %c-malloc   (%resolve "malloc"))
(def %c-free     (%resolve "free"))

; Convenience: write one byte at offset
(def ptr-set1! (fn (_ ptr offset val) (%ptr-set! ptr offset val 1)))

; ============================================================
; HTTP helpers
; ============================================================

; Extract the request path from an HTTP request string.
; "GET /path HTTP/1.1\r\n..." → "/path"
(def %http-path
  (fn (_ request)
    (if (null? request) "/"
      ; nested let, not def-in-do: this is the tail, so def would leak to global
      (let ((%find-space
             (fn (self i)
               (if (>= i (%str-length request)) 0
                 (if (Char =? (%str-ref request i) #\space) i
                   (self (+ i 1)))))))
        (let ((start (+ (%find-space 0) 1)))
          (let ((end (%find-space start)))
            (if (>= start end) "/"
              (%substring request start end))))))))

; Build an HTTP response string.
(def %http-response
  (fn (_ status content-type body)
    (Str append "HTTP/1.1 " status "\r\n"
         "Content-Type: " content-type "\r\n"
         "Content-Length: " (%number->str (%str-length body)) "\r\n"
         "Access-Control-Allow-Origin: *\r\n"
         "Connection: close\r\n"
         "\r\n"
         body)))

; ============================================================
; File reading
; ============================================================

(def %slurp-chunk 1048576)  ; 1MB chunks

(def %slurp
  (fn (_ path)
    (def fd (Sys open-read path))
    (if (< fd 0) ""
      ; let, not def-in-do: this is the tail (def would leak to global)
      (let ((%read-all
             (fn (self acc)
               (def buf (%int->ptr (%ptr-call %c-malloc %slurp-chunk)))
               ; %sys-fold (x/sys/posix): Linux zero-extends read's -1
               (def n (%sys-fold (%ptr-call %c-read fd buf (- %slurp-chunk 1))))
               (if (<= n 0)
                 (do (%ptr-call %c-free buf) acc)
                 (do
                   (ptr-set1! buf n 0)
                   (let ((chunk (%ptr->str buf)))
                     (%ptr-call %c-free buf)
                     (self (Str append acc chunk))))))))
        (def content (%read-all ""))
        (Sys close fd)
        content))))

; ============================================================
; Bytecode file — flat JSON array entries, one per line
; ============================================================

(def %bc-path "/tmp/turtle.bc")
(def %bc-fd -1)
(def %fstr (fn (_ v) (%write-to-str v)))

(def %bc-open
  (fn ()
    (if (>= %bc-fd 0) ()
      (set! %bc-fd (Sys open-append %bc-path)))))

; Append one bytecode entry to the file
; 0-arg: writes "OP" + comma + newline
; 1-arg: writes "OP",val + comma + newline
; 2-arg: writes "OP",a,b + comma + newline
(def %bc-append
  (fn (_ . args)
    (%bc-open)
    (def op (first args))
    (def rest-args (rest args))
    (Sys fd-write %bc-fd
      (if (null? rest-args)
        (Str append "\"" op "\",\n")
        (if (null? (rest rest-args))
          (Str append "\"" op "\"," (%fstr (first rest-args)) ",\n")
          (Str append "\"" op "\"," (%fstr (first rest-args))
               "," (%fstr (first (rest rest-args))) ",\n"))))))

; Clear bytecode file
(def %bc-clear
  (fn ()
    (if (>= %bc-fd 0) (Sys close %bc-fd))
    (def fd (Sys open-write %bc-path))
    (if (>= fd 0) (Sys close fd))
    (set! %bc-fd (Sys open-append %bc-path))))

; Read bytecode file and wrap as JSON array
(def %bc-json
  (fn ()
    (def content (%slurp %bc-path))
    (if (str=? content "") "[]"
      (Str append "[" (%substring content 0 (- (%str-length content) 2)) "]"))))

; Write initial empty bytecode file
(def %bc-write
  (fn ()
    (def fd (Sys open-write %bc-path))
    (if (>= fd 0) (Sys close fd))))

; ============================================================
; Server
; ============================================================

(def turtle-serve
  (fn (_ port)
    ; Read the HTML template
    (def html-template (%slurp "apps/logo/viewer.html"))
    (if (str=? html-template "")
      (Err raise 'io "Could not read turtle.html" ()))
    ; Inject the endpoint script before </body>
    (def html-page
      (Str append "<script>window.TURTLE_ENDPOINT='/bc';</script>\n"
           html-template))
    ; Create server socket
    (def server-fd (Socket tcp-listen port))
    (display "Turtle server listening on http://localhost:")
    (display port) (newline)
    (display "Press Ctrl+C to stop.\n")
    ; Accept loop
    (def %serve-loop
      (fn (self)
        (def client-fd (guard (_ -1) (Socket accept server-fd)))
        (if (< client-fd 0) (self)  ; Accept failed, retry
          (do
            (guard (err
                (display "Request error: ") (display err) (newline))
              ; Read request
              (def request (Socket recv client-fd 4096))
              (def path (%http-path request))
              ; Dispatch
              (def response
                (if (str=? path "/bc")
                  (%http-response "200 OK" "application/json" (%bc-json))
                  (if (str=? path "/")
                    (%http-response "200 OK" "text/html; charset=utf-8" html-page)
                    (%http-response "404 Not Found" "text/plain" "Not found"))))
              ; Send response
              (Socket send client-fd response))
            ; Close client connection
            (Socket close client-fd)
            (self)))))
    (%serve-loop)))

(provide logo/serve turtle-serve %bc-write)
