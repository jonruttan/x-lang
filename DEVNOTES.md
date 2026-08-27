Title:       x-lang Development Notes  
Description: Development notes for x-lang.  
Keywords:    [#x-lang, #Dev, #Notes]  
Author:      "[Jon Ruttan](jonruttan@gmail.com)"  
Date:        2021-10-05  
Revision:    7 (2026-08-27)  

# Notes

## Filenames

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


### Alternates

***QR Alphanumeric***

Full set:

```regex
[- $%*+./:0-9A-Z]*
```

Filenames:

```regex
[0-9A-Z][-.0-9A-Z]*
```

---


## Engine notes moved out

The object/heap notes and the C spec-harness notes that used to live here
describe the engine, and moved to
[x-engine-c](https://github.com/jonruttan/x-engine-c) when it was split into
its own repository.
