; net/rest.x -- Rest: the JSON layer over Http (#412).
;
; RESTful endpoints speak JSON: these verbs emit x values as JSON request
; bodies (Content-Type/Accept set) and decode JSON response bodies back
; to x values by content-type. The Json mapping applies both ways:
; object <-> Dict, array <-> list, null <-> 'null, numbers/strings/bools.
;
;   (Rest get url [headers])          (Rest delete url [headers])
;   (Rest post url value [headers])   (Rest put url value [headers])
;   (Rest patch url value [headers])
;     -> ((status . INT) (headers . ALIST) (body . VALUE))
;
; body is the DECODED value when the response says json and carries
; content; the raw byte list otherwise (an empty body is ()). Statuses
; stay data -- a 404 comes back as 404, never a raise (the redirect
; stance): (Rest ok? resp) answers the 2xx question. Everything Http
; rules holds here: https via Tls, names via resolve, no redirects.
;
; Zero top-level %-globals (new-file budget 0).

(import x/type/class)
(import x/core/list)
(import x/type/assoc)
(import x/net/http)
(import x/codec/json)

(def-class Rest ()
  (doc "JSON-speaking verbs over Http: values go out as JSON bodies, JSON responses come back decoded (object <-> Dict, array <-> list, null <-> 'null). Statuses stay data -- (Rest ok? resp) answers the 2xx question."
    (sample "(Assoc find 'body (Rest get \"http://127.0.0.1:8080/users/1\"))" "('body . the decoded Dict)")
    (see get) (see post) (see ok?))
  (static
    ; Decode the body by content-type; pass non-json bodies through raw.
    (method %decode (self (param resp ALIST "An Http response alist"))
      (doc "The response with a JSON body decoded to a value (content-type says json and bytes exist); other bodies pass through as byte lists."
        (returns ALIST "((status . INT) (headers . ALIST) (body . VALUE-or-BYTES))"))
      (def headers (rest (Assoc find (lit headers) resp)))
      (def body (rest (Assoc find (lit body) resp)))
      (def ct (Assoc find "content-type" headers))
      (def json? (if (null? ct) #f (Str8 includes? "json" (rest ct))))
      (list (pair (lit status) (rest (Assoc find (lit status) resp)))
            (pair (lit headers) headers)
            (pair (lit body)
                  (if (if json? (pair? body) #f)
                    (Json parse (bytes->str body))
                    body))))

    ; The JSON request headers, ahead of the caller's (theirs win at the
    ; peer: later duplicates are legal http, and callers may override).
    (method %headers (self (param extra ALIST "Caller headers"))
      (doc "Content-Type/Accept application/json plus the caller's headers."
        (returns ALIST "Header pairs"))
      (List append
        (list (pair "Content-Type" "application/json")
              (pair "Accept" "application/json"))
        extra))

    (method get (self (param url STRING "Endpoint url")
                      . (param headers ALIST "Optional (name . value) header strings"))
      (doc "GET the endpoint; a JSON response body comes back decoded."
        (returns ALIST "((status . INT) (headers . ALIST) (body . VALUE))")
        (sample "(rest (Assoc find 'body (Rest get \"http://127.0.0.1:8080/users\")))" "the decoded array as a list"))
      (Rest %decode
        (Http request "GET" url
          (List append (list (pair "Accept" "application/json"))
                       (if (null? headers) () (first headers)))
          ())))

    (method delete (self (param url STRING "Endpoint url")
                         . (param headers ALIST "Optional (name . value) header strings"))
      (doc "DELETE the endpoint; a JSON response body comes back decoded."
        (returns ALIST "((status . INT) (headers . ALIST) (body . VALUE))"))
      (Rest %decode
        (Http request "DELETE" url
          (List append (list (pair "Accept" "application/json"))
                       (if (null? headers) () (first headers)))
          ())))

    (method post (self (param url STRING "Endpoint url")
                       (param value ANY "The value to send, emitted as JSON (Dict/list/string/number/bool/'null)")
                       . (param headers ALIST "Optional (name . value) header strings"))
      (doc "POST value as a JSON body; a JSON response body comes back decoded."
        (returns ALIST "((status . INT) (headers . ALIST) (body . VALUE))")
        (sample "(Rest post \"http://127.0.0.1:8080/users\" (Dict from-plist (list \"name\" \"ida\")))" "the response alist, body decoded"))
      (Rest %decode
        (Http request "POST" url
          (Rest %headers (if (null? headers) () (first headers)))
          (Json emit value))))

    (method put (self (param url STRING "Endpoint url")
                      (param value ANY "The value to send, emitted as JSON")
                      . (param headers ALIST "Optional (name . value) header strings"))
      (doc "PUT value as a JSON body; a JSON response body comes back decoded."
        (returns ALIST "((status . INT) (headers . ALIST) (body . VALUE))"))
      (Rest %decode
        (Http request "PUT" url
          (Rest %headers (if (null? headers) () (first headers)))
          (Json emit value))))

    (method patch (self (param url STRING "Endpoint url")
                        (param value ANY "The value to send, emitted as JSON")
                        . (param headers ALIST "Optional (name . value) header strings"))
      (doc "PATCH the endpoint with value as a JSON body; a JSON response body comes back decoded."
        (returns ALIST "((status . INT) (headers . ALIST) (body . VALUE))"))
      (Rest %decode
        (Http request "PATCH" url
          (Rest %headers (if (null? headers) () (first headers)))
          (Json emit value))))

    (method ok? (self (param resp ALIST "A Rest/Http response alist"))
      (doc "Did the exchange succeed at the http level -- status in [200, 300)?"
        (returns BOOL "#t for a 2xx status")
        (example "(Rest ok? (list (pair 'status 204)))" "#t"))
      (let ((st (rest (Assoc find (lit status) resp))))
        (if (>= st 200) (< st 300) #f)))))

(doc (provide x/net/rest Rest)
  (note "The JSON layer over Http: values out (Json emit + the json headers), values back (Json parse by content-type). Statuses stay data -- ok? answers 2xx; 3xx/4xx/5xx come back for the caller's policy, as with Http's redirects.")
  "JSON-speaking REST verbs, homed on the Rest class.")
