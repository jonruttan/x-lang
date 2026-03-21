Title:       X-Lang Project Notes  
Description: Development notes for X-Lang.  
Keywords:    [#X, #X-Lang, #Project, #Notes]  
Author:      "[Jon Ruttan](jonruttan@gmail.com)"  
Date:        2021-10-06  
Revision:    6 (2026-03-21)  

# X-Lang Project Notes

## Sub-projects

### X-Expressions (x-expr) -- Computational Expressions Library

- Simple
- Minimalist
- Thread-safe
- Dynamic type system
- Type specific evaluators
- Multiple independent environments
- Metacircular evaluator
- Reflective
- ANSI / Standard C
- No external dependencies


### X-Lang (x-lang) -- Minimalist Dialect

Foundational / Scripting

- Simple
- Minimalist
- Thread-safe
- Lisp1
- Metacircular evaluator
- Dynamic type system
- Type specific evaluators
- Reflective
- Multiple independent environments
- Embeddable
- Bootstrap/library
- ANSI / Standard C
- No external dependencies


### X/OR (x-or) -- Midsize/Unstable Dialect

Experimental / Hacking

- Built on X-Lang
- Unstable
- Full Dialect
- Kernel access
- Compiler
- Modules


### X/AND (x-and) -- Maximal/Stable X-Lang Dialect

Hardened / Full Stack

- Built on X-Lang
- Stable
- Lisp1
- Full Dialect
- Kernel access
- Compiler
- Modules
- Hardened


### X-Tools System Tools

- Built with X-Pro Lisp

- Document generator
- Package manager(s)
- Editor
- Make
- C Compiler