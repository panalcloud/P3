"
I test how integer values are read: int2, int4, int8 and the catalog integer types oid, xid and cid, from their smallest to their largest value. The limits of int8 are LargeIntegers in Pharo. Reading a value consumes exactly its bytes, so the next column reads from the right place.
"
Class {
	#name : 'P3IntegerDecodingTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3IntegerDecodingTest >> read: sqlExpression [
	^ (client query: 'SELECT ' , sqlExpression) firstFieldOfFirstRecord
]

{ #category : 'tests' }
P3IntegerDecodingTest >> testCatalogIntegerTypes [
	self assert: (self read: '4294967295::oid') equals: 4294967295.
	self assert: (self read: '0::oid') equals: 0.
	self assert: (self read: '''123''::xid') equals: 123.
	self assert: (self read: '''7''::cid') equals: 7
]

{ #category : 'tests' }
P3IntegerDecodingTest >> testDecodingConsumesExactlyTheBytesOfTheValue [
	| bytes stream |
	bytes := '-4711' asByteArray , #[ 1 2 3 ].
	stream := bytes readStream.
	self
		assert: (P3Converter new convertIntegerFrom: stream length: 5 description: nil)
		equals: -4711.
	self assert: stream upToEnd equals: #[ 1 2 3 ]
]

{ #category : 'tests' }
P3IntegerDecodingTest >> testIntegerIsFollowedByTheNextColumn [
	self
		assert: (client query: 'SELECT (-123)::int4, 9223372036854775807::int8, NULL::int2, ''x''::text, 42::int2') firstRecord
		equals: #( -123 9223372036854775807 nil 'x' 42 )
]

{ #category : 'tests' }
P3IntegerDecodingTest >> testLimitsOfEachIntegerType [
	{
		'(-32768)::int2' -> -32768. '32767::int2' -> 32767.
		'(-2147483648)::int4' -> -2147483648. '2147483647::int4' -> 2147483647.
		'(-9223372036854775808)::int8' -> -9223372036854775808. '9223372036854775807::int8' -> 9223372036854775807.
		'0::int2' -> 0. '0::int4' -> 0. '0::int8' -> 0. '(-1)::int4' -> -1. '1::int8' -> 1 }
		do: [ :each | self assert: (self read: each key) equals: each value ]
]

{ #category : 'tests' }
P3IntegerDecodingTest >> testRangeOfValues [
	"Values of every number of digits and both signs"

	| result expected |
	result := client query: 'SELECT (s * i)::int8 FROM generate_series(0, 18) e, LATERAL (SELECT (10::numeric ^ e)::int8 + e AS i) v, (VALUES (1), (-1)) AS t(s) ORDER BY e, s'.
	expected := (0 to: 18) flatCollect: [ :e | | i | i := (10 raisedTo: e) + e. { i negated. i } ].
	self assert: (result data collect: [ :each | each first ]) asArray equals: expected asArray
]
