[← Index](../../index.md)

# x/core/repl

Start the read-eval-print loop.

### `repl`

Start the read-eval-print loop.

> Customizable via %repl-prompt (default "> ") and %repl-print.

> Uses dynamic scoping so def persists across iterations.

> Uses eval! (no env save/restore) so definitions persist.

