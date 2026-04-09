; serve.x -- Minimal HTTP server for turtle graphics viewer
;
; Serves turtle.html on / and segment JSON on /segments.
; Uses FFI to wrap socket syscalls.
;
; Usage:
;   (import x/logo/turtle)
;   (import x/logo/serve)
;   ; ... run Logo commands to populate segments ...
;   (turtle-serve 8080)
;   ; Open http://localhost:8080 in browser

(import x/sys/posix)

; ============================================================
; Resolve libc socket functions
; ============================================================

(def %libc (dlopen () 1))
(def %resolve (fn (_ name) (dlsym %libc name)))

(def %c-socket   (%resolve "socket"))
(def %c-bind     (%resolve "bind"))
(def %c-listen   (%resolve "listen"))
(def %c-accept   (%resolve "accept"))
(def %c-read     (%resolve "read"))
(def %c-write    (%resolve "write"))
(def %c-close    (%resolve "close"))
(def %c-setsockopt (%resolve "setsockopt"))
(def %c-malloc   (%resolve "malloc"))
(def %c-free     (%resolve "free"))
(def %c-memset   (%resolve "memset"))

; Convenience: write one byte at offset
(def ptr-set1! (fn (_ ptr offset val) (ptr-set! ptr offset val 1)))

; Platform constants (macOS / Darwin)
(def %AF_INET 2)
(def %SOCK_STREAM 1)
(def %SOL_SOCKET 65535)
(def %SO_REUSEADDR 4)

; ============================================================
; Socket helpers
; ============================================================

; Allocate and fill a sockaddr_in struct (16 bytes on macOS)
; Returns a ptr that must be freed after bind.
(def %make-sockaddr-in
  (fn (_ port)
    (def addr (int->ptr (ptr-call %c-malloc 16)))
    (ptr-call %c-memset addr 0 16)
    (ptr-set1! addr 0 16)               ; sin_len (macOS)
    (ptr-set1! addr 1 %AF_INET)         ; sin_family
    (ptr-set1! addr 2 (/ port 256))     ; sin_port high byte (network order)
    (ptr-set1! addr 3 (% port 256))     ; sin_port low byte
    ; sin_addr = INADDR_ANY (0) — already zeroed by memset
    addr))

; Create a TCP server socket, bind, listen. Returns the fd.
(def %make-server-socket
  (fn (_ port)
    (def fd (ptr-call %c-socket %AF_INET %SOCK_STREAM 0))
    (if (< fd 0) (error "socket() failed"))
    ; Set SO_REUSEADDR
    (def optval (int->ptr (ptr-call %c-malloc 4)))
    (ptr-set1! optval 0 1) (ptr-set1! optval 1 0)
    (ptr-set1! optval 2 0) (ptr-set1! optval 3 0)
    (ptr-call %c-setsockopt fd %SOL_SOCKET %SO_REUSEADDR optval 4)
    (ptr-call %c-free optval)
    ; Bind
    (def addr (%make-sockaddr-in port))
    (def result (ptr-call %c-bind fd addr 16))
    (ptr-call %c-free addr)
    (if (< result 0) (error "bind() failed"))
    ; Listen
    (if (< (ptr-call %c-listen fd 5) 0) (error "listen() failed"))
    fd))

; Read up to n bytes from fd into a new string.
(def %fd-read-string
  (fn (_ fd maxlen)
    (def buf (int->ptr (ptr-call %c-malloc (+ maxlen 1))))
    (def n (ptr-call %c-read fd buf maxlen))
    (if (<= n 0)
      (do (ptr-call %c-free buf) ())
      (do
        (ptr-set1! buf n 0)
        (def s (ptr->str buf))
        (ptr-call %c-free buf)
        s))))

; Write a string to fd.
(def %fd-write-all
  (fn (_ fd s)
    (ptr-call %c-write fd s (str-length s))))

; ============================================================
; HTTP helpers
; ============================================================

; Extract the request path from an HTTP request string.
; "GET /path HTTP/1.1\r\n..." → "/path"
(def %http-path
  (fn (_ request)
    (if (null? request) "/"
      (do
        ; Find space after method
        (def %find-space
          (fn (self i)
            (if (>= i (str-length request)) 0
              (if (char=? (request i) #\space) i
                (self (+ i 1))))))
        (def start (+ (%find-space 0) 1))
        ; Find space before HTTP version
        (def end (%find-space start))
        (if (>= start end) "/"
          (substring request start end))))))

; Build an HTTP response string.
(def %http-response
  (fn (_ status content-type body)
    (str "HTTP/1.1 " status "\r\n"
         "Content-Type: " content-type "\r\n"
         "Content-Length: " (number->str (str-length body)) "\r\n"
         "Access-Control-Allow-Origin: *\r\n"
         "Connection: close\r\n"
         "\r\n"
         body)))

; ============================================================
; File reading
; ============================================================

(def %slurp
  (fn (_ path)
    (def fd (sh-open-read path))
    (if (< fd 0) (error (str "Cannot open: " path))
      (do
        (def buf (int->ptr (ptr-call %c-malloc 131072)))
        (def n (ptr-call %c-read fd buf 131071))
        (sh-close fd)
        (if (<= n 0)
          (do (ptr-call %c-free buf) "")
          (do
            (ptr-set1! buf n 0)
            (def content (ptr->str buf))
            (ptr-call %c-free buf)
            content))))))

; ============================================================
; Segment JSON output to string
; ============================================================

; Segments file path — shared between parent (writer) and server (reader)
(def %segments-path "/tmp/turtle-segments.json")

; Read segments from file (server child reads parent's updates)
(def %segments-json
  (fn ()
    (def content (%slurp %segments-path))
    (if (str=? content "") "[]" content)))

; Write current segments to file
(def %segments-write
  (fn ()
    (def fd (sh-open-write %segments-path))
    (if (< fd 0) ()
      (do
        (fd-write fd (turtle-json-str))
        (sh-close fd)))))

; ============================================================
; Server
; ============================================================

(def turtle-serve
  (fn (_ port)
    ; Read the HTML template
    (def html-template (%slurp "turtle.html"))
    (if (str=? html-template "")
      (error "Could not read turtle.html"))
    ; Inject the endpoint script before </body>
    (def html-page
      (str "<script>window.TURTLE_ENDPOINT='/segments';</script>\n"
           html-template))
    ; Create server socket
    (def server-fd (%make-server-socket port))
    (display "Turtle server listening on http://localhost:")
    (display port) (newline)
    (display "Press Ctrl+C to stop.\n")
    ; Accept loop
    (def %serve-loop
      (fn (self)
        (def client-fd (ptr-call %c-accept server-fd 0 0))
        (if (< client-fd 0) (self)  ; Accept failed, retry
          (do
            (guard (err
                (display "Request error: ") (display err) (newline))
              ; Read request
              (def request (%fd-read-string client-fd 4096))
              (def path (%http-path request))
              ; Dispatch
              (def response
                (if (str=? path "/segments")
                  (%http-response "200 OK" "application/json" (%segments-json))
                  (if (str=? path "/")
                    (%http-response "200 OK" "text/html; charset=utf-8" html-page)
                    (%http-response "404 Not Found" "text/plain" "Not found"))))
              ; Send response
              (%fd-write-all client-fd response))
            ; Close client connection
            (ptr-call %c-close client-fd)
            (self)))))
    (%serve-loop)))

(provide x/logo/serve turtle-serve %segments-write)
