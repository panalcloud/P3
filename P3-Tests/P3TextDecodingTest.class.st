"
I test how text values and column names are decoded from UTF-8.

A value reads as the text the server holds. It is a ByteString when all its characters fit in one byte, and a WideString otherwise, whatever was read before it. Decoding a value consumes exactly its bytes, so the next column reads from the right place. Bytes that are not valid UTF-8 signal the error of the character encoder.

The server tests cover every character up to U+FFFF except the surrogates, characters of four bytes, characters at the start, end and middle of a value, and long values. The tests on bytes cover what a server never sends, invalid UTF-8.
"
Class {
	#name : 'P3TextDecodingTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3TextDecodingTest >> decode: bytes [
	"Decode all of bytes as a text value, with the converter of a new client"

	^ P3Converter new convertStringFrom: bytes readStream length: bytes size description: nil
]

{ #category : 'private' }
P3TextDecodingTest >> readText: sqlExpression [
	^ (client query: 'SELECT ' , sqlExpression) firstFieldOfFirstRecord
]

{ #category : 'private' }
P3TextDecodingTest >> stringOfCodePoints: anInterval [
	^ String withAll: (anInterval collect: [ :each | Character value: each ])
]

{ #category : 'tests' }
P3TextDecodingTest >> testAsciiText [
	| text |
	text := self readText: '''abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789''::text'.
	self assert: text equals: 'abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789'.
	self assert: text class equals: ByteString
]

{ #category : 'tests' }
P3TextDecodingTest >> testClassOfEachValueDependsOnItsOwnCharacters [
	"A value with a character beyond U+00FF does not make the values read after it wide"

	| values |
	values := (client query: 'SELECT v FROM (VALUES (1, ''€''), (2, ''abc''), (3, ''ñá''), (4, ''—'')) AS t(i, v) ORDER BY i') data
		collect: [ :each | each first ].
	self assert: values equals: #( '€' 'abc' 'ñá' '—' ).
	self
		assert: (values collect: [ :each | each class ])
		equals: { WideString. ByteString. ByteString. WideString }
]

{ #category : 'tests' }
P3TextDecodingTest >> testColumnNamesWithNonAsciiCharacters [
	self
		assert: ((client query: 'SELECT 1 AS "año", 2 AS "€ total"') descriptions collect: [ :each | each fieldName ])
		equals: #( 'año' '€ total' )
]

{ #category : 'tests' }
P3TextDecodingTest >> testDecodingConsumesExactlyTheBytesOfTheValue [
	| bytes stream |
	bytes := 'ñ€a' utf8Encoded , #[ 1 2 3 ].
	stream := bytes readStream.
	self
		assert: (P3Converter new convertStringFrom: stream length: bytes size - 3 description: nil)
		equals: 'ñ€a'.
	self assert: stream upToEnd equals: #[ 1 2 3 ]
]

{ #category : 'tests' }
P3TextDecodingTest >> testEmptyText [
	self assert: (self readText: '''''::text') equals: ''
]

{ #category : 'tests' }
P3TextDecodingTest >> testEveryCharacterUpToU0FFFF [
	"Every character from U+0100 to U+FFFF, two-byte and three-byte UTF-8 sequences, except the
	surrogates, which are not characters, and U+FEFF, which the encoder skips as a byte order mark"

	| text expected |
	text := self readText: '(SELECT string_agg(chr(i), '''' ORDER BY i) FROM generate_series(256, 65535) i WHERE i NOT BETWEEN 55296 AND 57343 AND i <> 65279)'.
	expected := (self stringOfCodePoints: (256 to: 55295)) , (self stringOfCodePoints: (57344 to: 65278)) , (self stringOfCodePoints: (65280 to: 65535)).
	self assert: text size equals: expected size.
	self assert: text equals: expected.
	self assert: text class equals: WideString
]

{ #category : 'tests' }
P3TextDecodingTest >> testEveryOneByteCharacter [
	"Every character from U+0001 to U+00FF, ASCII and two-byte UTF-8 sequences, in one value"

	| text |
	text := self readText: '(SELECT string_agg(chr(i), '''' ORDER BY i) FROM generate_series(1, 255) i)'.
	self assert: text equals: (self stringOfCodePoints: (1 to: 255)).
	self assert: text class equals: ByteString
]

{ #category : 'tests' }
P3TextDecodingTest >> testFourByteCharacters [
	self
		assert: (self readText: '''x'' || chr(128512) || ''y'' || chr(1114111)')
		equals: 'x' , (String with: (Character value: 128512)) , 'y' , (String with: (Character value: 1114111))
]

{ #category : 'tests' }
P3TextDecodingTest >> testInvalidUtf8SignalsTheErrorOfTheEncoder [
	"A truncated sequence, an overlong one, a surrogate, a byte that cannot start a sequence, and a
	continuation byte without a start"

	self should: [ self decode: #[ 16r61 16rC3 ] ] raise: ZnIncomplete.
	self should: [ self decode: #[ 16rC0 16r80 ] ] raise: ZnInvalidUTF8.
	self should: [ self decode: #[ 16rED 16rA0 16r80 ] ] raise: ZnInvalidUTF8.
	self should: [ self decode: #[ 16r61 16rFF ] ] raise: ZnInvalidUTF8.
	self should: [ self decode: #[ 16r80 16r61 ] ] raise: ZnInvalidUTF8
]

{ #category : 'tests' }
P3TextDecodingTest >> testLargeText [
	| text |
	text := self readText: 'repeat(''abcdefghij'', 100000) || ''ñ'''.
	self assert: text size equals: 1000001.
	self assert: (text first: 10) equals: 'abcdefghij'.
	self assert: text last equals: $ñ.
	self assert: text class equals: ByteString
]

{ #category : 'tests' }
P3TextDecodingTest >> testNonAsciiCharacterAfterALongAsciiRun [
	| text |
	text := self readText: 'repeat(''a'', 5000) || ''é'' || repeat(''b'', 3)'.
	self assert: text size equals: 5004.
	self assert: (text at: 5000) equals: $a.
	self assert: (text at: 5001) equals: $é.
	self assert: (text last: 3) equals: 'bbb'
]

{ #category : 'tests' }
P3TextDecodingTest >> testNonAsciiCharactersAtTheStartTheEndAndNextToEachOther [
	#( 'ñ' 'ñx' 'xñ' 'ññ' 'ñáéíóú' 'añbécíd' 'x€' '€x' '€€ñ' ) do: [ :each |
		self
			assert: (client query: 'SELECT ''' , each , '''::text') firstFieldOfFirstRecord
			equals: each ]
]

{ #category : 'tests' }
P3TextDecodingTest >> testTextIsFollowedByTheNextColumn [
	self
		assert: (client query: 'SELECT ''ñá€'' || chr(128512), 42::int4, ''z''::text, ''é''::text, 7::int4') firstRecord
		equals: { 'ñá€' , (String with: (Character value: 128512)). 42. 'z'. 'é'. 7 }
]
