# Glossary

One name per concept. This page owns the cross-layer vocabulary; the normative
anchors it defers to are the absence discipline (spec.md, "Nil, false, and
truthiness") and the method-naming adjudications in
[contributing.md](contributing.md). Terms are added here as naming decisions
are settled (tracked in issue #42 and #44).

## Association vocabulary

- **assoc** — one dotted `(key . val)` pair: a single association. `List assoc`
  / `List assq` return the assoc itself.
- **alist** — a list of assocs: `((k1 . v1) (k2 . v2) ...)`. The associative
  wire format of the library: pairing producers (`List zip`, `Gen zip`,
  `Gen enumerate`, `List group-by`, `Dict ->alist`) emit alists, and the keyed
  consumers (`Assoc` API, `Dict from-alist`) take them. Keys in the alist layer
  compare with `eq?`.
- **plist** — the flat `(k v k v ...)` shape. Legal only in **option stores**.
- **option store** — an argument accepting an alist *or* a plist, walked by
  `%opt-cell`: `let-opts`, `Assoc get-or`/`opt-get-or`/`opt-get-or-else`, and
  object initialization (`new`, `new-from`). Everything else — including
  `Dict` and JSON — is alist-only.
- **bindings list** — `((key value) ...)` two-element lists, the shape `let`
  uses. Bridged to alists by `Assoc from-bindings` / `Assoc ->bindings`.
