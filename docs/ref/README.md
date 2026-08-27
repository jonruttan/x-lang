# Generated reference

This directory is the output root for generated API reference. Its contents
are build artifacts, ignored by git; the directory itself is tracked, because
the x-lang generator expects it to exist.  (Doxygen's half now runs inside
the engine and makes its own output root there; the site workflow
copies it in, so the published path is unchanged.)  Doxygen fails outright
without an output root:

    error: tag OUTPUT_DIRECTORY: Output directory 'docs/ref/c/' does not
           exist and cannot be created

| subdirectory | generator | source |
|---|---|---|
| `c/` | `make doc-c` -- delegates to the engine, which generates into `engine/docs/ref/c/` | the C engine, [x-engine-c](https://github.com/jonruttan/x-engine-c) |
| `x/` | `make doc-x` (`tools/dev/doc.x`) | the `(doc ...)` forms in `lib/x/**` |

`make doc` runs both. Hand-written documentation lives one level up, in
`docs/`; nothing here should be edited, since the next generator run
overwrites it.
