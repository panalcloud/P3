"
P3ArrayParameterTest holds unit tests for binding a collection as one array parameter of a prepared statement: the text of the array literal that P3MessageBuilder writes, and the round trip of that literal through the server.

An element of an array literal is not a scalar parameter: a comma, a brace, a double quote, a backslash, leading or trailing whitespace, an empty string and the text NULL all change the shape of the array unless the element is quoted and escaped. Every test here pins one of those.

I reuse the configuration of P3ClientTest. Example:

  P3ClientTest url: 'psql://sven:secret@localhost:5432/database'.

I create no tables, so I run without the server sending a NoticeResponse.
"
Class {
	#name : 'P3ArrayParameterTest',
	#superclass : 'TestCase',
	#instVars : [
		'client'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3ArrayParameterTest >> arrayLiteralFor: aCollection [
	"Answer the parameter text that P3MessageBuilder writes for aCollection, without the
	4 byte size prefix of a Bind parameter. No server is involved."

	| builder |
	builder := P3MessageBuilder newWithEncoder: ZnUTF8Encoder new.
	builder nextPutParameterAsText: aCollection description: nil.
	^ (builder asBytes allButFirst: 4) utf8Decoded
]

{ #category : 'private' }
P3ArrayParameterTest >> firstElementOf: aCollection as: aTypeName [
	"Bind aCollection as an array parameter of aTypeName and answer its first element as read
	back by the server. Used for element types whose array type P3Converter does not map."

	^ self select: 'SELECT ($1::' , aTypeName , ')[1]' bind: aCollection
]

{ #category : 'private' }
P3ArrayParameterTest >> roundTrip: aCollection as: aTypeName [
	"Bind aCollection as a single array parameter of aTypeName and answer the array the
	server reads back from it."

	^ self select: 'SELECT $1::' , aTypeName bind: aCollection
]

{ #category : 'private' }
P3ArrayParameterTest >> select: sqlTemplate bind: aValue [
	"Prepare sqlTemplate, run it with aValue bound to $1 and answer the single value read back."

	| statement result |
	statement := client prepare: sqlTemplate.
	[ result := statement query: { aValue } ] ensure: [ statement close ].
	^ result firstFieldOfFirstRecord
]

{ #category : 'running' }
P3ArrayParameterTest >> setUp [
	super setUp.
	client := P3Client new.
	client url: P3ClientTest url.
	client timeout: 10. "second"
	client connect
]

{ #category : 'running' }
P3ArrayParameterTest >> tearDown [
	client close.
	super tearDown
]

{ #category : 'tests-literal' }
P3ArrayParameterTest >> testArrayLiteralEscapesQuoteAndBackslash [
	"Inside a quoted element a double quote and a backslash are the only two characters
	that need a backslash before them."

	self
		assert: (self arrayLiteralFor: { 'say "hi"'. 'a\b' })
		equals: '{"say \"hi\"","a\\b"}'
]

{ #category : 'tests-literal' }
P3ArrayParameterTest >> testArrayLiteralOfEmptyCollection [
	"An empty collection is the empty array, which is not the same as an array holding one
	empty element."

	self assert: (self arrayLiteralFor: #( )) equals: '{}'.
	self assert: (self arrayLiteralFor: #( '' )) equals: '{""}'
]

{ #category : 'tests-literal' }
P3ArrayParameterTest >> testArrayLiteralOfNestedCollections [
	"A nested collection is a sub-array: it keeps its braces and is not quoted."

	self
		assert: (self arrayLiteralFor: #( #( 1 2 ) #( 3 4 ) ))
		equals: '{{"1","2"},{"3","4"}}'
]

{ #category : 'tests-literal' }
P3ArrayParameterTest >> testArrayLiteralQuotesElements [
	"Every element is quoted, so a comma inside an element stays part of that element
	instead of separating two of them."

	self assert: (self arrayLiteralFor: #( 'a,b' 'c' )) equals: '{"a,b","c"}'
]

{ #category : 'tests-literal' }
P3ArrayParameterTest >> testArrayLiteralWritesNilAsNull [
	"nil is the null element and is written unquoted, since a quoted NULL is the text 'NULL'."

	self assert: (self arrayLiteralFor: #( 1 nil 3 )) equals: '{"1",NULL,"3"}'
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testByteaArrayElementRoundTrips [
	"The bytea hex format starts with a backslash, which an array literal reads as an escape
	unless the element is quoted and the backslash doubled."

	| bytes |
	bytes := #[ 1 2 92 255 ].
	self assert: (self firstElementOf: { bytes } as: 'bytea[]') equals: bytes
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testDateArrayElementRoundTrips [
	"A scalar date parameter carries single quotes, which are part of the value inside an
	array literal and must not be written there."

	| date |
	date := Date newDay: 31 month: 1 year: 2024.
	self assert: (self firstElementOf: { date } as: 'date[]') equals: date
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testEmptyTextArrayRoundTrips [
	"An empty collection is an array of zero elements."

	self assert: (self roundTrip: #( ) as: 'text[]') equals: #( )
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testIntegerArrayWithNilRoundTrips [
	"A nil element is bound as the null element instead of failing to print."

	| array |
	array := #( 1 nil 3 ).
	self assert: (self roundTrip: array as: 'int4[]') equals: array
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testNestedIntegerArrayRoundTrips [
	"Quoting elements must not quote a nested array, which is structure and not a value."

	| array |
	array := #( #( 1 2 ) #( 3 4 ) ).
	self assert: (self roundTrip: array as: 'int4[]') equals: array
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testTextArrayWithEmptyStringRoundTrips [
	"An empty element keeps its place in the array."

	| array |
	array := #( '' 'x' '' ).
	self assert: (self roundTrip: array as: 'text[]') equals: array
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testTextArrayWithNullTextRoundTrips [
	"The text 'NULL' is a value, not the null element."

	| array |
	array := #( 'NULL' 'null' ).
	self assert: (self roundTrip: array as: 'text[]') equals: array
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testTextArrayWithQuotesBackslashesAndWhitespaceRoundTrips [
	"A double quote, a backslash and surrounding whitespace survive the literal."

	| array |
	array := { 'say "hi"'. 'a\b'. ' x '. 'two words' }.
	self assert: (self roundTrip: array as: 'text[]') equals: array
]

{ #category : 'tests-round trip' }
P3ArrayParameterTest >> testTextArrayWithSeparatorsRoundTrips [
	"An element holding a comma or a brace must come back as one element, not as several."

	| array |
	array := #( 'a,b' 'c' '{d}' '}' ).
	self assert: (self roundTrip: array as: 'text[]') equals: array
]
