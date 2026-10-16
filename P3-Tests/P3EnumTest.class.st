"
I test how P3Client reads ENUM types and arrays of them. An enum is read as a Symbol once P3Client>>#loadEnums mapped it, which is repeated by itself when the client reconnects. An enum that is not mapped signals a P3Error, like any other type without a converter.
"
Class {
	#name : 'P3EnumTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3EnumTest >> dropObjects [
	"Notices about objects that do not exist are expected."

	[ client
		execute: 'DROP TABLE IF EXISTS p3_enum_table';
		execute: 'DROP TYPE IF EXISTS p3_enum_late';
		execute: 'DROP TYPE IF EXISTS p3_enum_mood';
		execute: 'DROP SCHEMA IF EXISTS p3_enum_schema CASCADE' ]
		on: P3Notification
		do: [ :notification | notification resume ]
]

{ #category : 'private' }
P3EnumTest >> readMoods [
	^ (client query: 'SELECT m, ms FROM p3_enum_table ORDER BY m NULLS LAST') data
]

{ #category : 'running' }
P3EnumTest >> setUp [
	super setUp.
	self dropObjects.
	client
		execute: 'CREATE SCHEMA p3_enum_schema';
		execute: 'CREATE TYPE p3_enum_mood AS ENUM (''sad'', ''ok'', ''happy'', ''very happy'')';
		execute: 'CREATE TYPE p3_enum_schema.shade AS ENUM (''light'', ''dark'')';
		execute: 'CREATE TABLE p3_enum_table (m p3_enum_mood, ms p3_enum_mood[], s p3_enum_schema.shade)';
		execute: 'INSERT INTO p3_enum_table VALUES (''ok'', ARRAY[''sad'', NULL, ''very happy'']::p3_enum_mood[], ''dark''), (NULL, NULL, NULL)'
]

{ #category : 'running' }
P3EnumTest >> tearDown [
	[ self dropObjects ] on: Error do: [ :error | ].
	super tearDown
]

{ #category : 'tests' }
P3EnumTest >> testEnumCreatedAfterLoadSignalsUntilLoadedAgain [
	client loadEnums.
	client execute: 'CREATE TYPE p3_enum_late AS ENUM (''a'')'.
	self should: [ client query: 'SELECT ''a''::p3_enum_late' ] raise: P3Error.
	self assertConnectionAnswersItsOwnQueries.
	client loadEnums.
	self
		assert: (client query: 'SELECT ''a''::p3_enum_late') firstFieldOfFirstRecord
		equals: #a
]

{ #category : 'tests' }
P3EnumTest >> testEnumInAnotherSchemaIsRead [
	client loadEnums.
	self
		assert: (client query: 'SELECT s FROM p3_enum_table WHERE s IS NOT NULL') firstFieldOfFirstRecord
		equals: #dark
]

{ #category : 'tests' }
P3EnumTest >> testEnumsNeverLoadedAreNotLoadedByReconnect [
	client close.
	self should: [ self readMoods ] raise: P3Error
]

{ #category : 'tests' }
P3EnumTest >> testLoadEnumsAnswersNamesQualifiedWhenNotVisible [
	| names |
	names := client loadEnums.
	self assert: (names includes: #p3_enum_mood).
	self assert: (names includes: #'p3_enum_schema.shade').
	self deny: (names includes: #shade)
]

{ #category : 'tests' }
P3EnumTest >> testLoadedEnumAndEnumArrayReadSymbols [
	client loadEnums.
	self
		assert: self readMoods
		equals: { { #ok. { #sad. nil. #'very happy' } }. #( nil nil ) }
]

{ #category : 'tests' }
P3EnumTest >> testLoadedEnumInPreparedStatement [
	| statement |
	client loadEnums.
	statement := client prepare: 'SELECT m FROM p3_enum_table WHERE m = $1' named: 'p3_enum_prepared'.
	self assert: (statement query: #( #ok )) data equals: #( #( #ok ) ).
	self assert: (statement query: #( 'ok' )) data equals: #( #( #ok ) )
]

{ #category : 'tests' }
P3EnumTest >> testLoadedEnumsAreLoadedAgainAfterReconnect [
	client loadEnums.
	client close.
	self
		assert: self readMoods
		equals: { { #ok. { #sad. nil. #'very happy' } }. #( nil nil ) }
]

{ #category : 'tests' }
P3EnumTest >> testUnmappedEnumArraySignals [
	self
		should: [ client query: 'SELECT ARRAY[''ok'']::p3_enum_mood[]' ]
		raise: P3Error.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests' }
P3EnumTest >> testUnmappedEnumIsTextWhenUnknownTypesAreText [
	client enableUnknownTypesAsText: true.
	self assert: self readMoods first equals: { 'ok'. '{sad,NULL,"very happy"}' }
]

{ #category : 'tests' }
P3EnumTest >> testUnmappedEnumSignals [
	self should: [ self readMoods ] raise: P3Error.
	self assertConnectionAnswersItsOwnQueries
]
