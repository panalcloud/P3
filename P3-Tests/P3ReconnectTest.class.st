"
I test what a client does when its connection was lost outside a transaction. By default it reconnects on the next request, signals P3ConnectionReplaced so the application can learn that the session state is gone, and prepares its statements again. With autoReconnect off it signals a P3Error and waits for an explicit connect. A backend that terminates itself with pg_terminate_backend ends the session deterministically.
"
Class {
	#name : 'P3ReconnectTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3ReconnectTest >> loseConnection [
	"End the session from the server side. The FATAL error is expected and ignored."

	[ client query: 'SELECT pg_terminate_backend(pg_backend_pid())' ] on: P3Error do: [ :e | e return ].
	self deny: client isConnected
]

{ #category : 'helpers' }
P3ReconnectTest >> replacementsDuring: aBlock [
	"Answer how many times P3ConnectionReplaced was signalled while aBlock ran."

	| count |
	count := 0.
	aBlock
		on: P3ConnectionReplaced
		do: [ :notification | count := count + 1. notification resume ].
	^ count
]

{ #category : 'tests' }
P3ReconnectTest >> testAnExplicitCloseIsNotALostConnection [
	"Closing is the caller's choice: the next request opens a connection, with or without autoReconnect, and
	nothing is signalled."

	client autoReconnect: false.
	client close.
	self assert: (self replacementsDuring: [
		self assert: (client query: 'SELECT 2') firstFieldOfFirstRecord equals: 2 ]) equals: 0
]

{ #category : 'tests' }
P3ReconnectTest >> testAutoReconnectIsOnByDefault [
	self assert: client autoReconnect.
	client autoReconnect: false.
	self deny: client autoReconnect
]

{ #category : 'tests' }
P3ReconnectTest >> testClosingAStatementOfALostSessionNeedsNoServer [
	| statement |
	statement := client prepare: 'SELECT 1'.
	self loseConnection.
	statement close.
	self deny: client isConnected description: 'Closing opened a connection just to close a statement that is gone'.
	self should: [ client preparedStatementNamed: 'SELECT 1' ] raise: NotFound
]

{ #category : 'tests' }
P3ReconnectTest >> testFirstConnectAndExplicitReconnectSignalNothing [
	| other |
	other := P3Client new url: P3ClientTest url; yourself.
	self assert: (self replacementsDuring: [ other connect. other close. other connect ]) equals: 0.
	other close.
	self assert: client connectionGeneration equals: 1
]

{ #category : 'tests' }
P3ReconnectTest >> testLostConnectionIsReplacedAndSaysSo [
	| count |
	self loseConnection.
	count := self replacementsDuring: [
		self assert: (client query: 'SELECT 111') firstFieldOfFirstRecord equals: 111 ].
	self assert: count equals: 1.
	self assert: client connectionGeneration equals: 2.
	self assert: (self replacementsDuring: [ client query: 'SELECT 1' ]) equals: 0

]

{ #category : 'tests' }
P3ReconnectTest >> testPreparedStatementBatchAfterReplacement [
	| statement results |
	statement := client prepare: 'SELECT $1::int'.
	self loseConnection.
	results := statement queryAll: #( #(1) #(2) ).
	self assert: (results collect: [ :each | each firstFieldOfFirstRecord ]) asArray equals: #(1 2).
	statement close
]

{ #category : 'tests' }
P3ReconnectTest >> testPreparedStatementIsPreparedAgainAfterReplacement [
	| statement |
	statement := client prepare: 'SELECT $1::int + 1000'.
	self assert: (statement query: #(1)) firstFieldOfFirstRecord equals: 1001.
	self loseConnection.
	self assert: (statement query: #(2)) firstFieldOfFirstRecord equals: 1002.
	self assert: (statement query: #(3)) firstFieldOfFirstRecord equals: 1003.
	self assert: (client preparedStatementNamed: statement name) == statement.
	statement close
]

{ #category : 'tests' }
P3ReconnectTest >> testSessionStateIsGoneAfterReplacement [
	"The reason for the notification: a temp table lived in the lost session."

	client execute: 'CREATE TEMP TABLE p3_reconnect_t (i int)'.
	self loseConnection.
	self should: [ client query: 'SELECT count(*) FROM p3_reconnect_t' ] raise: P3Error
]

{ #category : 'tests' }
P3ReconnectTest >> testStatementIsPreparedAgainAfterExplicitReconnect [
	| statement |
	statement := client prepare: 'SELECT $1::int + 1000'.
	client close.
	client connect.
	self assert: (statement query: #(5)) firstFieldOfFirstRecord equals: 1005
]

{ #category : 'tests' }
P3ReconnectTest >> testUnhandledReplacementDoesNotChangeBehaviour [
	self loseConnection.
	self assert: (client query: 'SELECT 111') firstFieldOfFirstRecord equals: 111
]

{ #category : 'tests' }
P3ReconnectTest >> testWithoutAutoReconnectALostConnectionSignals [
	| error |
	client autoReconnect: false.
	self loseConnection.
	error := [ client query: 'SELECT 1'. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil description: 'The client reconnected although autoReconnect is off'.
	self assert: error code equals: 'P3052'.
	self deny: client isConnected.
	self assert: (self replacementsDuring: [ [ client query: 'SELECT 1' ] on: P3Error do: [ :e | e return ] ]) equals: 0
]

{ #category : 'tests' }
P3ReconnectTest >> testWithoutAutoReconnectExplicitConnectContinues [
	client autoReconnect: false.
	self loseConnection.
	client connect.
	self assert: (client query: 'SELECT 111') firstFieldOfFirstRecord equals: 111.
	self assert: client connectionGeneration equals: 2
]
