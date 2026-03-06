Title:       X-Doc Text Formatting  
Description: Development notes for X.  
Keywords:    [#X, #X-Lisp, #Project, #Notes]  
Author:      "[Jon Ruttan](jonruttan@gmail.com)"  
Date:        2021-10-07  
Revision:    2 (2021-12-03)  

# X-Doc Text Formatting

## Text Formatting

All text formatting in documents follows the [GitHub Flavored Markdown(GFM)](https://github.github.com/gfm/) / [CommonMark](https://commonmark.org/) specification, with ATX (hash (#) prefix) headers.


## Typographical Conventions

- *Italic*
  - New terms, URLs, email addresses, filenames, and file extensions.

- `Constant width`
  - Program elements such as variable or function names, databases, data types, environment variables, statements, and keywords.

- **`Constant width bold`**
  - Commands or other text that should be entered literally.

- *`Constant width italic`*
  - Text that should be replaced with supplied values or by values determined by context.

- _**NOTE:** Best practices in proton pack operation include not crossing the streams._
  - A tip, suggestion, or general note.

- _**WARNING:** Crossing the streams can result in total protonic reversal!_
  - A warning or caution.

- _**IMPORTANT:** Never cross the streams!_
  - A strong warning or prohibition.

- _**COUNTEREXAMPLE:** This might result in the streams becoming crossed._
  - An example of what not to do.

- ```Fenced Code block```
  - Program listings.


## Fenced Code Blocks

###  Info String

`[LANGUAGE] [counterexample] [name=[FILENAME]] [numbering=[on|[OFFSET]] [lines=[HEIGHT]`

### Example

```c counterexample name=main.c numbering=on lines=10
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[], char *env[])
{
  int i;

  /* IMPORTANT: This has an off-by-one error. */
  for (i=0; i <= argc; i++) {
    printf("Argument %d: '%s'\n", i, argv[i]);
  }

  return EXIT_SUCCESS;
}
```

## Files

### Filenames

***Preferred:***

```regex
[0-9a-zA-Z][-.0-9a-zA-Z]*\.md
```
    
***Expanded:***

```regex
[0-9a-zA-Z_][-.0-9a-zA-Z_]*\.md
```
    
***Minimal:***

```regex
[0-9A-Z][-.0-9A-Z]*\.MD
```

### Metadata

#### YAML Frontmatter

***Minimal***

_**NOTE:** There are two trailing spaces at the end of each line of the frontmatter to correctly format it on viewers/editors that don't handle frontmatter._

```yaml
Title:       <TITLE>  
Description: <DESCRIPTION>  
Keywords:    [#<KEYWORD>]  
Author:      "[Jon Ruttan](jonruttan@gmail.com)"  
Date:        <YYYY-MM-DD>  
Revision:    1 (<YYYY-MM-DD>)  
```