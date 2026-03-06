define 'expressions'

	define 'boolean'
		define 'false'
			it 'should accept #f as false/empty list' '#f' '()'
			it 'should accept () as false/empty list' '()' '()'
			it 'should accept '\''() as false/empty list' \''()' '()'

		define 'true'
			it 'should accept #t as true' '#t' '#t'

	define 'integer'
		define 'entry'
			it 'should accept positive integers' 99 99
			it 'should accept negative integers' -99 -99
			it 'should accept integers expressed as octal' 077 63
			it 'should accept integers expressed as hexadecimal' 0xff 255

	define 'string'
		define 'entry'
			it 'should return "rs" when "rs" entered' '"rs"' '"rs"'
			it 'should accept empty strings' '""' '""'

		define ''
			it 'should fetch single characters indexed from beginning of string' '("abc" 2)' '#\\c'
			it 'should fetch single characters indexed from end of string' '("abc" -1)' '#\\c'

	define 'list'

	define 'quote'
		it 'should evalute to <symbol> when given '\''<symbol>' \''a' 'a'
		it 'should evalute to <datum> when given '\''<datum>)' \''#(a b c)' '(vector a b c)'
		it 'should evalute to <datum> when given '\''<cons>' \''(+ 1 2)' '(+ 1 2)'

	define 'quasiquote'

	define 'unquote'

	define 'unquote-splicing'

	define 'vector'

	define 'char'
		it 'should evaluate character constants' '#\\a' '#\\a'

	define 'variable references'
		it 'should reference variables' '(define x 28)' 28

	define 'literal expressions'
		it 'should evalute to <datum> when given (quote <datum>)' '(quote a)' a
		it 'should evalute to <datum> when given (quote <datum>)' '(quote #(a b c))' '(vector a b c)'
		it 'should evalute to <datum> when given (quote <datum>)' '(quote (+ 1 2))' '(+ 1 2)'

define 'procedures'
	define 'addition'
		it 'should ignore an empty set' '(+)' '0'
		it 'should add a single value' '(+ 1)' '1'
		it 'should add two values' '(+ 2 1)' '3'
		it 'should add three values' '(+ 3 2 1)' '6'

	define 'subtraction'
		it 'should ignore an empty set' '(-)' '0'
		it 'should subtract a single value' '(- 1)' '1'
		it 'should subtract two values' '(- 2 1)' '1'
		it 'should subtract three values' '(- 3 2 1)' '0'

	define 'multiplication'
		it 'should ignore an empty set' '(*)' '0'
		it 'should multiply a single value' '(* 1)' '1'
		it 'should multiply two values' '(* 2 1)' '2'
		it 'should multiply three values' '(* 3 2 1)' '6'

	define 'division'
		it 'should ignore an empty set' '(/)' '0'
		it 'should subtract a single value' '(/ 1)' '1'
		it 'should subtract two values' '(/ 2 1)' '2'
		it 'should subtract three values' '(/ 3 2 1)' '1'

	define 'modulo'
		it 'should ignore an empty set' '(%)' '0'
		it 'should modulo a single value' '(% 1)' '1'
		it 'should modulo two values' '(% 1 2)' '1'
		it 'should modulo three values' '(% 1 2 3)' '1'

	define 'not'
		it 'should ignore an empty set' '(not)' '()'
		it 'should return false for true datum' '(not #t)' '()'
		it 'should return false for a non-false datum' '(not 0)' '()'
		it 'should ignore true for false datum' '(not #f)' '#t'
		it 'should ignore true for empty set' '(not '\''())' '#t'
