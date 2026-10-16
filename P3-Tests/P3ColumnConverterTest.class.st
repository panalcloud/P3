"
I test which converter reads the values of a column, and when it is chosen.

The converter of a column comes from the type map of the client's converter as it is when the result is read. So a mapping changed between two executions of the same prepared statement applies to the second one, and each result of a query with several statements uses its own columns. A type that has no converter only signals when a value of it is read: a result without rows, or with only NULL values, reads fine.
"
Class {
	#name : 'P3ColumnConverterTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests' }
P3ColumnConverterTest >> testColumnsOfTheSameRowUseTheirOwnConverters [
	self
		assert: (client query: 'SELECT 1::int4, ''1''::text, 1::float8, NULL::int4, ''1''::text') firstRecord
		equals: #( 1 '1' 1.0 nil '1' )
]

{ #category : 'tests' }
P3ColumnConverterTest >> testEachResultOfAQueryUsesItsOwnColumns [
	"The answer holds the rows of the last statement, read with the converters of its own columns"

	| result |
	result := client query: 'SELECT ''x''::text, 1.5::float8; SELECT 42::int4, ''t''::bool'.
	self assert: result results size equals: 2.
	self assert: result data equals: #( #( 42 true ) )
]

{ #category : 'tests' }
P3ColumnConverterTest >> testMappingChangedBetweenExecutionsOfAPreparedStatementApplies [
	| statement |
	statement := client prepare: 'SELECT $1::int4' named: 'p3_column_converter_test'.
	self assert: (statement query: #( 7 )) firstFieldOfFirstRecord equals: 7.
	self withInt4ReadAsMarkedTextDo: [
		self assert: (statement query: #( 7 )) firstFieldOfFirstRecord equals: '7!' ].
	self assert: (statement query: #( 7 )) firstFieldOfFirstRecord equals: 7
]

{ #category : 'tests' }
P3ColumnConverterTest >> testMappingChangedBetweenQueriesApplies [
	self assert: (client query: 'SELECT 7::int4') firstFieldOfFirstRecord equals: 7.
	self withInt4ReadAsMarkedTextDo: [
		self assert: (client query: 'SELECT 7::int4') firstFieldOfFirstRecord equals: '7!' ].
	self assert: (client query: 'SELECT 7::int4') firstFieldOfFirstRecord equals: 7
]

{ #category : 'tests' }
P3ColumnConverterTest >> testUnknownTypeSignalsAtItsFirstValue [
	self
		should: [ client query: 'SELECT v FROM (VALUES (NULL::inet), (''10.0.0.1''::inet)) AS t(v)' ]
		raise: P3Error.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests' }
P3ColumnConverterTest >> testUnknownTypeWithOnlyNullValuesDoesNotSignal [
	self
		assert: (client query: 'SELECT NULL::inet FROM generate_series(1, 3)') data
		equals: #( #( nil ) #( nil ) #( nil ) )
]

{ #category : 'tests' }
P3ColumnConverterTest >> testUnknownTypeWithoutRowsDoesNotSignal [
	| result |
	result := client query: 'SELECT ''10.0.0.1''::inet WHERE false'.
	self assert: result descriptions size equals: 1.
	self assert: result data isEmpty
]

{ #category : 'tests' }
P3ColumnConverterTest >> testUnknownTypesAsTextChangedBetweenExecutionsOfAPreparedStatementApplies [
	| statement |
	statement := client prepare: 'SELECT $1::inet' named: 'p3_column_converter_test'.
	self should: [ statement query: #( '10.0.0.1' ) ] raise: P3Error.
	[ client enableUnknownTypesAsText: true.
	  self assert: (statement query: #( '10.0.0.1' )) firstFieldOfFirstRecord equals: '10.0.0.1' ]
		ensure: [ client enableUnknownTypesAsText: false ].
	self should: [ statement query: #( '10.0.0.1' ) ] raise: P3Error
]

{ #category : 'running' }
P3ColumnConverterTest >> withInt4ReadAsMarkedTextDo: aBlock [
	"Evaluate aBlock while my client reads an int4 as its text followed by an exclamation mark.
	The standard int4 converter is always restored."

	^ [ client converter
			mapOid: 23
			type: #int4
			to: [ :bytes :length :description | (bytes next: length) asString , '!' ].
	  aBlock value ]
		ensure: [ client converter
			mapOid: 23
			type: #int4
			to: #convertIntegerFrom:length:description: ]
]
