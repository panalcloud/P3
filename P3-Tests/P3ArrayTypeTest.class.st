"
I test reading arrays of the standard types that are read through the converter of their element type.

Configure the connection through P3ClientTest class >> #url:, like the other tests in this package.
"
Class {
	#name : 'P3ArrayTypeTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests' }
P3ArrayTypeTest >> testStandardArrayTypesAreConverted [
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
P3ArrayTypeTest >> testUuidAndTimestampArrays [
	| record uuid |
	uuid := '123e4567-e89b-12d3-a456-426614174000'.
	record := (client query: 'SELECT ARRAY[''', uuid, '''::uuid], ARRAY[''2024-01-31 10:00''::timestamp]') firstRecord.
	self assert: record first equals: { UUID fromString: uuid }.
	self assert: record second equals: { DateAndTime year: 2024 month: 1 day: 31 hour: 10 minute: 0 second: 0 offset: 0 hours }
]
