"
I test the default of P3Client: a column type P3 has no converter for signals a P3Error, because the caller is reading data it does not handle. The connection stays in step after the error.
"
Class {
	#name : 'P3UnknownTypeSignalsTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests' }
P3UnknownTypeSignalsTest >> testConverterWithoutFallbackSignalsForUnknownOid [
	| converter description |
	converter := P3Converter new.
	converter encoder: ZnUTF8Encoder new.
	description := P3RowFieldDescription new typeOid: 869; yourself.
	self
		should: [ converter convert: #[49] readStream length: 1 description: description ]
		raise: P3Error.
	converter unknownTypeConverter: #convertStringFrom:length:description:.
	self
		assert: (converter convert: #[49] readStream length: 1 description: description)
		equals: '1'
]

{ #category : 'tests' }
P3UnknownTypeSignalsTest >> testStandardArrayTypesStillConvert [
	self
		assert: (client query: 'SELECT ARRAY[3,4]::int8[]') firstFieldOfFirstRecord
		equals: #( 3 4 )
]

{ #category : 'tests' }
P3UnknownTypeSignalsTest >> testUnknownScalarTypeSignals [
	self deny: client isUnknownTypesAsTextEnabled.
	#( 'SELECT ''10.0.0.1''::inet' 'SELECT ''[1,5)''::int4range' 'SELECT ''<a/>''::xml' ) do: [ :sql |
		self should: [ client query: sql ] raise: P3Error.
		self assertConnectionAnswersItsOwnQueries ]
]

{ #category : 'tests' }
P3UnknownTypeSignalsTest >> testUnknownTypeInPreparedStatementSignals [
	| statement |
	statement := client prepare: 'SELECT $1::inet' named: 'p3_unknown_signals_test'.
	self should: [ statement query: #( '10.0.0.1' ) ] raise: P3Error.
	self assertConnectionAnswersItsOwnQueries
]
