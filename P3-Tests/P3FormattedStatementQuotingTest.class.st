"
Tests that P3FormattedStatement quotes values correctly when the session has standard_conforming_strings off. With that setting a backslash inside a plain quoted literal is an escape character. For each value the statement may either read it back unchanged or refuse to run, but it must never run a different statement or store a different value. Each test uses its own connection, so the setting never leaks.
"
Class {
	#name : 'P3FormattedStatementQuotingTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests-server' }
P3FormattedStatementQuotingTest >> testBackslashIsNotAnEscapeWhenSettingIsOff [
	"\b is a backspace in an escape string. The value must come back with a backslash and a b, or be refused."

	| value |
	self turnOffStandardConformingStrings.
	value := self quietly: [ self valueOf: 'SELECT $1::text' with: { 'a\b' } ].
	value ifNotNil: [ self assert: value equals: 'a\b' ]
]

{ #category : 'tests-server' }
P3FormattedStatementQuotingTest >> testBackslashRoundTripsByDefault [
	"With the default setting a backslash is an ordinary character."

	self assert: (self valueOf: 'SELECT $1::text' with: { 'a\b\' }) equals: 'a\b\'
]

{ #category : 'tests-server' }
P3FormattedStatementQuotingTest >> testByteaRoundTripsByDefault [
	self assert: (self valueOf: 'SELECT $1::bytea' with: { #[65 66 222 173 190 239 92 39] }) equals: #[65 66 222 173 190 239 92 39]
]

{ #category : 'tests-server' }
P3FormattedStatementQuotingTest >> testByteaRoundTripsWhenSettingIsOff [
	"The bytea hex format starts with a backslash and must not be read as an escape. The bytes 65 66 are written as \x4142, which an escape string reads as the text A42."

	| value |
	self turnOffStandardConformingStrings.
	value := self quietly: [ self valueOf: 'SELECT $1::bytea' with: { #[65 66] } ].
	value ifNotNil: [ self assert: value equals: #[65 66] ]
]

{ #category : 'tests-server' }
P3FormattedStatementQuotingTest >> testSettingIsOffInTestSession [
	"Guard for the other tests: the session really treats a backslash as an escape."

	self turnOffStandardConformingStrings.
	self assert: (client query: 'SHOW standard_conforming_strings') firstFieldOfFirstRecord equals: 'off'.
	self assert: (client query: 'SELECT ''a\tb''') firstFieldOfFirstRecord equals: 'a' , (String with: Character tab) , 'b'
]

{ #category : 'tests-server' }
P3FormattedStatementQuotingTest >> testTrailingBackslashCannotInjectSql [
	"The first value ends in a backslash. When that escapes the closing quote, the second value's text becomes SQL and a sub select runs."

	| record |
	self turnOffStandardConformingStrings.
	record := self
		quietly: [ ((client format: 'SELECT $1::text AS a, $2::text AS b') query: { '\'. ' , (SELECT current_user) --' }) firstRecord ].
	record ifNotNil: [
		self assert: record size equals: 2.
		self assert: record first equals: '\'.
		self assert: record second equals: ' , (SELECT current_user) --' ]
]

{ #category : 'helpers' }
P3FormattedStatementQuotingTest >> turnOffStandardConformingStrings [
	"Change this session only. The warning is switched off so the server sends no notice."

	client execute: 'SET client_min_messages = error'.
	client execute: 'SET escape_string_warning = off'.
	client execute: 'SET standard_conforming_strings = off'
]
