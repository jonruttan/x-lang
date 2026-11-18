# The Document Tree

A document is a list of blocks. A reader of a format answers one and a
writer takes one, so a format needs one reader and one writer to convert to
and from every other.

| Module | Reads | Writes |
|---|---|---|
| `x/codec/markdown` | `(Markdown parse TEXT)` | `(Markdown html BLOCKS)`, HTML |
| `x/codec/html` | `(Html parse TEXT)` | |
| `x/tui/page` | | `(Page markdown BLOCKS WIDTH)`, lines for a terminal |

`x/codec/document` holds the tree's definition as data and checks a tree
against it:

```x
(import x/codec/document)
(Document blocks)        ; the block nodes, each (NAME KIND...)
(Document inlines)       ; the inline nodes
(Document check BLOCKS)  ; nil, or the first fault as (NAME PART NODE)
```

## Nodes

A node is a list led by its name, a symbol, then its parts in order. The
tree is lists, strings, symbols, integers, `#t`, `#f` and nil, and nothing
else: a reader builds it with `list`, and a writer reads it with `first` and
`rest`.

### Blocks

| Node | Meaning |
|---|---|
| `(heading LEVEL INLINES)` | A heading, LEVEL 1 to 6 |
| `(paragraph INLINES)` | A paragraph |
| `(code-block INFO TEXT)` | Preformatted text. INFO names its language, `""` for none; TEXT keeps its line ends |
| `(block-quote BLOCKS)` | A quotation |
| `(list ORDERED? START TIGHT? ITEMS)` | A list. ITEMS is a list of items, each a list of blocks |
| `(thematic-break)` | A rule between sections |
| `(html-block TEXT)` | HTML carried through as it was written |

In a list, START is the number of an ordered list's first item, and nil for
a list with no numbers. TIGHT? is `#t` when the items' paragraphs are set
with no space between them.

### Inlines

INLINES is a list of strings and inline nodes. A string is text.

| Node | Meaning |
|---|---|
| `(emph INLINES)` | Emphasis |
| `(strong INLINES)` | Strong emphasis |
| `(code TEXT)` | A code span |
| `(softbreak)` | A line end in the source that a writer may set as a space |
| `(hardbreak)` | A line end a writer keeps |
| `(link DESTINATION TITLE INLINES)` | A link; TITLE is nil for none |
| `(image DESTINATION TITLE INLINES)` | An image; INLINES is its alternative text |
| `(html-inline TEXT)` | HTML carried through as it was written |
| `(field TYPE NAME VALUE ON OPTIONS FORM)` | A form's field, as `x/codec/html` describes it |

## What a writer may rely on

- Every node is one of those above, with exactly the parts shown. `(Document
  check)` answers nil for the tree.
- Text is UTF-8 with character references already decoded, and
  destinations and titles are decoded too. A writer escapes for its own
  format.
- Blocks hold blocks only through `block-quote` and `list`; inlines hold
  inlines only through `emph`, `strong`, `link` and `image`.
- A node a writer has no form for has a plain reading: an `image` is its
  alternative text, a `field` its value, `html-block` and `html-inline`
  nothing, and a `softbreak` a space.

## What a reader must do

- Answer only the nodes above. Structure the format has and the tree does
  not is set with the nodes there are, as `x/codec/html` sets a table as a
  paragraph a row.
- Decode the format's escapes, so that no text in the tree is written in
  the source format's notation.
- Pass `(Document check)`: a reader's spec checks what it answers.

## Adding a node

A node is added to the table in `lib/x/codec/document.x`, to this page, and
to each writer, in one change. A reader may answer the node once every
writer takes it.
