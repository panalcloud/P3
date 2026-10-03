"
I test how P3Converter reads column types it has no converter for. Such a value is answered as the text the server sent, and the connection stays usable. Standard array types are converted element by element.
"
Class {
	#name : 'P3UnknownTypeTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests' }
P3UnknownTypeTest >> testStandardArrayTypesAreConverted [
	| record |
	record := (client query: 'SELECT ARRAY[1,2]::int2[], ARRAY[3,4]::int8[], ARRAY[1.5]::float4[],
		ARRAY[1.25]::numeric[], ARRAY[''a b'', ''c,d'']::bpchar[], ARRAY[''x'']::name[],
		ARRAY[''2024-01-31'']::date[]') firstRecord.
	self assert: (record at: 1) equals: #( 1 2 ).
	self assert: (record at: 2) equals: #( 3 4 ).
	self assert: (record at: 3) equals: #( 1.5 ).
	self assert: (record at: 4) equals: { 1.25s2 }.
	self assert: (record at: 5) equals: #( 'a b' 'c,d' ).
	self assert: (record at: 6) equals: #( 'x' ).
	self assert: (record at: 7) equals: { Date year: 2024 month: 1 day: 31 }
]

{ #category : 'tests' }
P3UnknownTypeTest >> testUnknownScalarTypesAnswerTheirText [
	"inet, cidr, macaddr, money, xml and ranges have no converter."

	#( #( 'SELECT ''10.0.0.1/8''::inet' '10.0.0.1/8' )
	   #( 'SELECT ''10.0.0.0/8''::cidr' '10.0.0.0/8' )
	   #( 'SELECT ''08:00:2b:01:02:03''::macaddr' '08:00:2b:01:02:03' )
	   #( 'SELECT ''<a/>''::xml' '<a/>' )
	   #( 'SELECT ''[1,5)''::int4range' '[1,5)' )
	   #( 'SELECT ''a & b''::tsquery' '''a'' & ''b''' ) ) do: [ :each |
		self
			assert: (client query: each first) firstFieldOfFirstRecord
			equals: each second ]
]

{ #category : 'tests' }
P3UnknownTypeTest >> testUnknownTypeInPreparedStatementAnswersItsText [
	| statement |
	statement := client prepare: 'SELECT $1::inet' named: 'p3_unknown_type_test'.
	self
		assert: (statement query: #( '10.0.0.1' )) firstFieldOfFirstRecord
		equals: '10.0.0.1'
]

{ #category : 'tests' }
P3UnknownTypeTest >> testUnknownTypeKeepsConnectionInStep [
	(client query: 'SELECT ''10.0.0.1''::inet, 1 FROM generate_series(1, 3)') data.
	self
		assert: (client query: 'SELECT 111') data
		equals: #( #( 111 ) )
]

{ #category : 'tests' }
P3UnknownTypeTest >> testUuidAndTimestampArrays [
	| record uuid |
	uuid := '123e4567-e89b-12d3-a456-426614174000'.
	record := (client query: 'SELECT ARRAY[''', uuid, '''::uuid], ARRAY[''2024-01-31 10:00''::timestamp]') firstRecord.
	self assert: record first equals: { UUID fromString: uuid }.
	self assert: record second equals: { DateAndTime year: 2024 month: 1 day: 31 hour: 10 minute: 0 second: 0 offset: 0 hours }
]
