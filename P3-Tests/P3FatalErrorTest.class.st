"
I test what a client reports when the server ends the session with a FATAL error. The server sends an ErrorResponse and then closes the socket, it does not send ReadyForQuery. The client must report that error, with its SQLSTATE and text, and not the closed socket. A backend that terminates itself with pg_terminate_backend makes the server send exactly that, so no second connection and no waiting is needed.
"
Class {
	#name : 'P3FatalErrorTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3FatalErrorTest >> assertTerminationReported: aBlock [
	"aBlock must signal the P3Error that the server sent for a terminated backend, 57P01."

	| error |
	error := aBlock on: Error do: [ :e | e ].
	self assert: (error isKindOf: P3Error) description: 'The error was ' , error class name , ', not the error the server sent'.
	self assert: error code equals: '57P01'.
	self assert: (error messageText includesSubstring: 'terminating connection').
	self deny: client isConnected.
	self deny: client isResponsePending.
	^ error
]

{ #category : 'private' }
P3FatalErrorTest >> terminateSql [
	^ 'SELECT pg_terminate_backend(pg_backend_pid())'
]

{ #category : 'tests' }
P3FatalErrorTest >> testClientReconnectsAfterFatalErrorOutsideATransaction [
	"Nothing was lost with the session, so the next use opens a new connection and answers for itself."

	self assertTerminationReported: [ client query: self terminateSql. nil ].
	self assert: (client query: 'SELECT 111') firstFieldOfFirstRecord equals: 111.
	self assert: (client query: 'SELECT 222') firstFieldOfFirstRecord equals: 222
]

{ #category : 'tests' }
P3FatalErrorTest >> testFatalErrorInsideATransactionLosesIt [
	"The server rolled the transaction back. The client must say so and not continue in autocommit."

	| error |
	client execute: 'BEGIN'.
	self assertTerminationReported: [ client query: self terminateSql. nil ].
	error := [ client query: 'SELECT 1'. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil description: 'The client reconnected silently after a lost transaction'.
	self assert: error code equals: 'P3050'
]

{ #category : 'tests' }
P3FatalErrorTest >> testFatalErrorIsSeenByTheErrorLog [
	"The error is logged as any other error, so a subscriber learns why the connection ended."

	| errors |
	errors := OrderedCollection new.
	P3LogEvent announcer
		when: P3ErrorOccurredEvent
		do: [ :event | errors add: event ]
		for: self.
	[ self assertTerminationReported: [ client query: self terminateSql. nil ] ]
		ensure: [ P3LogEvent announcer unsubscribe: self ].
	self assert: errors size equals: 1.
	self assert: errors first exception code equals: '57P01'
]

{ #category : 'tests' }
P3FatalErrorTest >> testFatalErrorWhileConnectingIsReported [
	"A database that does not exist is a FATAL error during startup, 3D000."

	| other error url |
	url := P3ClientTest url asZnUrl copy.
	url removeLastPathSegment; addPathSegment: 'p3_no_such_database'.
	other := P3Client new url: url.
	other timeout: 5.
	error := [ other connect. nil ] on: Error do: [ :e | e ].
	[ self assert: (error isKindOf: P3Error) description: 'The error was ' , error class name.
	self assert: error code equals: '3D000' ] ensure: [ other close ]
]

{ #category : 'tests' }
P3FatalErrorTest >> testTerminatedBackendIsReportedByItsError [
	self assertTerminationReported: [ client query: self terminateSql. nil ]
]

{ #category : 'tests' }
P3FatalErrorTest >> testTerminatedBackendIsReportedInAPreparedStatement [
	| statement |
	statement := client prepare: self terminateSql.
	self assertTerminationReported: [ statement query: #(). nil ]
]
