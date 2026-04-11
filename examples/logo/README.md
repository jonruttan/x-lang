# Logo Turtle Graphics

A Logo interpreter built on x-lang with a live browser viewer.

## Quick Start

```sh
rlwrap ./x.sh -l logo
```

Opens a REPL at `http://localhost:8080`. Type Logo commands and watch the turtle draw in the browser.

## Commands

### Movement
| Command | Args | Description |
|---------|------|-------------|
| `FORWARD` / `FD` | distance | Move forward |
| `BACK` / `BK` | distance | Move backward |
| `RIGHT` / `RT` | degrees | Turn clockwise |
| `LEFT` / `LT` | degrees | Turn counterclockwise |
| `SETXY` | x y | Move to absolute position |
| `SETX` | x | Set x coordinate |
| `SETY` | y | Set y coordinate |
| `HOME` | | Return to origin, heading 0 |
| `SETHEADING` / `SETH` | degrees | Set absolute heading |

### Pen
| Command | Args | Description |
|---------|------|-------------|
| `PENUP` / `PU` | | Stop drawing |
| `PENDOWN` / `PD` | | Resume drawing |
| `PENCOLOR` / `PC` | color | Set pen color (`"red"`, `"#FF0000"`) |
| `PENWIDTH` / `PW` | width | Set line width |

### Screen
| Command | Args | Description |
|---------|------|-------------|
| `CLEARSCREEN` / `CS` | | Clear and reset |
| `HIDETURTLE` / `HT` | | Hide cursor |
| `SHOWTURTLE` / `ST` | | Show cursor |

### Queries
| Function | Returns |
|----------|---------|
| `HEADING` | Current heading (degrees) |
| `XCOR` | Current x position |
| `YCOR` | Current y position |
| `DISTANCE(x, y)` | Distance to point |
| `TOWARDS(x, y)` | Heading toward point |
| `TURTLE.STATE` | Position + heading as list |

### Scaled Turtle
| Command | Args | Description |
|---------|------|-------------|
| `GROW` | factor | Multiply scale by factor |
| `S.FORWARD` / `S.FD` | distance | Forward * current scale |

## Control Flow

```logo
REPEAT 4 [ FD 100 RT 90 ]

REPEAT FOREVER [ FD 1 RT 1 ]

REPEAT [ FD 10 X <- X + 1 ] UNTIL X > 100

IF X > 5 THEN FD 100
IF X > 5 THEN FD 100 ELSE BK 50
IF NOT X < 0 THEN FD 100

TO SQUARE SIZE
    REPEAT 4
        FD SIZE
        RT 90

TO POLY SIDE ANGLE [ FD SIDE RT ANGLE POLY SIDE ANGLE ]

STOP                    ; exit current procedure
RETURN expr             ; return value from procedure
```

## Expressions

Infix arithmetic with standard precedence:

```logo
FD 2 + 3 * 4            ; = 14
FD (2 + 3) * 4           ; = 20
X <- SIDE + 1
POLYSPI (SIDE + 1, ANGLE)
```

Operators: `+` `-` `*` `/` `^` `=` `>` `<` `>=` `<=` `<>`

## Math Functions

```logo
SQRT(144)               ; 12
ABS(-7)                 ; 7
SIN(90)                 ; 1
COS(0)                  ; 1
TAN(45)                 ; 1
ARCTAN(1)               ; 45
REMAINDER(17, 5)        ; 2
RAND(1, 100)            ; random integer
ROUND(3.7)              ; 4
INT(3.9)                ; 3
POWER(2, 10)            ; 1024
PI                      ; 3.14159...
NOT(expr)               ; boolean negation
MEMBER(item, [list])    ; list membership
```

## Variables

```logo
X <- 10                 ; assignment
X <- X + 1              ; update
PRINT X                 ; output value
TYPE X                  ; output without newline
```

## File Loading

```logo
LOAD "examples/logo/ch1.logo"
```

## Meta-evaluation

```logo
EXECUTE "fd 100 rt 90"
```

## Examples

### Square
```logo
REPEAT 4 [ FD 100 RT 90 ]
```

### Circle
```logo
REPEAT 360 [ FD 1 RT 1 ]
```

### Spiral
```logo
TO POLYSPI SIDE ANGLE
    FD SIDE
    RT ANGLE
    POLYSPI (SIDE + 1, ANGLE)
```

### Flower
```logo
TO ARCR R DEG [ REPEAT DEG [ FD R RT 1 ] ]
TO PETAL SIZE [ ARCR SIZE 60 RT 120 ARCR SIZE 60 RT 120 ]
TO FLOWER SIZE [ REPEAT 6 [ PETAL SIZE RT 60 ] ]
FLOWER 60
```

### Spirolateral
```logo
TO SPIRO SIDE ANGLE MAX
    REPEAT FOREVER
        COUNT <- 1
        REPEAT MAX
            FD SIDE * COUNT
            RT ANGLE
            COUNT <- COUNT + 1
```

### GCD (Euclid's Algorithm)
```logo
TO EUCLID N R
    IF N = R THEN RETURN N
    IF N > R THEN RETURN EUCLID(N - R, R)
    IF N < R THEN RETURN EUCLID(N, R - N)

PRINT EUCLID(360, 144)    ; 72
```

## Browser Viewer

The viewer at `http://localhost:8080` shows the turtle drawing in real time.

- **Play/Pause** — control animation playback
- **Reset** — restart animation from the beginning
- **Speed slider** — 1 (slow) to 200 (instant)

The viewer receives a bytecode stream from the REPL. Each turtle command emits compact opcodes (`F`, `R`, `L`, `U`, `D`, `K`, `W`, etc.) that the browser interprets and renders as SVG.

### Static Embedding

For blog posts, embed bytecodes directly:

```html
<script>
window.TURTLE_BC = ["F",100,"R",90,"F",100,"R",90,"F",100,"R",90,"F",100,"R",90];
</script>
<script src="turtle-player.js"></script>
```

## Architecture

```
Logo REPL (x-lang)                    Browser (turtle.html)
  |                                      |
  |-- turtle commands                    |
  |     (fd, rt, pencolor, ...)          |
  |                                      |
  v                                      |
  state.x -- bytecode emission           |
  |     ("F",100  "R",90  "K","red")     |
  |                                      |
  v                                      |
  serve.x -- /bc endpoint ---------> poll every 100ms
  |     (JSON array of bytecodes)        |
  |                                      v
  |                               parseBytecode()
  |                               compute positions
  |                               render SVG lines
  |                               animate cursor
```

## Source Files

| File | Description |
|------|-------------|
| `lib/logo.x` | Entry point — loads library, starts REPL |
| `lib/x/logo.x` | Server setup, hooks, fork |
| `lib/x/logo/state.x` | Turtle state and bytecode emission |
| `lib/x/logo/types.x` | Logo tokenizer types |
| `lib/x/logo/expr.x` | Expression parser (infix to values) |
| `lib/x/logo/dispatch.x` | Command dispatcher and control flow |
| `lib/x/logo/math.x` | Math functions and LFSR random |
| `lib/x/logo/tstate.x` | Extended turtle commands |
| `lib/x/logo/indent.x` | Indentation preprocessor |
| `lib/x/logo/repl.x` | Interactive REPL |
| `lib/x/logo/serve.x` | HTTP server for browser viewer |
| `lib/x/logo/json.x` | Bytecode JSON output |
| `turtle.html` | Browser viewer and animation |

## Reference

Based on *Turtle Geometry: The Computer as a Medium for Exploring Mathematics* by Harold Abelson and Andrea diSessa (MIT Press, 1981).
