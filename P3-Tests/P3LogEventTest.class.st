"
I test the log events that a client sends to P3LogEvent announcer: a subscriber sees the query that was written and the result that was read, with its duration, and the preparation and the bound values of a prepared statement. A subscriber that arrives between two requests sees the next one with its own duration.
"
Class {
	#name : 'P3LogEventTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3LogEventTest >> eventsDuring: aBlock [
	"Answer the log events of my client's session emitted while aBlock runs"

	| events session |
	events := OrderedCollection new.
	session := client session.
	P3LogEvent announcer
		when: P3LogEvent
		do: [ :event | event session = session ifTrue: [ events add: event ] ]
		for: self.
	[ aBlock value ] ensure: [ P3LogEvent announcer unsubscribe: self ].
	^ events asArray
]

{ #category : 'tests' }
P3LogEventTest >> testDurationOfAResult [
	| events |
	events := self eventsDuring: [ client query: 'SELECT pg_sleep(0.2)' ].
	self assert: events last duration >= 200
]

{ #category : 'tests' }
P3LogEventTest >> testPreparedStatementReachesASubscriber [
	| events statement |
	events := self eventsDuring: [
		statement := client prepare: 'SELECT $1::int4' named: 'p3_log_event_test'.
		statement executeBatch: #( #( 1 ) #( 2 ) ) ].
	self
		assert: (events collect: [ :each | each class ])
		equals: { P3StatementPreparedEvent. P3StatementBoundEvent. P3StatementBoundEvent. P3ResultReadEvent. P3ResultReadEvent }.
	self
		assert: ((events select: [ :each | each class = P3StatementBoundEvent ]) collect: [ :each | each inputValues ])
		equals: #( #( 1 ) #( 2 ) )
]

{ #category : 'tests' }
P3LogEventTest >> testQueryAndResultReachASubscriber [
	| events |
	events := self eventsDuring: [ client query: 'SELECT 1' ].
	self assert: (events collect: [ :each | each class ]) equals: { P3QueryWrittenEvent. P3ResultReadEvent }.
	self assert: events first query equals: 'SELECT 1'.
	self assert: events second result data equals: #( #( 1 ) ).
	self assert: events second duration >= 0
]

{ #category : 'tests' }
P3LogEventTest >> testSubscriberArrivingBetweenRequestsSeesTheNextWithItsOwnDuration [
	"Requests made with nobody listening leave nothing behind that the next result would be timed from"

	| statement events |
	statement := client prepare: 'SELECT 1' named: 'p3_log_event_test'.
	statement query: #().
	client query: 'SELECT 1'.
	(Delay forMilliseconds: 300) wait.
	events := self eventsDuring: [ client query: 'SELECT 2' ].
	self assert: (events collect: [ :each | each class ]) equals: { P3QueryWrittenEvent. P3ResultReadEvent }.
	self assert: events last duration < 250
]
