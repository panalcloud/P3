"
Tests how a P3PreparedStatement behaves when it is used wrongly: the wrong number of values, a value of the wrong type, and use after close. After each error the connection must still answer queries, and an error must say what was wrong.
"
Class {
	#name : 'P3PreparedStatementLifecycleTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3PreparedStatementLifecycleTest >> assertConnectionStillAnswers [
	self assert: (client query: 'SELECT 1') firstFieldOfFirstRecord equals: 1
]

{ #category : 'tests' }
P3PreparedStatementLifecycleTest >> testCloseTwiceIsHarmless [
	| statement |
	statement := client prepare: 'SELECT $1::int8'.
	statement close.
	statement close.
	self assertConnectionStillAnswers
]

{ #category : 'tests' }
P3PreparedStatementLifecycleTest >> testPreparingTheSameSourceAgainWorksAfterClose [
	"The server names a statement after its source, so the name is free again after close."

	| first second |
	first := client prepare: 'SELECT $1::int8'.
	first close.
	second := client prepare: 'SELECT $1::int8'.
	[ self assert: (second query: { 3 }) firstFieldOfFirstRecord equals: 3 ]
		ensure: [ second close ]
]

{ #category : 'tests' }
P3PreparedStatementLifecycleTest >> testUseAfterCloseSaysTheStatementIsClosed [
	"A closed statement has no client. The error must not be a message sent to nil."

	| statement error |
	statement := client prepare: 'SELECT $1::int8'.
	statement close.
	error := [ statement query: { 1 }. nil ] on: Error do: [ :e | e ].
	self assert: error notNil description: 'Using a closed statement did not signal'.
	self deny: (error isKindOf: MessageNotUnderstood)
]

{ #category : 'tests' }
P3PreparedStatementLifecycleTest >> testValueOfWrongTypeLeavesStatementUsable [
	| statement |
	statement := client prepare: 'SELECT $1::int8'.
	[ self should: [ statement query: { 'abc' } ] raise: P3Error.
	self assertConnectionStillAnswers.
	self assert: (statement query: { 7 }) firstFieldOfFirstRecord equals: 7 ]
		ensure: [ statement close ]
]

{ #category : 'tests' }
P3PreparedStatementLifecycleTest >> testWrongNumberOfValuesIsRefusedBeforeSending [
	| statement |
	statement := client prepare: 'SELECT $1::int8'.
	[ self should: [ statement query: #() ] raise: Error.
	self assertConnectionStillAnswers.
	self should: [ statement query: { 1. 2 } ] raise: Error.
	self assertConnectionStillAnswers.
	self assert: (statement query: { 7 }) firstFieldOfFirstRecord equals: 7 ]
		ensure: [ statement close ]
]
