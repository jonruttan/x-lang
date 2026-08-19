; net/http.x -- Http: a plain-http/1.1 client over the Socket class (#374).
;
; The ruled strategy (issue comment, 2026-08-20): pure x over
; (Socket tcp-connect) -- request line + headers out, full response
; parsing back: status line, headers, and the body under EITHER framing
; (Content-Length, or Transfer-Encoding: chunked -- decoded here).
; Connection: close on every request; no keep-alive, no redirects
; (the status comes back -- following 3xx is the caller's policy).
;
; https rides the Tls class (#412's amendment to the #374 ruling:
; libssl binds over the dlopen FFI -- the variadic blocker was libcurl's;
; verification + SNI + hostname checks on by default). Hostnames resolve
; through (Socket resolve) at request time; the Host header carries the
; NAME (virtual hosting), the connect takes the quad.
;
; net/ is the network-PROTOCOL tier: message shapes over sys/socket's
; transport, the way codec/ is data shapes over strings and bytes.
;
; Bodies ride BYTE LISTS (the lossless carrier: recv's string door
; truncates at NUL; this client reads through Socket recv-bytes) --
; (bytes->str body) for textual responses. Request bodies are strings
; (text protocols; NUL-free by the string tier's nature).
;
; Zero top-level %-globals (new-file budget 0).

(import x/type/class)
(import x/core/list)
(import x/type/assoc)
(import x/sys/socket)
(import x/net/tls)

(def-class Http ()
  (doc "A plain-http/1.1 client over Socket: (Http get url), (Http post url body), (Http request method url headers body) -> ((status . INT) (headers . ALIST) (body . BYTE-LIST)). Header names come back lowercased; https and DNS are out by design (the curl door covers TLS)."
    (example "(rest (Assoc find 'status (Http %parse-response (list 72 84 84 80 47 49 46 49 32 50 48 48 32 75 13 10 13 10))))" "200")
    (see get) (see request))
  (static
    ; --- url -> ((host . H) (port . P) (path . S)); strict per #61 ---
    (method %parse-url (self (param url STRING "http://HOST[:PORT][/PATH...]"))
      (doc "Split an http or https url; the path defaults to \"/\", the port to the scheme's (80/443); a missing scheme raises kind-'value."
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
      (doc "Render the request: verb + path, Host, Connection: close, Content-Length when a body rides, the caller's headers, CRLF framing."
        (returns STRING "The full request text"))
      (def head
        (Str8 append method " " (rest (Assoc find (lit path) u)) " HTTP/1.1\r\n"
                     "Host: " (rest (Assoc find (lit host) u)) "\r\n"
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
    (method %hex-nibble (self (param c INT "Byte value"))
      (doc "The hex value of one byte, or -1 off-domain."
        (returns INT "0-15, or -1"))
      (match
        ((if (>= c 48) (<= c 57) #f) (- c 48))
        ((if (>= c 97) (<= c 102) #f) (- c 87))
        ((if (>= c 65) (<= c 70) #f) (- c 55))
        (#t -1)))

    (method %dechunk (self (param bytes LIST "Chunked-framing body bytes"))
      (doc "Decode Transfer-Encoding: chunked framing: hex-size line, that many bytes, CRLF, repeated to the zero chunk. Malformed framing raises kind-'value."
        (returns LIST "The unframed body bytes"))
      (def %bad (fn (_ what)
        (Err raise (lit value) (Str8 append "Http: bad chunked framing: " what) ())))
      (let go ((l bytes) (acc ()))
        ; the size line: hex digits, tolerate extensions up to CRLF
        (let ((size-and-rest
                (let sz ((l l) (n 0) (any #f))
                  (match
                    ((null? l) (%bad "unterminated size line"))
                    ((if (pair? (rest l)) (if (= (first l) 13) (= (first (rest l)) 10) #f) #f)
                      (if any (pair n (rest (rest l))) (%bad "missing size")))
                    (#t
                      (let ((v (Http %hex-nibble (first l))))
                        (if (< v 0)
                          ; chunk extensions (";...") ride to the CRLF
                          (let ext ((l l))
                            (match
                              ((null? l) (%bad "unterminated size line"))
                              ((if (pair? (rest l)) (if (= (first l) 13) (= (first (rest l)) 10) #f) #f)
                                (if any (pair n (rest (rest l))) (%bad "missing size")))
                              (#t (ext (rest l)))))
                          (sz (rest l) (+ (* 16 n) v) #t))))))))
          (let ((size (first size-and-rest)) (l (rest size-and-rest)))
            (match
              ((= size 0) (List flat-map (fn (_ c) c) (%reverse acc)))
              (#t
                (let take ((l l) (k size) (chunk ()))
                  (match
                    ((= k 0)
                      (match
                        ((if (pair? l) (if (pair? (rest l)) (if (= (first l) 13) (= (first (rest l)) 10) #f) #f) #f)
                          (go (rest (rest l)) (pair (%reverse chunk) acc)))
                        (#t (%bad "chunk not CRLF-terminated"))))
                    ((null? l) (%bad "truncated chunk"))
                    (#t (take (rest l) (- k 1) (pair (first l) chunk)))))))))))

    (method %parse-response (self (param bytes LIST "The raw response bytes, complete")
                                  . (param no-body BOOL "Truthy for HEAD responses: headers may claim a Content-Length, but no body follows"))
      (doc "Parse a full http response: status from the status line, headers lowercased into an alist, the body unframed (chunked decoded; Content-Length applied; else everything to EOF). HEAD callers pass the no-body flag -- framing headers describe the body a GET would have carried."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST))"))
      (def %bad (fn (_ what)
        (Err raise (lit value) (Str8 append "Http: bad response: " what) ())))
      ; split head/body at the first CRLFCRLF; the look-ahead rides a
      ; helper (a hand-inlined six-if chain cost a paren-slip that
      ; mis-tiered every later method -- structure over cleverness)
      (def %crlf2?
        (fn (_ l)
          (let ((b? (fn (_ l v) (if (pair? l) (= (first l) v) #f))))
            (if (b? l 13)
              (if (b? (rest l) 10)
                (if (b? (rest (rest l)) 13)
                  (b? (rest (rest (rest l))) 10)
                  #f)
                #f)
              #f))))
      (def split-at
        (let scan ((l bytes) (i 0))
          (match
            ((null? l) ())
            ((%crlf2? l) i)
            (#t (scan (rest l) (+ i 1))))))
      (when (null? split-at) (%bad "no header terminator"))
      (def head-str (bytes->str (List take split-at bytes)))
      (def body-raw (List drop (+ split-at 4) bytes))
      (def lines (Str8 split "\r\n" head-str))
      (when (null? lines) (%bad "empty head"))
      ; "HTTP/1.x NNN reason"
      (def status
        (let ((parts (Str8 split " " (first lines))))
          (match
            ((null? (rest parts)) (%bad "no status code"))
            (#t
              (let ((n (%str->number (first (rest parts)))))
                (if (null? n) (%bad "non-numeric status") n))))))
      (def headers
        (List map
          (fn (_ ln)
            (let ((colon (Str8 index-of ":" ln)))
              (if (null? colon) (pair (Str8 downcase ln) "")
                (pair (Str8 downcase (Str8 sub 0 colon ln))
                      (Str8 trim (Str8 sub (+ colon 1) (Str8 length ln) ln))))))
          (List reject (fn (_ ln) (str=? ln "")) (rest lines))))
      (def body
        (if (if (null? no-body) #f (first no-body)) ()
        (let ((te (Assoc find "transfer-encoding" headers)))
          (match
            ((if (pair? te) (Str8 includes? "chunked" (rest te)) #f)
              (Http %dechunk body-raw))
            (#t
              (let ((cl (Assoc find "content-length" headers)))
                (match
                  ((null? cl) body-raw)
                  (#t
                    (let ((n (%str->number (rest cl))))
                      (if (null? n) body-raw (List take n body-raw)))))))))))
      (list (pair (lit status) status)
            (pair (lit headers) headers)
            (pair (lit body) body)))

    (method %quad? (self (param host STRING "Host text"))
      (doc "Is this a dotted quad already (digits and dots only)? Names go through (Socket resolve)."
        (returns BOOL "#t for quad-shaped text"))
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

    ; --- the wire ---
    (method request (self (param method STRING "Verb: \"GET\", \"POST\", ...")
                          (param url STRING "http://HOST[:PORT][/PATH]")
                          (param headers ALIST "(name . value) strings; () for none")
                          (param body ANY "Body string, or nil"))
      (doc "One http/1.1 exchange with Connection: close: connect, send, read to EOF, parse. Redirects are NOT followed -- the 3xx status and its location header come back for the caller's policy."
        (returns ALIST "((status . INT) (headers . ALIST) (body . BYTE-LIST))")
        (sample "(bytes->str (rest (Assoc find 'body (Http get \"http://127.0.0.1:8080/\"))))" "the page text"))
      (def u (Http %parse-url url))
      (def host (rest (Assoc find (lit host) u)))
      (def quad (if (Http %quad? host) host (Socket resolve host)))
      (def tls? (rest (Assoc find (lit tls) u)))
      (def req (Http %build-request method u headers body))
      (def raw
        (if tls?
          (let ((sess (Tls connect quad (rest (Assoc find (lit port) u))
                          (list (pair (lit host) host)))))
            (let ()
              (Tls send sess req)
              (let ((bytes (let drain ((acc ()))
                             (let ((chunk (Tls recv-bytes sess 65536)))
                               (if (null? chunk) (List flat-map (fn (_ c) c) (%reverse acc))
                                 (drain (pair chunk acc)))))))
                (Tls close sess)
                bytes)))
          (let ((fd (Socket tcp-connect quad (rest (Assoc find (lit port) u)))))
            (let ()
              (Socket send fd req)
              (let ((bytes (let drain ((acc ()))
                             (let ((chunk (Socket recv-bytes fd 65536)))
                               (if (null? chunk) (List flat-map (fn (_ c) c) (%reverse acc))
                                 (drain (pair chunk acc)))))))
                (Socket close fd)
                bytes)))))
      (Http %parse-response raw (str=? method "HEAD")))

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
  (note "http/1.1 over Socket -- and https over Tls (#412), verification on, names resolved via (Socket resolve) with the Host header keeping the name. Connection: close; chunked + Content-Length framing decoded; bodies are byte lists (bytes->str for text); redirects are the caller's policy. Verbs: get/post/put/patch/delete/head; url-encode/with-query build query strings. net/ = protocol shapes over sys/socket transport.")
  "A plain-http client, homed on the Http class.")
