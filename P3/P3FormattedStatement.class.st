"
I am P3FormattedStatement, an SQL template with placeholders that, together with arguments, can be executed.

I am a tool to safely and more easily create SQL statements and queries that contain arguments. I know the correct textual representation of a set of primitive types. I do proper string escaping.

Since I know the client that created me, I can be executed autonomously.

You create instances of me by sending #format: to a P3Client instance.

For example,

	statement := client format: 'SELECT name, enabled FROM table1 WHERE id >= $1 ORDER BY id'.
	result := statement query: #( 345 ).

in the above 345 will be bound to (and replace) $1 in the SQL template.

The syntax that I use ($n) and my public API is mostly polymorphic with P3PreparedStatement. The difference is that I do simple string processing on the client without any interaction with the server.

"
Class {
	#name : 'P3FormattedStatement',
	#superclass : 'Object',
	#instVars : [
		'client',
		'source'
	],
	#category : 'P3-Core',
	#package : 'P3',
	#tag : 'Core'
}

{ #category : 'binding' }
P3FormattedStatement >> bind: arguments [
	"Build and return the actual SQL statement by splicing in the arguments for all placeholders in the template.
	Only a $ followed by digits outside string literals, quoted identifiers, dollar quoted strings,
	comments and identifiers is a placeholder. Everything else is copied as it is."

	| text |
	text := self source.
	^ String streamContents: [ :out | | index |
		index := 1.
		[ index <= text size ] whileTrue: [
			index := self copyTokenFrom: text at: index to: out arguments: arguments ] ]
]

{ #category : 'initialization' }
P3FormattedStatement >> client: aP3Client [
	client := aP3Client
]

{ #category : 'public' }
P3FormattedStatement >> close [
]

{ #category : 'private' }
P3FormattedStatement >> copyBlockCommentFrom: text at: start to: out [
	"Copy a /* */ comment. These comments nest. An unfinished comment runs to the end of the text.
	Answer the index after the comment."

	| index depth |
	out nextPutAll: '/*'.
	index := start + 2.
	depth := 1.
	[ index <= text size and: [ depth > 0 ] ] whileTrue: [
		| char next |
		char := text at: index.
		next := text at: index + 1 ifAbsent: [ nil ].
		(char = $/ and: [ next = $* ])
			ifTrue: [
				depth := depth + 1.
				out nextPutAll: '/*'.
				index := index + 2 ]
			ifFalse: [
				(char = $* and: [ next = $/ ])
					ifTrue: [
						depth := depth - 1.
						out nextPutAll: '*/'.
						index := index + 2 ]
					ifFalse: [
						out nextPut: char.
						index := index + 1 ] ] ].
	^ index
]

{ #category : 'private' }
P3FormattedStatement >> copyDollarTokenFrom: text at: start to: out arguments: arguments [
	"The token at start begins with a $. It is a placeholder when digits follow, the opening tag of a
	dollar quoted string when a tag and a second $ follow, and a plain character otherwise.
	Answer the index after the token."

	| index next close |
	next := text at: start + 1 ifAbsent: [ nil ].
	(next notNil and: [ next isDigit ])
		ifTrue: [
			index := start + 1.
			[ index <= text size and: [ (text at: index) isDigit ] ] whileTrue: [ index := index + 1 ].
			((arguments at: (text copyFrom: start + 1 to: index - 1) asInteger)
				p3PrintUsing: self on: out).
			^ index ].
	index := start + 1.
	(next notNil and: [ self isIdentifierStart: next ])
		ifTrue: [
			[ index <= text size and: [ self isTagPart: (text at: index) ] ] whileTrue: [ index := index + 1 ] ].
	(index <= text size and: [ (text at: index) = $$ ])
		ifFalse: [
			out nextPut: $$.
			^ start + 1 ].
	"The tag is the opening $tag$. The string ends at the next equal tag."
	close := text indexOfSubCollection: (text copyFrom: start to: index) startingAt: index + 1.
	close = 0 ifTrue: [
		out nextPutAll: (text copyFrom: start to: text size).
		^ text size + 1 ].
	out nextPutAll: (text copyFrom: start to: close + (index - start)).
	^ close + (index - start) + 1
]

{ #category : 'private' }
P3FormattedStatement >> copyLineCommentFrom: text at: start to: out [
	"Copy a -- comment up to, but not including, the end of the line. Answer the index of the line end."

	| index |
	index := start.
	[ index <= text size and: [ (text at: index) ~= Character lf and: [ (text at: index) ~= Character cr ] ] ]
		whileTrue: [
			out nextPut: (text at: index).
			index := index + 1 ].
	^ index
]

{ #category : 'private' }
P3FormattedStatement >> copyQuotedFrom: text at: start to: out escapes: aBoolean [
	"Copy a literal or a quoted identifier. A doubled quote stays inside. When aBoolean is true,
	a backslash escapes the next character, as in an E'..' string. Answer the index after the closing quote."

	| quote index char |
	quote := text at: start.
	out nextPut: quote.
	index := start + 1.
	[ index <= text size ] whileTrue: [
		char := text at: index.
		out nextPut: char.
		index := index + 1.
		(aBoolean and: [ char = $\ ])
			ifTrue: [
				index <= text size ifTrue: [
					out nextPut: (text at: index).
					index := index + 1 ] ]
			ifFalse: [
				char = quote ifTrue: [
					(index <= text size and: [ (text at: index) = quote ])
						ifTrue: [
							out nextPut: quote.
							index := index + 1 ]
						ifFalse: [ ^ index ] ] ] ].
	^ index
]

{ #category : 'private' }
P3FormattedStatement >> copyTokenFrom: text at: index to: out arguments: arguments [
	"Copy the token that starts at index to out, writing the argument for a placeholder.
	Answer the index of the first character after the token."

	| char next |
	char := text at: index.
	next := text at: index + 1 ifAbsent: [ nil ].
	(char = $' or: [ char = $" ])
		ifTrue: [ ^ self copyQuotedFrom: text at: index to: out escapes: false ].
	(char = $- and: [ next = $- ])
		ifTrue: [ ^ self copyLineCommentFrom: text at: index to: out ].
	(char = $/ and: [ next = $* ])
		ifTrue: [ ^ self copyBlockCommentFrom: text at: index to: out ].
	char = $$
		ifTrue: [ ^ self copyDollarTokenFrom: text at: index to: out arguments: arguments ].
	(self isIdentifierStart: char)
		ifTrue: [ ^ self copyWordFrom: text at: index to: out ].
	out nextPut: char.
	^ index + 1
]

{ #category : 'private' }
P3FormattedStatement >> copyWordFrom: text at: start to: out [
	"Copy an identifier or a keyword. A $ and digits belong to it. A lone E or e directly before a
	quote starts an escape string, in which a backslash escapes the next character.
	Answer the index after the token."

	| index word |
	index := start.
	[ index <= text size and: [ self isIdentifierPart: (text at: index) ] ] whileTrue: [ index := index + 1 ].
	word := text copyFrom: start to: index - 1.
	out nextPutAll: word.
	(word size = 1 and: [ word first asLowercase = $e and: [ index <= text size and: [ (text at: index) = $' ] ] ])
		ifTrue: [ ^ self copyQuotedFrom: text at: index to: out escapes: true ].
	^ index
]

{ #category : 'public' }
P3FormattedStatement >> execute: arguments [
	"Bind the arguments given to the placeholders in my SQL template and
	execute this statement using my client, returning the result"

	^ client execute: (self bind: arguments)
]

{ #category : 'executing' }
P3FormattedStatement >> executeBatch: argumentsCollection [
	"Bind each set of arguments from the argumentsCollection given
	to the placeholders in my SQL template and execute this statement using my client,
	returning the collection of results. The batch is atomic: when a set fails, the sets before it
	are rolled back. When my client is already in a transaction, that transaction decides."

	| ownTransaction |
	ownTransaction := client transactionStatus ~= $T and: [ client transactionStatus ~= $E ].
	ownTransaction ifTrue: [ client execute: 'BEGIN' ].
	^ [ | results |
		results := argumentsCollection collect: [ :each | self execute: each ].
		ownTransaction ifTrue: [ client execute: 'COMMIT' ].
		results ]
		on: Error
		do: [ :error |
			ownTransaction ifTrue: [ [ client execute: 'ROLLBACK' ] on: Error do: [ :ignored | nil ] ].
			error pass ]
]

{ #category : 'private' }
P3FormattedStatement >> isIdentifierPart: aCharacter [
	^ (self isIdentifierStart: aCharacter) or: [ aCharacter isDigit or: [ aCharacter = $$ ] ]
]

{ #category : 'private' }
P3FormattedStatement >> isIdentifierStart: aCharacter [
	^ aCharacter isLetter or: [ aCharacter = $_ or: [ aCharacter asInteger > 127 ] ]
]

{ #category : 'private' }
P3FormattedStatement >> isTagPart: aCharacter [
	"A dollar quote tag has no $ in it."

	^ (self isIdentifierStart: aCharacter) or: [ aCharacter isDigit ]
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printBitString: bitString on: stream [
	"Use the B'0101' syntax for bit strings"
	
	stream nextPut: $B; nextPut: $'; print: bitString; nextPut: $'
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printByteArray: byteArray on: stream [
	"Use the bytea Hex Format for bytes (ByteArray), as in E'\\xDEADBEEF'.
	The backslash is doubled, so the text reads the same whatever the standard_conforming_strings setting is."

	| hex |
	stream nextPutAll: 'E''\\x'.
	hex := '0123456789ABCDEF'.
	byteArray do: [ :byte |
		stream
			nextPut: (hex at: (byte bitShift: -4) + 1);
			nextPut: (hex at: (byte bitAnd: 15) + 1) ].
	stream nextPut: $'
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printDate: date on: stream [
	"Use ISO 8601 YYYY-MM-DD"
	
	stream nextPut: $'.
	date printOn: stream format: #(3 2 1 $- 1 1 2).
	stream nextPut: $'
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printDateAndTime: dateAndTime on: stream [
	"Use ISO 8601 YYYY-MM-DDThh:mm:ss.s+ZZ:zz"
	
	stream nextPut: $'.
	dateAndTime printOn: stream.
	stream nextPut: $' 
]

{ #category : 'printing' }
P3FormattedStatement >> printFloat: float on: stream [
	self printNumber: float on: stream
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printGeometricObject: geometricObject on: stream [
	"Delegate to P3GeometricObject that knows how to print itself in typed quoted PSQL text format"
	
	geometricObject printPsqlOn: stream
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printInterval: interval on: stream [
	"Delegate partially to P3Interval that knows how to print itself in postgresql style"
	
	stream nextPutAll: #interval; space; nextPut: $'; print: interval; nextPut: $'
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printNullOn: stream [
	"nil becomes NULL"
	
	stream nextPutAll: 'NULL'
]

{ #category : 'printing' }
P3FormattedStatement >> printNumber: number on: stream [
	"A negative number is written in parentheses, so a preceding minus sign cannot make a -- comment
	and a preceding operator character cannot join with the sign.
	A fraction is a division of two numerics, since an integer division would round it.
	A negative zero is a float8 text, because a numeric literal has no negative zero."

	number isInteger ifTrue: [ ^ self printSigned: number printString on: stream ].
	number isFraction ifTrue: [
		stream nextPut: $(.
		self printSigned: number numerator printString on: stream.
		stream nextPutAll: '::numeric/'.
		self printSigned: number denominator printString on: stream.
		^ stream nextPutAll: '::numeric)' ].
	number isFloat ifTrue: [
		number isNaN ifTrue: [ ^ stream nextPutAll: '''NaN''::float8' ].
		number isInfinite ifTrue: [
			^ stream nextPutAll: (number > 0 ifTrue: [ '''Infinity''::float8' ] ifFalse: [ '''-Infinity''::float8' ]) ].
		(number isZero and: [ number printString first = $- ]) ifTrue: [ ^ stream nextPutAll: '''-0''::float8' ] ].
	^ self printSigned: number printString on: stream
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printObject: object on: stream [
	"Numbers, booleans, characters and UUIDs have an SQL text. Any other object has none:
	its print string is not SQL, so it is refused."

	object isNumber ifTrue: [ ^ self printNumber: object on: stream ].
	(object == true or: [ object == false ]) ifTrue: [ ^ object printOn: stream ].
	object isCharacter ifTrue: [ ^ self printString: (String with: object) on: stream ].
	(object isKindOf: UUID) ifTrue: [ ^ self printString: object printString on: stream ].
	^ (P3Error cannotFormatObject: object) signal
]

{ #category : 'printing' }
P3FormattedStatement >> printOn: stream [
	super printOn: stream.
	stream nextPut: $(; << source; nextPut: $)
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printScaledDecimal: scaledDecimal on: stream [
	"For ScaledDecimals, use a regular floating point like representation"

	self
		printSigned: (String streamContents: [ :text |
			scaledDecimal
				printOn: text
				showingDecimalPlaces: scaledDecimal scale ])
		on: stream
]

{ #category : 'private' }
P3FormattedStatement >> printSigned: numberText on: stream [
	"Write numberText, in parentheses when it starts with a minus sign."

	(numberText notEmpty and: [ numberText first = $- ])
		ifTrue: [ stream nextPut: $(; nextPutAll: numberText; nextPut: $) ]
		ifFalse: [ stream nextPutAll: numberText ]
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printString: string on: stream [
	"For strings use single quotes and the doubling of single quotes when they are part of the string.
	A string with a backslash is written as an E'..' string with the backslash doubled, which reads the
	same whatever the standard_conforming_strings setting is."

	| hasBackslash |
	hasBackslash := string includes: $\.
	hasBackslash ifTrue: [ stream nextPut: $E ].
	stream nextPut: $'.
	string do: [ :each |
		(each = $' or: [ each = $\ ]) ifTrue: [ stream nextPut: each ].
		stream nextPut: each ].
	stream nextPut: $'
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printTime: time on: stream [
	"Use ISO 8601 hh:mm:ss, followed by the fraction of the second when there is one."

	stream nextPut: $'.
	time print24: true on: stream.
	time nanoSecond > 0 ifTrue: [
		stream
			nextPut: $.;
			nextPutAll: ((time nanoSecond printPaddedWith: $0 to: 9) trimRight: [ :each | each = $0 ]) ].
	stream nextPut: $'
]

{ #category : 'printing-dispatched' }
P3FormattedStatement >> printValuesArray: valuesArray on: stream [
	| first |
	valuesArray isEmpty 
		ifTrue: [ ^ stream nextPutAll: '''{}''' ]. "prevent untyped empty array error"
	first := true.
	stream nextPutAll: #array.
	stream nextPut: $[.
	valuesArray do: [ :each |
		first ifTrue: [ first := false ] ifFalse: [ stream nextPut: $, ].
		each p3PrintUsing: self on: stream ].
	stream nextPut: $]
]

{ #category : 'public' }
P3FormattedStatement >> query: arguments [
	"Bind the arguments given to the placeholders in my SQL template and
	execute this query using my client, returning the result"
	
	^ client query: (self bind: arguments)
]

{ #category : 'public' }
P3FormattedStatement >> queryAll: argumentsCollection [
	"Bind each set of arguments from the argumentsCollection given
	to the placeholders in my SQL template and execute this query using my client, 
	returning the collection of results"

	^ argumentsCollection collect: [ :each | self query: each ]
]

{ #category : 'accessing' }
P3FormattedStatement >> source [
	"Return my SQL source"
	
	^ source
]

{ #category : 'initialization' }
P3FormattedStatement >> sql: anSQLTemplateString [
	source := anSQLTemplateString 
]
