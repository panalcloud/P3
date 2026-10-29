"
Tests how a P3PreparedStatement behaves when it is used wrongly: the wrong number of values, a value of the wrong type, use after close, a batch with a row that cannot be bound or that fails at the server. After each error the connection must still answer queries, and an error must say what was wrong. Also tests what a request records about itself: the bound values it logs and the source of its results.
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
P3PreparedStatementLifecycleTest >> boundValuesDuring: aBlock [
	"Answer the input values of every P3StatementBoundEvent emitted while aBlock runs."

	| bound |
	bound := OrderedCollection new.
	P3LogEvent announcer
		when: P3StatementBoundEvent
		do: [ :event | bound add: event inputValues ]
		for: self.
	[ aBlock value ] ensure: [ P3LogEvent announcer unsubscribe: self ].
	^ bound asArray
]

{ #category : 'tests' }
P3PreparedStatementLifecycleTest >> testBatchRunsAsOneImplicitTransaction [
	| insert |
	client execute: 'CREATE TEMP TABLE p3l_batch(i int PRIMARY KEY)'.
	insert := client prepare: 'INSERT INTO p3l_batch VALUES ($1)'.
	self should: [ insert executeBatch: { { 1 }. { 2 }. { 2 } } ] raise: P3Error.
	self assert: (client query: 'SELECT count(*) FROM p3l_batch') firstFieldOfFirstRecord equals: 0.
	self should: [ (client prepare: 'VACUUM') executeBatch: { #(). #() } ] raise: P3Error.
	self assert: (client query: 'SELECT 5') firstFieldOfFirstRecord equals: 5
]

{ #category : 'tests' }
P3PreparedStatementLifecycleTest >> testBoundEventIsEmittedOncePerRowOfTheSentRequest [
	| statement rows bound |
	statement := client prepare: 'SELECT $1::int + 1'.
	rows := { { 1 }. { 2 }. { 3 } }.
	bound := self boundValuesDuring: [ statement executeBatch: rows ].
	self assert: bound equals: rows.
	bound := self boundValuesDuring: [ statement query: #( 7 ) ].
	self assert: bound equals: { #( 7 ) }
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
P3PreparedStatementLifecycleTest >> testEmptyPreparedQueryKeepsTheConnection [
	#( '' '-- only a comment' ) do: [ :sql | | result |
		result := (client prepare: sql) query: #().
		self deny: result hasData.
		self assert: result firstFieldOfFirstRecord isNil.
		self assert: client isConnected.
		self assert: (client query: 'SELECT 5') firstFieldOfFirstRecord equals: 5.
		self assert: (client query: 'SELECT 6') firstFieldOfFirstRecord equals: 6 ]
]

{ #category : 'tests' }
P3PreparedStatementLifecycleTest >> testNoBoundEventWhenTheRequestCannotBeBuilt [
	| statement bound |
	statement := client prepare: 'SELECT $1::int + 1'.
	bound := self boundValuesDuring: [
		self should: [ statement executeBatch: { { 1 }. { Object new } } ] raise: Error ].
	self assert: bound isEmpty.
	self assert: (client query: 'SELECT 5') firstFieldOfFirstRecord equals: 5
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
P3PreparedStatementLifecycleTest >> testResultSourceIsThatOfItsOwnStatementWhenProcessesShareAClient [
	| statements done wrong |
	statements := #( 1 2 ) collect: [ :each | client prepare: 'SELECT $1::int + ' , each printString ].
	done := statements collect: [ :each | Semaphore new ].
	wrong := OrderedCollection new.
	statements with: done do: [ :statement :semaphore |
		[ [ 40 timesRepeat: [ | result |
				result := statement query: #( 1 ).
				result source = statement source ifFalse: [ wrong add: result source ] ] ]
			ensure: [ semaphore signal ] ] fork ].
	done do: [ :semaphore | semaphore waitTimeoutMilliseconds: 60000 ].
	self assert: wrong isEmpty
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
