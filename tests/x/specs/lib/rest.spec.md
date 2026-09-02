# Rest: the JSON layer over Http (#412)
# @weight 3

Values out as JSON bodies, JSON responses decoded by content-type,
statuses kept as data. The wire path was proven live at build time:
https-by-name GETs against github.com (DNS -> verified TLS -> parse),
a decoded Dict from api.github.com's rate_limit endpoint, and a
captured PUT showing the verb, json headers, and emitted body. These
specs pin the pure tier.

## decoding

### a json content-type decodes the body; others pass bytes through

```x
(do (import x/net/rest)
  (def %s->b (fn (_ s) (let go ((i (- (Str8 length s) 1)) (acc ()))
                         (if (< i 0) acc (go (- i 1) (pair (Char ->int (Str8 ref i s)) acc))))))
  (def j (Rest %decode (list (pair 'status 200)
                             (pair 'headers (list (pair "content-type" "application/json")))
                             (pair 'body (%s->b "{\"n\": 7}")))))
  (def t (Rest %decode (list (pair 'status 200)
                             (pair 'headers (list (pair "content-type" "text/plain")))
                             (pair 'body (%s->b "hi")))))
  (list ((rest (Assoc find 'body j)) get "n")
        (bytes->str (rest (Assoc find 'body t)))))
```
---
    (7 "hi")

### an empty body stays nil even when the type says json

```x
(do (import x/net/rest)
  (list (rest (Assoc find 'body
    (Rest %decode (list (pair 'status 204)
                        (pair 'headers (list (pair "content-type" "application/json")))
                        (pair 'body ())))))))
```
---
    (())

## status policy

### ok? is the 2xx test; statuses stay data

```x
(do (import x/net/rest)
  (list (Rest ok? (list (pair 'status 200)))
        (Rest ok? (list (pair 'status 204)))
        (Rest ok? (list (pair 'status 301)))
        (Rest ok? (list (pair 'status 404)))))
```
---
    (#t #t #f #f)

## request headers

### the json pair rides ahead of caller headers

```x
(do (import x/net/rest)
  (Rest %headers (list (pair "X-A" "1"))))
```
---
    (("Content-Type" . "application/json") ("Accept" . "application/json") ("X-A" . "1"))
