; net/http.x -- Http: a plain-http/1.1 client over the Socket class (#374).
;
; The ruled strategy (issue comment, 2026-08-20): pure x over
; (Socket tcp-connect) -- request line + headers out, full response
; parsing back: status line, headers, and the body under EITHER framing
; (Content-Length, or Transfer-Encoding: chunked -- decoded here).
; Connection: close on every request; no keep-alive. Redirects
; auto-follow (cap 10, RFC method rules, (redirects . 0) opts out).
;
; https rides the Tls class (#412's amendment to the #374 ruling:
; libssl binds over the dlopen FFI -- the variadic blocker was libcurl's;
; verification + SNI + hostname checks on by default). Hostnames resolve
; through (Socket resolve) at request time; the Host header carries the
; NAME (virtual hosting), the connect takes the quad.
;
; net/ is the network-PROTOCOL profile: it carries messages over sys/socket's
; transport, the way codec/ carries data over strings and bytes.
;
; Bodies ride BYTE LISTS (the lossless carrier: recv's string door
; truncates at NUL; this client reads through Socket recv-bytes) --
; (bytes->str body) for textual responses. Request bodies are strings
; (text protocols; NUL-free by the string profile's nature).
;
; One reader parses every response: an HttpStream reads the head, then
; hands the body out a piece at a time as the transport delivers it.
; (Http open) returns the stream, for bodies too large to hold; request
; drains it into one byte list.
;
; Zero top-level %-globals (new-file budget 0).

(module x/net/http)
(import x/type/class)
(import x/core/list)
(import x/type/assoc)
(import x/sys/socket)
(import x/net/tls)
(import x/codec/base64)   ; basic-auth's credential encoding (#412)
(import x/type/record)

; A response being read: its transport (a Tls session, a socket fd, or a
; list of runs read in turn), the bytes read but not yet handed out -- buf's
; bytes from off to end -- and the body's framing state: mode is none, eof,
; length (left bytes to go), or a chunked step: size, data (left bytes to
; go), tail, trailer. head, status and headers are filled from the head.
;
; Bytes travel as RUNS, (STRING . COUNT): a string buffer and how many of its
; bytes count, NUL bytes included. A run costs a few objects whatever its
; size, where a byte list costs a pair a byte and every walk of it more.
(def-record HttpStream (tls ()) (fd ()) (pieces ()) (buf ()) (off 0) (end 0)
                       (mode ()) (left 0) (head ()) (status 0) (headers ()))

(def-class Http ()
  (doc "An http/1.1 client over Socket, https over Tls: (Http get url), (Http post url body), (Http request method url headers body) -> ((status . INT) (headers . ALIST) (body . BYTE-LIST)); (Http open method url headers body) -> a stream whose body (Http read s n) hands out a piece at a time. Header names come back lowercased."
    (example "(rest (Assoc find 'status (Http %parse-response (list 72 84 84 80 47 49 46 49 32 50 48 48 32 75 13 10 13 10))))" "200")
    (see get) (see request))
  (static
    ; --- url -> ((host . H) (port . P) (path . S)); strict per #61 ---
    (method %parse-url (self (param url STRING "http://HOST[:PORT][/PATH...]"))
      (doc "Split an http or https url; the path defaults to \"/\", the port to the scheme's (80/443); a missing scheme raises a label 'value."
        (returns ALIST "((host . H) (port . P) (path . S) (tls . BOOL))"))
      (def tls? (Str8 starts? "https://" url))
      (unless (if tls? #t (Str8 starts? "http://" url))
        (Err raise (lit value) "Http: not an http(s):// url" url))
      (def rest-part (Str8 sub (if tls? 8 7) (Str8 length url) url))
      (def slash (Str8 index-of "/" rest-part))
      (def hostport (if (null? slash) rest-part (Str8 sub 0 slash rest-part)))
      (def path (if (null? slash) "/"
                  (Str8 sub slash (Str8 length rest-part) rest-part)))
      (def colon (Str8 index-of ":" hostport))
      (def host (if (null? colon) hostport (Str8 sub 0 colon hostport)))
      (def port (if (null? colon) (if tls? 443 80)
                  (let ((p (%str->number (Str8 sub (+ colon 1) (Str8 length hostport) hostport))))
                    (if (null? p)
                      (Err raise (lit value) "Http: bad port" url)
                      p))))
      (when (str=? host "")
        (Err raise (lit value) "Http: empty host" url))
      (list (pair (lit host) host) (pair (lit port) port) (pair (lit path) path)
            (pair (lit tls) tls?)))

    ; --- request text (string; the send side is textual by nature) ---
    (method %build-request (self (param method STRING "Verb, e.g. \"GET\"")
                                 (param u ALIST "%parse-url's result")
                                 (param headers ALIST "(name . value) strings, appended verbatim")
                                 (param body ANY "Body string, or nil"))
      (doc "Render the request: verb + path, Host (with the port when it is not the scheme's own, RFC 9110 7.2), Connection: close, Content-Length when a body rides, the caller's headers, CRLF framing."
        (returns STRING "The full request text"))
      (def port (rest (Assoc find (lit port) u)))
      (def head
        (Str8 append method " " (rest (Assoc find (lit path) u)) " HTTP/1.1\r\n"
                     "Host: " (rest (Assoc find (lit host) u))
                     (if (= port (if (rest (Assoc find (lit tls) u)) 443 80)) ""
                       (Str8 append ":" (%number->str port)))
                     "\r\n"
                     "Connection: close\r\n"))
      (def with-len
        (if (null? body) head
          (Str8 append head "Content-Length: " (%number->str (Str8 length body)) "\r\n")))
      (def with-user
        (List fold (fn (_ acc h) (Str8 append acc (first h) ": " (rest h) "\r\n"))
          with-len headers))
      (Str8 append with-user "\r\n" (if (null? body) "" body)))

    ; --- response parsing (byte-level; spec-testable without a socket) ---
    ; hex chunk-size parse over bytes; -1 marks a non-hex byte
    (method %hex-nibble (self (param c INTEGER "Byte value"))
      (doc "The hex value of one byte, or -1 off-domain."
        (returns INTEGER "0-15, or -1"))
      (match
        ((if (>= c 48) (<= c 57) #f) (- c 48))
        ((if (>= c 97) (<= c 102) #f) (- c 87))
        ((if (>= c 65) (<= c 70) #f) (- c 55))
        (#t -1)))

    ; --- the response stream: one reader for every framing ---
    ; A stream reads runs off its transport and hands the body out a run at
    ; a time, removing the framing as it goes. Every response this class
    ; reads goes through it: open/read on the wire, request draining it,
    ; %parse-response and %dechunk over a byte list.
    (method %run-join (self (param a STRING "The first buffer")
                            (param off INTEGER "Where its bytes start")
                            (param n INTEGER "How many of them")
                            (param b STRING "The second buffer, or nil")
                            (param m INTEGER "How many of its bytes, from its start"))
      (doc "A new run of a's n bytes from off followed by b's first m, copied by libc's memcpy: NUL bytes and all, a few objects whatever the size."
        (returns PAIR "(STRING . n+m)"))
      (def %call (prim-ref (lit ptr) (lit call)))
      (def %make-str (prim-ref (lit str) (lit make)))
      (def %str->ptr (prim-ref (lit str) (lit ->ptr)))
      (def %ptr->int (prim-ref (lit ptr) (lit ->int)))
      (def %int->ptr (prim-ref (lit int) (lit ->ptr)))
      (def memcpy ((prim-ref (lit ffi) (lit dlsym)) ((prim-ref (lit ffi) (lit dlopen)) () 1) "memcpy"))
      (def out (%make-str (if (< (+ n m) 1) 1 (+ n m))))
      (def at (%ptr->int (%str->ptr out)))
      (when (> n 0)
        (%call memcpy (%int->ptr at) (%int->ptr (+ (%ptr->int (%str->ptr a)) off)) n))
      (when (> m 0)
        (%call memcpy (%int->ptr (+ at n)) (%str->ptr b) m))
      (pair out (+ n m)))

    (method %run-copy (self (param buf STRING "A run's buffer")
                            (param off INTEGER "First byte to copy")
                            (param n INTEGER "How many bytes"))
      (doc "A new run of buf's n bytes from off."
        (returns PAIR "(STRING . n)"))
      (Http %run-join buf off n () 0))

    (method %run->bytes (self (param r PAIR "A run, (STRING . COUNT)"))
      (doc "A run's bytes as a byte list, the carrier request and %parse-response answer with."
        (returns LIST "The bytes, 0-255 each"))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (let go ((i (- (rest r) 1)) (acc ()))
        (if (< i 0) acc (go (- i 1) (pair (& (%c->i (%bref (first r) i)) 255) acc)))))

    (method %recv (self (param s OBJECT "An HttpStream"))
      (doc "One read off the stream's transport: the Tls session, the socket, or the next of its pieces."
        (returns ANY "A run, or nil at end of input"))
      (match
        ((not (null? (s tls))) (Tls recv-run (s tls) 65536))
        ((not (null? (s fd))) (Socket recv-run (s fd) 65536))
        ((null? (s pieces)) ())
        (#t (let ((p (first (s pieces))))
              (do (s pieces (rest (s pieces))) p)))))

    (method %fill (self (param s OBJECT "An HttpStream"))
      (doc "Read once more from the transport onto the buffer: the read becomes the buffer when the buffer is used up, and is joined to what is left of it otherwise."
        (returns BOOL "#f at end of input"))
      (def got (Http %recv s))
      (def have (- (s end) (s off)))
      (match
        ((null? got) #f)
        ((= have 0) (do (s buf (first got)) (s off 0) (s end (rest got)) #t))
        (#t
          (let ((joined (Http %run-join (s buf) (s off) have (first got) (rest got))))
            (do (s buf (first joined)) (s off 0) (s end (rest joined)) #t)))))

    (method %line (self (param s OBJECT "An HttpStream"))
      (doc "The next CRLF-terminated line as a string, consumed through the CRLF. An empty line answers \"\"; input that ends before a CRLF answers #f and leaves the partial line buffered."
        (returns ANY "STRING, or #f at end of input"))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (let scan ((i (s off)))
        (match
          ((>= (+ i 1) (s end))
            (if (Http %fill s) (scan (s off)) #f))
          ((if (= (%c->i (%bref (s buf) i)) 13) (= (%c->i (%bref (s buf) (+ i 1))) 10) #f)
            ; a line is short and read as text: a string of its own
            (let ((line (bytes->str (Http %run->bytes (Http %run-copy (s buf) (s off) (- i (s off)))))))
              (do (s off (+ i 2)) line)))
          (#t (scan (+ i 1))))))

    (method %take (self (param s OBJECT "An HttpStream")
                        (param n INTEGER "Most bytes wanted"))
      (doc "Up to n buffered bytes as a run, after one transport read when the buffer is used up. A whole buffer is handed over as it is; part of one is copied."
        (returns ANY "A run, or nil at end of input"))
      (when (= (s off) (s end)) (Http %fill s))
      (def have (- (s end) (s off)))
      (def k (if (< n have) n have))
      (match
        ((= have 0) ())
        ((if (= (s off) 0) (= k have) #f)
          (do (s off (s end)) (pair (s buf) k)))
        (#t
          (let ((r (Http %run-copy (s buf) (s off) k)))
            (do (s off (+ (s off) k)) r)))))

    (method %bad-chunk (self (param what STRING "What was wrong"))
      (doc "Raise a label 'value for malformed chunked framing.")
      (Err raise (lit value) (Str8 append "Http: bad chunked framing: " what) ()))

    (method %chunk-size (self (param line STRING "A chunk-size line, without its CRLF"))
      (doc "The hex size that opens the line; a chunk extension (\";...\") after it is ignored. A line with no leading hex digit raises a label 'value."
        (returns INTEGER "The chunk's size"))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def len (Str8 length line))
      (let go ((i 0) (n 0) (any #f))
        (def v (if (>= i len) -1 (Http %hex-nibble (%c->i (%bref line i)))))
        (match
          ((>= v 0) (go (+ i 1) (+ (* 16 n) v) #t))
          (any n)
          (#t (Http %bad-chunk "missing size")))))

    (method %read-counted (self (param s OBJECT "An HttpStream framed by Content-Length")
                                (param n INTEGER "Most bytes wanted"))
      (doc "The next run of a Content-Length body; the count runs down to nil. Input that ends early ends the body there."
        (returns ANY "A run, or nil at the end of the body"))
      (match
        ((= (s left) 0) (do (s mode (lit none)) ()))
        (#t
          (let ((r (Http %take s (if (< n (s left)) n (s left)))))
            (match
              ((null? r) (do (s mode (lit none)) ()))
              (#t (do (s left (- (s left) (rest r))) r)))))))

    (method %read-chunked (self (param s OBJECT "An HttpStream framed by Transfer-Encoding: chunked")
                                (param n INTEGER "Most bytes wanted"))
      (doc "The next run of a chunked body. The stream's mode walks size (a hex size line), data (that many bytes), tail (the CRLF after them), and trailer (header lines to an empty one) after the zero chunk. Malformed framing raises a label 'value."
        (returns ANY "A run, or nil at the end of the body"))
      (let step ()
        (def m (s mode))
        (match
          ((eq? m (lit size))
            (let ((line (Http %line s)))
              (do (when (eq? line #f) (Http %bad-chunk "unterminated size line"))
                  (let ((size (Http %chunk-size line)))
                    (if (= size 0) (s mode (lit trailer))
                      (do (s left size) (s mode (lit data)))))
                  (step))))
          ((eq? m (lit data))
            (let ((r (Http %take s (if (< n (s left)) n (s left)))))
              (do (when (null? r) (Http %bad-chunk "truncated chunk"))
                  (s left (- (s left) (rest r)))
                  (when (= (s left) 0) (s mode (lit tail)))
                  r)))
          ((eq? m (lit tail))
            (let ((line (Http %line s)))
              (do (when (if (eq? line #f) #t (not (str=? line "")))
                    (Http %bad-chunk "chunk not CRLF-terminated"))
                  (s mode (lit size))
                  (step))))
          (#t
            (let ((line (Http %line s)))
              (if (if (eq? line #f) #t (str=? line ""))
                (do (s mode (lit none)) ())
                (step)))))))

    (method read (self (param s OBJECT "An (Http open) stream")
                       (param n INTEGER "Most bytes wanted"))
      (doc "The body's next piece as a RUN, (STRING . COUNT) -- at most n bytes in a string buffer, NUL bytes included -- with the framing removed: Content-Length counted down, chunked decoded. Pieces come as the peer sends them and cost a few objects each, so a body of any size needs one piece's memory: read until nil, writing each away with (File write fd (first r) (rest r)). A peer that closes early ends the body early -- compare the bytes read with the content-length header where that matters. Malformed chunked framing raises a label 'value."
        (returns ANY "(STRING . COUNT), or nil once the body is done")
        (sample "(let ((s (Http open \"GET\" \"http://127.0.0.1:8080/f\" () ()))) (Http read s 4096))" "(\"...\" . 4096)"))
      (match
        ((eq? (s mode) (lit none)) ())
        ((eq? (s mode) (lit eof)) (Http %take s n))
        ((eq? (s mode) (lit length)) (Http %read-counted s n))
        (#t (Http %read-chunked s n))))

    (method %drain (self (param s OBJECT "An HttpStream"))
      (doc "Read the rest of the body into one byte list."
        (returns LIST "The body's bytes"))
      (let go ((acc ()))
        (let ((r (Http read s 65536)))
          (if (null? r) (List flat-map (fn (_ c) c) (%reverse acc))
            (go (pair (Http %run->bytes r) acc))))))

    (method %start (self (param s OBJECT "An HttpStream at the start of a response")
                         (param no-body BOOL "#t for a HEAD response"))
      (doc "Read the head: the status line, the header lines, and the body's framing from them. HEAD responses carry no body whatever their framing headers say; a Transfer-Encoding naming chunked decodes chunks; a numeric Content-Length counts; anything else reads to the end of input. A response with no blank line after its head raises a label 'value."
        (returns OBJECT "s, positioned at the body"))
      (def %bad (fn (_ what)
        (Err raise (lit value) (Str8 append "Http: bad response: " what) ())))
      (def lines
        (let go ((acc ()))
          (let ((line (Http %line s)))
            (match
              ((eq? line #f) (%bad "no header terminator"))
              ((str=? line "") (%reverse acc))
              (#t (go (pair line acc)))))))
      (when (null? lines) (%bad "empty head"))
      ; "HTTP/1.x NNN reason"
      (def code
        (let ((parts (Str8 split " " (first lines))))
          (match
            ((null? (rest parts)) (%bad "no status code"))
            (#t
              (let ((n (%str->number (first (rest parts)))))
                (if (null? n) (%bad "non-numeric status") n))))))
      (def fields
        (List map
          (fn (_ ln)
            (let ((colon (Str8 index-of ":" ln)))
              (if (null? colon) (pair (Str8 downcase ln) "")
                (pair (Str8 downcase (Str8 sub 0 colon ln))
                      (Str8 trim (Str8 sub (+ colon 1) (Str8 length ln) ln))))))
          (rest lines)))
      (def te (Assoc find "transfer-encoding" fields))
      (def cl (Assoc find "content-length" fields))
      (def size (if (null? cl) () (%str->number (rest cl))))
      (s head lines)
      (s status code)
      (s headers fields)
      (match
        (no-body (s mode (lit none)))
        ((if (pair? te) (Str8 includes? "chunked" (rest te)) #f) (s mode (lit size)))
        ((null? size) (s mode (lit eof)))
        (#t (do (s left size) (s mode (lit length)))))
      s)

    (method %over (self (param pieces LIST "Byte lists, one answered per transport read")
                        (param no-body BOOL "#t for a HEAD response"))
      (doc "A stream over byte-list pieces instead of a connection, its head read: the wire's shape, a piece per read, with no socket."
        (returns OBJECT "An HttpStream positioned at the body"))
      (def runs (List map (fn (_ b) (pair (bytes->str b) (List length b))) pieces))
      (Http %start (Http %over-runs runs) no-body))

    (method %over-runs (self (param pieces LIST "Runs, one answered per transport read"))
      (doc "A fresh stream whose transport is a list of runs."
        (returns OBJECT "An HttpStream"))
      (new HttpStream pieces pieces))

    (method %dechunk (self (param bytes LIST "Chunked-framing body bytes"))
      (doc "Decode Transfer-Encoding: chunked framing: hex-size line, that many bytes, CRLF, repeated to the zero chunk. Malformed framing raises a label 'value."
        (returns LIST "The unframed body bytes"))
      (def pieces (list (pair (bytes->str bytes) (List length bytes))))
      (def mode (lit size))
      (Http %drain (new HttpStream pieces pieces mode mode)))

    (method %parse-response (self (param bytes LIST "The raw response bytes, complete")
                                  . (param no-body BOOL "Truthy for HEAD responses: headers may claim a Content-Length, but no body follows"))
      (doc "Parse a full http response: status from the status line, headers lowercased into an alist, the body unframed (chunked decoded; Content-Length applied; else everything to EOF). HEAD callers pass the no-body flag -- framing headers describe the body a GET would have carried."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST))"))
      (def s (Http %over (list bytes) (if (null? no-body) #f (first no-body))))
      (def body (Http %drain s))
      (list (pair (lit status) (s status))
            (pair (lit headers) (s headers))
            (pair (lit body) body)))

    (method %quad? (self (param host STRING "Host text"))
      (doc "Is this a dotted quad already (digits and dots only)? Names go through (Socket resolve)."
        (returns BOOL "#t for dotted-quad text"))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def n (%blen host))
      (let go ((i 0))
        (match
          ((= i n) (> n 0))
          (#t
            (let ((c (%c->i (%bref host i))))
              (if (or (= c 46) (if (>= c 48) (<= c 57) #f))
                (go (+ i 1))
                #f))))))

    (method url-encode (self (param s STRING "Text to percent-encode"))
      (doc "Percent-encode for urls: unreserved bytes (A-Z a-z 0-9 - _ . ~) pass through, everything else becomes %XX uppercase (#412)."
        (returns STRING "The encoded text")
        (example "(Http url-encode \"a b&c=d\")" "\"a%20b%26c%3Dd\""))
      (def %blen (prim-ref (lit str) (lit byte-len)))
      (def %bref (prim-ref (lit str) (lit byte-ref)))
      (def %c->i (prim-ref (lit char) (lit ->int)))
      (def %hex (fn (_ v) (if (< v 10) (+ 48 v) (+ 55 v))))
      (def %plain? (fn (_ c)
        (or (if (>= c 65) (<= c 90) #f)
            (or (if (>= c 97) (<= c 122) #f)
                (or (if (>= c 48) (<= c 57) #f)
                    (or (= c 45) (or (= c 95) (or (= c 46) (= c 126)))))))))
      (def n (%blen s))
      (bytes->str
        (%reverse
          (let go ((i 0) (acc ()))
            (match
              ((= i n) acc)
              (#t
                (let ((c (%c->i (%bref s i))))
                  (go (+ i 1)
                      (if (%plain? c) (pair c acc)
                        (pair (%hex (& c 15)) (pair (%hex (>> c 4)) (pair 37 acc))))))))))))

    (method with-query (self (param url STRING "Base url (may already carry a query)")
                             (param params ALIST "(name . value) strings, both percent-encoded here"))
      (doc "Append percent-encoded query parameters: ? on a bare url, & on one already carrying a query (#412)."
        (returns STRING "The url with the query appended")
        (example "(Http with-query \"http://h/p\" (list (pair \"q\" \"a b\") (pair \"n\" \"2\")))" "\"http://h/p?q=a%20b&n=2\""))
      (List fold
        (fn (_ acc kv)
          (Str8 append acc
            (if (Str8 includes? "?" acc) "&" "?")
            (Http url-encode (first kv)) "=" (Http url-encode (rest kv))))
        url params))

    (method basic-auth (self (param user STRING "Username")
                             (param pass STRING "Password"))
      (doc "The Authorization header pair for HTTP Basic auth (RFC 7617): add it to any verb's headers -- (Http get url (list (Http basic-auth u p))) or through Rest's trailing headers the same way. Credentials ride base64, NOT encryption: use https urls. On a cross-host redirect the header is stripped automatically (the curl rule)."
        (returns PAIR "(\"Authorization\" . \"Basic ...\")")
        (example "(Http basic-auth \"Aladdin\" \"open sesame\")" "(\"Authorization\" . \"Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==\")"))
      (pair "Authorization"
            (Str8 append "Basic " (Base64 encode (Str8 append user ":" pass)))))

    (method bearer-auth (self (param token STRING "The bearer token"))
      (doc "The Authorization header pair for bearer-token auth (RFC 6750) -- add it to any verb's headers, exactly like basic-auth: (Rest get url (list (Http bearer-auth tok))). Tokens are credentials: use https urls; the cross-host redirect strip covers this header too."
        (returns PAIR "(\"Authorization\" . \"Bearer ...\")")
        (example "(Http bearer-auth \"abc123\")" "(\"Authorization\" . \"Bearer abc123\")"))
      (pair "Authorization" (Str8 append "Bearer " token)))

    (method %sans-auth (self (param headers ALIST "Request headers"))
      (doc "The headers without any Authorization entry (name compared case-insensitively) -- applied when a redirect hops to a DIFFERENT host, so credentials never leak cross-origin (the curl rule)."
        (returns ALIST "The filtered headers"))
      (List reject
        (fn (_ h) (str=? (Str8 downcase (first h)) "authorization"))
        headers))

    ; --- the wire ---
    (method %opt (self (param o ALIST "Options alist")
                       (param key SYMBOL "Option name")
                       (param default ANY "Value when absent"))
      (doc "An option's value: (key . v) gives v, a bare (key) gives #t, absence gives default."
        (returns ANY "The value"))
      (def e (Assoc entry key o))
      (match
        ((null? e) default)
        ((null? (rest e)) #t)
        (#t (rest e))))

    (method %open-once (self (param method STRING "Verb")
                             (param url STRING "http(s)://HOST[:PORT][/PATH]")
                             (param headers ALIST "(name . value) strings; () for none")
                             (param body ANY "Body string, or nil")
                             (param o ALIST "open's options"))
      (doc "One exchange, redirects NOT followed -- the wire step open loops over: connect, send the request, read the head."
        (returns OBJECT "An HttpStream positioned at the body"))
      (def u (Http %parse-url url))
      (def host (rest (Assoc find (lit host) u)))
      (def quad (if (Http %quad? host) host (Socket resolve host)))
      (def port (rest (Assoc find (lit port) u)))
      (def req (Http %build-request method u headers body))
      (def s
        (if (rest (Assoc find (lit tls) u))
          (let ((tls (Tls connect quad port
                       (if (Http %opt o (lit insecure) #f)
                         (list (pair (lit host) host) (list (lit insecure)))
                         (list (pair (lit host) host))))))
            (new HttpStream tls tls))
          (let ((fd (Socket tcp-connect quad port)))
            (new HttpStream fd fd))))
      (guard (e (do (Http close s) (error e)))
        (do (if (null? (s tls)) (Socket send (s fd) req) (Tls send (s tls) req))
            (Http %start s (str=? method "HEAD")))))

    (method open (self (param method STRING "Verb: \"GET\", \"POST\", ...")
                       (param url STRING "http(s)://HOST[:PORT][/PATH]")
                       (param headers ALIST "(name . value) strings; () for none")
                       (param body ANY "Body string, or nil")
                       . (param opts ALIST "Options: (redirects . N) hop cap -- default 10, 0 disables following; (insecure) skips https certificate verification"))
      (doc "Start an http exchange and stop at the body: the stream answers (s status) INTEGER, (s headers) the lowercased alist, (s head) the head's lines as sent (status line first); (Http read s n) takes the body a piece at a time, (Http close s) ends it. Redirects follow as request's do, each 3xx closed before the next hop. Exceeding the cap raises a label 'io."
        (returns OBJECT "An HttpStream positioned at the body of the FINAL response")
        (sample "(let ((s (Http open \"GET\" \"http://127.0.0.1:8080/f\" () ()))) (s status))" "200"))
      (def o (if (null? opts) () (first opts)))
      (def cap (Http %opt o (lit redirects) 10))
      (let hop ((verb method) (at url) (hs headers) (b body) (hops cap))
        (def s (Http %open-once verb at hs b o))
        (def code (s status))
        (def loc (Assoc find "location" (s headers)))
        (match
          ((not (if (>= code 300) (< code 400) #f)) s)
          ((null? loc) s)                                ; a 3xx with no location is final
          ((= hops 0)
            (if (= cap 0) s                              ; following disabled: the 3xx is the answer
              (do (Http close s) (Err raise (lit io) "Http: too many redirects" at))))
          (#t
            (do (Http close s)
                (let ((mk (Http %redirect-method code verb))
                      (next (Http %resolve-location (Http %parse-url at) (rest loc))))
                  ; credentials never cross hosts (the curl rule)
                  (let ((same-host?
                          (str=? (rest (Assoc find (lit host) (Http %parse-url at)))
                                 (rest (Assoc find (lit host) (Http %parse-url next))))))
                    (hop (first mk)
                         next
                         (if same-host? hs (Http %sans-auth hs))
                         (if (rest mk) b ())
                         (- hops 1)))))))))

    (method close (self (param s OBJECT "An (Http open) stream"))
      (doc "End the exchange: close the connection under the stream. Closing twice is harmless."
        (returns ANY "nil"))
      (match
        ((not (null? (s tls))) (do (Tls close (s tls)) (s tls ())))
        ((not (null? (s fd))) (do (Socket close (s fd)) (s fd ())))
        (#t ()))
      (s mode (lit none))
      ())


    ; The method a redirect hop uses (RFC 9110 + the curl/requests
    ; convention): 303 always becomes GET (body dropped); 301/302 become
    ; GET only when the original was POST; 307/308 preserve method+body.
    (method %redirect-method (self (param status INTEGER "The 3xx status")
                                   (param method STRING "The current verb"))
      (doc "The (verb . keep-body?) pair for following one redirect."
        (returns PAIR "(method-string . BOOL)")
        (example "(Http %redirect-method 303 \"POST\")" "(\"GET\" . #f)")
        (example "(Http %redirect-method 307 \"POST\")" "(\"POST\" . #t)"))
      (match
        ((= status 303) (pair "GET" #f))
        ((if (or (= status 301) (= status 302)) (str=? method "POST") #f)
          (pair "GET" #f))
        (#t (pair method #t))))

    (method %resolve-location (self (param u ALIST "The current url, parsed")
                                    (param loc STRING "The location header value"))
      (doc "Resolve a Location value against the current url: absolute http(s) urls pass through; a path-absolute /x keeps scheme/host/port; anything else resolves lexically against the current path's directory."
        (returns STRING "The next url")
        (example "(Http %resolve-location (Http %parse-url \"https://h:8443/a/b\") \"/c\")" "\"https://h:8443/c\""))
      (match
        ((or (Str8 starts? "http://" loc) (Str8 starts? "https://" loc)) loc)
        (#t
          (let ((tls? (rest (Assoc find (lit tls) u))))
            (let ((base (Str8 append
                          (if tls? "https://" "http://")
                          (rest (Assoc find (lit host) u))
                          (let ((port (rest (Assoc find (lit port) u))))
                            (if (= port (if tls? 443 80)) ""
                              (Str8 append ":" (%number->str port)))))))
              (if (Str8 starts? "/" loc) (Str8 append base loc)
                (let ((path (rest (Assoc find (lit path) u))))
                  (let ((cut (Str8 last-index-of "/" path)))
                    (Str8 append base (Str8 sub 0 (+ cut 1) path) loc)))))))))

    (method request (self (param method STRING "Verb: \"GET\", \"POST\", ...")
                          (param url STRING "http(s)://HOST[:PORT][/PATH]")
                          (param headers ALIST "(name . value) strings; () for none")
                          (param body ANY "Body string, or nil")
                          . (param opts ALIST "Options: (redirects . N) hop cap -- default 10, 0 disables following; (insecure) skips https certificate verification"))
      (doc "An http exchange that FOLLOWS redirects (cap 10, (redirects . 0) opts out): 3xx responses with a location header re-request per RFC -- 303 as GET, 301/302 as GET when the verb was POST, 307/308 preserving method and body; relative locations resolve against the current url; cross-scheme hops (http -> https) follow. Exceeding the cap raises a label 'io. The whole body is read into memory: (Http open) reads it a piece at a time."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST)) -- the FINAL response")
        (sample "(rest (Assoc find 'status (Http get \"http://github.com/\")))" "200 -- the 301 to https was followed"))
      (def s (Http open method url headers body (if (null? opts) () (first opts))))
      (def b (guard (e (do (Http close s) (error e))) (Http %drain s)))
      (Http close s)
      (list (pair (lit status) (s status))
            (pair (lit headers) (s headers))
            (pair (lit body) b)))

    (method get (self (param url STRING "http://HOST[:PORT][/PATH]")
                      . (param headers ALIST "Optional (name . value) header strings"))
      (doc "GET the url: (Http request \"GET\" url headers ())."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST))")
        (sample "(Assoc find 'status (Http get \"http://127.0.0.1:8080/health\"))" "('status . 200)"))
      (Http request "GET" url (if (null? headers) () (first headers)) ()))

    (method post (self (param url STRING "http://HOST[:PORT][/PATH]")
                       (param body STRING "Request body (Content-Length is set for you)")
                       . (param headers ALIST "Optional (name . value) header strings"))
      (doc "POST body to the url: (Http request \"POST\" url headers body). Set a content-type header when the peer cares."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST))")
        (sample "(Http post \"http://127.0.0.1:8080/in\" \"a=1\" (list (pair \"Content-Type\" \"application/x-www-form-urlencoded\")))" "the response alist"))
      (Http request "POST" url (if (null? headers) () (first headers)) body))

    (method put (self (param url STRING "Target url")
                      (param body STRING "Request body")
                      . (param headers ALIST "Optional (name . value) header strings"))
      (doc "PUT body to the url."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST))"))
      (Http request "PUT" url (if (null? headers) () (first headers)) body))

    (method patch (self (param url STRING "Target url")
                        (param body STRING "Request body")
                        . (param headers ALIST "Optional (name . value) header strings"))
      (doc "PATCH the url with body."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST))"))
      (Http request "PATCH" url (if (null? headers) () (first headers)) body))

    (method delete (self (param url STRING "Target url")
                         . (param headers ALIST "Optional (name . value) header strings"))
      (doc "DELETE the url."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST))"))
      (Http request "DELETE" url (if (null? headers) () (first headers)) ()))

    (method head (self (param url STRING "Target url")
                       . (param headers ALIST "Optional (name . value) header strings"))
      (doc "HEAD the url: the headers a GET would return, no body (framing headers describe the body that WOULD have come; the parser applies no body framing)."
        (returns ALIST "((status . INT) (headers . ALIST) (body . ()))"))
      (Http request "HEAD" url (if (null? headers) () (first headers)) ()))))

(doc (provide x/net/http Http)
  (note "http/1.1 over Socket -- and https over Tls (#412), verification on, names resolved via (Socket resolve) with the Host header keeping the name. Connection: close; chunked + Content-Length framing decoded; bodies are byte lists (bytes->str for text); redirects auto-follow (cap 10; (redirects . 0) opts out; 303->GET, 301/302 POST->GET, 307/308 preserve). (Http open) / (Http read s n) / (Http close s) stream a body a piece at a time. Verbs: get/post/put/patch/delete/head; url-encode/with-query build query strings; (Http basic-auth u p) / (Http bearer-auth tok) are the Authorization pairs (stripped on cross-host redirects). net/ = messages carried over sys/socket transport.")
  "A plain-http client, homed on the Http class.")
