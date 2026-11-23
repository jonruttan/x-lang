# language-model

Continue a prompt with a language model in GPT-2's layout.

```sh
x -l xe -f apps/language-model/main.x -- DIR "Hello, I'm a language model," 16
```

`DIR` holds the model as GPT-2 is published: `model.safetensors`,
`vocab.json` and `merges.txt`. The prompt is printed, and then each piece
as the model writes it, 32 of them unless a number follows the prompt.

Two more numbers draw each piece at random: a temperature, and how many
of the highest-scored pieces the draw is among.

```sh
x -l xe -f apps/language-model/main.x -- DIR "Once upon a time" 40 0.8 40
```

The program is [`LanguageModel`](../../lib/x/num/language-model.x) and a
command line; `(help LanguageModel)` has the class.

## A prelude for the vocabulary

Reading `vocab.json` and `merges.txt` is most of a run. A prelude that
reads them is imaged with the boot, and later runs load the image:

```x
(import x/num/language-model)
(def language-model-pieces
  (BytePair from-files "/path/to/vocab.json" "/path/to/merges.txt"))
```

```sh
x -l xe --prelude pieces.x -f apps/language-model/main.x -- DIR "Hello,"
```

The program uses `language-model-pieces` when the prelude bound it, and
reads the two files itself otherwise. The paths in a prelude are
absolute, and the image is rewritten when the prelude changes, not when
the files do ([state images](../../docs/state-images.md)).

## Why it is a program and not `-l language-model`

An entry under `apps/` boots itself and runs its command as it loads, so
its boot is never imaged, and the vocabulary would be read on every run.
A program run with `-f` leaves the boot to the dialect, which is imaged,
prelude and all.
