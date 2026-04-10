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

(def %slurp-chunk 1048576)  ; 1MB chunks

(def %slurp
  (fn (_ path)
    (def fd (sh-open-read path))
    (if (< fd 0) ""
      (do
        ; Read in chunks, accumulate strings
        (def %read-all
          (fn (self acc)
            (def buf (int->ptr (ptr-call %c-malloc %slurp-chunk)))
            (def n (ptr-call %c-read fd buf (- %slurp-chunk 1)))
            (if (<= n 0)
              (do (ptr-call %c-free buf) acc)
              (do
                (ptr-set1! buf n 0)
                (def chunk (ptr->str buf))
                (ptr-call %c-free buf)
                (self (str acc chunk))))))
        (def content (%read-all ""))
        (sh-close fd)
        content))))

; ============================================================
; Segment JSON output to string
; ============================================================

; Segments file — newline-delimited JSON (one segment per line).
; Parent appends lines, server child reads and wraps in [...].
(def %segments-path "/tmp/turtle-segments.ndjson")

; Format one segment as a JSON line — uses float->str directly (no write buffer overhead)
(def %fstr (fn (_ v) (float->str (first v))))

(def %segment-json-line
  (fn (_ seg)
    (def s1 (rest seg))
    (def s2 (rest s1))
    (def s3 (rest s2))
    (def s4 (rest s3))
    (def s5 (rest s4))
    (str "{\"x1\":" (%fstr (first seg))
         ",\"y1\":" (%fstr (first s1))
         ",\"x2\":" (%fstr (first s2))
         ",\"y2\":" (%fstr (first s3))
         ",\"pen\":" (if (first s4) "true" "false")
         ",\"heading\":" (%fstr (first s5)) "},\n")))

; Keep the file open — one write per segment, no open/close overhead
(def %segments-fd -1)

(def %segments-open
  (fn ()
    (if (>= %segments-fd 0) () ; already open
      (set! %segments-fd (sh-open-append %segments-path)))))

; Append one segment line (single write syscall)
(def %segment-append
  (fn (_ seg)
    (%segments-open)
    (fd-write %segments-fd (%segment-json-line seg))))

; Clear the segments file (close, truncate, reopen)
(def %segments-clear
  (fn ()
    (if (>= %segments-fd 0) (sh-close %segments-fd))
    (def fd (sh-open-write %segments-path))
    (if (>= fd 0) (sh-close fd))
    (set! %segments-fd (sh-open-append %segments-path))))

; Read segments file and wrap as JSON array for the viewer
(def %segments-json
  (fn ()
    (def content (%slurp %segments-path))
    (if (str=? content "") "[]"
      (str "[" (substring content 0 (- (str-length content) 2)) "]"))))

; Write all current segments (full rewrite — used for initial state only)
(def %segments-write
  (fn ()
    (def fd (sh-open-write %segments-path))
    (if (< fd 0) ()
      (do
        (def segs (reverse %turtle-segments))
        (def %wr
          (fn (self s)
            (if (null? s) ()
              (do (fd-write fd (%segment-json-line (first s)))
                  (self (rest s))))))
        (%wr segs)
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
