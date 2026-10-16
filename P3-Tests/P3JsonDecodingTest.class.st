"
I test how json and jsonb values are read: with NeoJSONReader, objects as NeoJSONObject with Symbols as keys, lists as Arrays, and every scalar as a value of its own. The server keeps the text of a json value as it was written, whitespace included, while jsonb is written again by the server; reading either consumes exactly the bytes of the value. The same key in different values is the same Symbol.
"
Class {
	#name : 'P3JsonDecodingTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3JsonDecodingTest >> read: jsonText as: typeName [
	"Answer the value of jsonText cast to typeName (json or jsonb) by the server"

	^ (client query: 'SELECT ''' , (jsonText copyReplaceAll: '''' with: '''''') , '''::' , typeName) firstFieldOfFirstRecord
]

{ #category : 'tests' }
P3JsonDecodingTest >> testKeysAreSymbols [
	#( 'json' 'jsonb' ) do: [ :type | | value |
		value := self read: '{"name": 1, "año": 2, "123": 3, "a b": 4, "": 5}' as: type.
		self assert: (value keys allSatisfy: [ :each | each isSymbol ]).
		self assert: (value keys asSet) equals: (Set withAll: #( #name #'año' #'123' #'a b' #'' )).
		self assert: (value at: #'año') equals: 2.
		self assert: (value at: #'123') equals: 3 ]
]

{ #category : 'tests' }
P3JsonDecodingTest >> testManyDistinctKeys [
	"An object with more keys than a reader would want to remember, read twice"

	| result |
	result := client query: 'SELECT json_object_agg(''key'' || i, i) FROM generate_series(1, 5000) i UNION ALL SELECT json_object_agg(''key'' || i, -i) FROM generate_series(1, 5000) i'.
	result data withIndexDo: [ :row :index | | value |
		value := row first.
		self assert: value size equals: 5000.
		self assert: (value at: #key1) equals: (index = 1 ifTrue: [ 1 ] ifFalse: [ -1 ]).
		self assert: (value at: #key5000) equals: (index = 1 ifTrue: [ 5000 ] ifFalse: [ -5000 ]).
		self assert: (value keys allSatisfy: [ :each | each isSymbol ]) ]
]

{ #category : 'tests' }
P3JsonDecodingTest >> testObjectsAndListsNested [
	#( 'json' 'jsonb' ) do: [ :type | | value |
		value := self read: '{"id": 1, "tags": ["a", [], {}], "address": {"zip": "06000", "lines": [1, 2.5, null, true]}, "empty": {}}' as: type.
		self assert: value class equals: NeoJSONObject.
		self assert: (value at: #id) equals: 1.
		self assert: (value at: #tags) first equals: 'a'.
		self assert: (value at: #tags) second equals: #().
		self assert: (value at: #tags) third class equals: NeoJSONObject.
		self assert: (value at: #tags) third isEmpty.
		self assert: ((value at: #address) at: #zip) equals: '06000'.
		self assert: ((value at: #address) at: #lines) equals: #( 1 2.5 nil true ).
		self assert: (value at: #empty) isEmpty ].
	self assert: (self read: '[]' as: 'json') equals: #().
	self assert: (self read: '{}' as: 'json') class equals: NeoJSONObject
]

{ #category : 'tests' }
P3JsonDecodingTest >> testScalarValues [
	#( 'json' 'jsonb' ) do: [ :type |
		{ '12' -> 12. '-7' -> -7. '1.5' -> 1.5. '1e3' -> 1000.0. '-2.5E-2' -> -0.025.
		  '12345678901234567890123' -> 12345678901234567890123.
		  'true' -> true. 'false' -> false. 'null' -> nil. '"text"' -> 'text'. '""' -> '' }
			do: [ :each | self assert: (self read: each key as: type) equals: each value ] ]
]

{ #category : 'tests' }
P3JsonDecodingTest >> testStringsWithEscapesAndNonAsciiCharacters [
	| expected |
	expected := 'tab' , (String with: Character tab) , 'quote" backslash\ slash/ é ' , (String with: (Character value: 128512)) , ' ñ €'.
	#( 'json' 'jsonb' ) do: [ :type |
		self
			assert: (self read: '"tab\tquote\" backslash\\ slash\/ é 😀 ñ €"' as: type)
			equals: expected.
		self
			assert: ((self read: '{"kéy": "€"}' as: type) at: #'kéy')
			equals: '€' ]
]

{ #category : 'tests' }
P3JsonDecodingTest >> testTheSameKeyIsTheSameSymbol [
	| values |
	values := (client query: 'SELECT json_build_object(''name'', i, ''nombre_único'', i) FROM generate_series(1, 3) i') data
		collect: [ :each | each first ].
	values do: [ :each |
		self assert: (each keys detect: [ :key | key = #name ]) == #name.
		self assert: (each keys detect: [ :key | key = #'nombre_único' ]) == #'nombre_único' ]
]

{ #category : 'tests' }
P3JsonDecodingTest >> testWhitespaceAroundAValueAndTheNextColumn [
	"json keeps the text as written, so the value may have whitespace before and after it"

	| record |
	record := (client query: 'SELECT ''  {"a": 1}   ''::json, 42, e''[1, 2]\n ''::json, ''x'', ''12 ''::json, 7, ''{"b": [ 1 ] }''::jsonb, 8') firstRecord.
	self assert: (record first at: #a) equals: 1.
	self assert: record allButFirst equals: { 42. #( 1 2 ). 'x'. 12. 7. record seventh. 8 }.
	self assert: (record seventh at: #b) equals: #( 1 )
]
