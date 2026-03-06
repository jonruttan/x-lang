Title:    Jon's Reflective Metacircular Lisp  
Subtitle: A minimalist, reflective, metacircular Lisp implemented in ANSI C  
Keywords: [#rl, #Reflective, #Metacircular, #Lisp, #Interpreter]  
Author:   "[Jon Ruttan](jonruttan@gmail.com)"  
Date:     2021-09-26  
Revision: 2 (2022-04-12)  
Syntax:   c  

# Jon's Reflective Metacircular Lisp Interpreter

## Key Goals

  - Minimal C code
  - Portable
  - ANSI C compliant
  - Architecture independent
  - Reflective
  - Metacircular
  - Able to replace interpreter code during runtime
  - No StdLib, no external dependencies
  - Fault Tolerant

## Purpose

Build a Lisp interpreter with the minimal amount of C code. The code should be portable, Ansi C compliant and able to run on any architecture which could feasibly run the interpreter. The interpreter should be able to replace its components while running. The interpreter is to be self-dependant and provide its own system libraries. The interpreter should be fault tolerant.

## Key Assumptions

Familiarity with Lisp is assumed.

## Quick Start

```bash
make
sudo make install
rl.sh
```

## Running Tests

```bash
make test
```