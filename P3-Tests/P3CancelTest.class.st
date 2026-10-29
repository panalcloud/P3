"
I test how P3Client stops a statement and bounds waiting: #cancel, the cancel that follows a read timeout, #statementTimeout:, #connectTimeout: and TCP keepalive. Statements are slow with pg_sleep. #extraClient is the connection a test sets up with its own settings.
"
Class {
	#name : 'P3CancelTest',
	#superclass : 'P3ResponseTestCase',
	#instVars : [
		'extraClient'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'running' }
P3CancelTest >> clients [
	^ super clients , { extraClient }
]

{ #category : 'private' }
P3CancelTest >> errorCodeOf: aBlock [
	"The SQLSTATE of the P3Error aBlock signals."

	^ [ aBlock value. nil ] on: P3Error do: [ :error | error code ]
]

{ #category : 'private' }
P3CancelTest >> newClientWith: aBlock [
	"A client with the settings of aBlock, not yet connected."

	| new |
	new := P3Client new
		url: P3ClientTest url;
		retryCount: 0;
		retryDelay: 0;
		yourself.
	aBlock value: new.
	^ new
]

{ #category : 'tests' }
P3CancelTest >> testCancelRequestMessageCarriesTheBackendKeys [
	| message |
	message := client cancelRequestMessage.
	self assert: message size equals: 16.
	self assert: (message first: 8) equals: #[ 0 0 0 16 4 210 22 46 ].
	self assert: (message copyFrom: 9 to: 12) asInteger equals: client backendProcessId.
	self
		assert: (message copyFrom: 13 to: 16) asInteger
		equals: ((client instVarNamed: 'properties') at: 'backend_secret_key')
]

{ #category : 'tests' }
P3CancelTest >> testCancelStopsARunningStatement [
	"Another process cancels while the statement runs, which is why #cancel cannot wait for the monitor."

	| code elapsed |
	[ (Delay forMilliseconds: 500) wait. client cancel ] fork.
	elapsed := [
		code := self errorCodeOf: [ client query: 'SELECT pg_sleep(20)' ] ] timeToRun.
	self assert: code equals: '57014'.
	self assert: elapsed < 5 seconds.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests' }
P3CancelTest >> testCancelWithoutAConnectionAnswersFalse [
	self deny: P3Client new cancel
]

{ #category : 'tests' }
P3CancelTest >> testCancelWithoutARunningRequestAnswersFalse [
	"A cancel names a session, not a statement: sent while nothing runs it could stop the next statement."

	self deny: client isResponsePending.
	self deny: client cancel
]

{ #category : 'tests' }
P3CancelTest >> testConnectTimeoutAndReadTimeoutAreSeparate [
	self assert: P3Client new connectTimeout equals: 10.
	extraClient := self newClientWith: [ :new | new timeout: 30; connectTimeout: 3 ].
	self assert: extraClient timeout equals: 30.
	self assert: extraClient connectTimeout equals: 3
]

{ #category : 'tests' }
P3CancelTest >> testConnectTimeoutBoundsReachingAServer [
	"10.255.255.1 does not answer. A network that rejects it at once also satisfies the test."

	| elapsed |
	extraClient := self newClientWith: [ :new |
		new host: '10.255.255.1'; connectTimeout: 1 ].
	elapsed := [ self should: [ extraClient connect ] raise: NetworkError ] timeToRun.
	self assert: elapsed < 5 seconds
]

{ #category : 'tests' }
P3CancelTest >> testConnectionUsesTcpKeepAlive [
	"Keepalive lets the operating system notice a peer that is gone without closing the connection."

	| option |
	option := client connection socket getOption: 'SO_KEEPALIVE'.
	self assert: option first equals: 0.
	self deny: option second = 0
]

{ #category : 'tests' }
P3CancelTest >> testHandshakeIsBoundedByTheConnectTimeout [
	"A server that accepts the TCP connection and then never answers holds the startup. That wait is bounded
	by #connectTimeout, not by the much longer #timeout for statements."

	| listener elapsed |
	listener := Socket newTCP.
	listener listenOn: 0 backlogSize: 4.
	[ extraClient := self newClientWith: [ :new |
		new host: '127.0.0.1'; port: listener localPort; connectTimeout: 1; timeout: 30 ].
	elapsed := [ self should: [ extraClient connect ] raise: NetworkError ] timeToRun.
	self assert: elapsed < 5 seconds ]
		ensure: [ listener destroy ]
]

{ #category : 'tests' }
P3CancelTest >> testReadTimeoutCancelsTheStatementAndKeepsTheConnection [
	| elapsed |
	extraClient := self newClientWith: [ :new | new timeout: 1 ].
	extraClient connect.
	elapsed := [
		self should: [ extraClient query: 'SELECT pg_sleep(20)' ] raise: ConnectionTimedOut ] timeToRun.
	self assert: elapsed < 5 seconds.
	self assert: extraClient isConnected.
	self assert: (extraClient query: 'SELECT 111') data equals: #( #( 111 ) ).
	self assert: (extraClient query: 'SELECT 222') data equals: #( #( 222 ) ).
	self assert: extraClient isResponsePending not
]

{ #category : 'tests' }
P3CancelTest >> testReadTimeoutInsideATransactionLeavesItFailedNotLost [
	extraClient := self newClientWith: [ :new | new timeout: 1 ].
	extraClient connect.
	extraClient execute: 'BEGIN'.
	self should: [ extraClient query: 'SELECT pg_sleep(20)' ] raise: ConnectionTimedOut.
	self assert: extraClient isConnected.
	self assert: extraClient transactionStatus equals: $E.
	self should: [ extraClient query: 'SELECT 1' ] raise: P3Error.
	extraClient execute: 'ROLLBACK'.
	self assert: (extraClient query: 'SELECT 111') data equals: #( #( 111 ) )
]

{ #category : 'tests' }
P3CancelTest >> testReadTimeoutStopsTheStatementOnTheServer [
	"The statement is cancelled, not abandoned: it does not finish its work after the caller gave up."

	| table |
	table := 'p3_cancel_test'.
	[ client execute: 'DROP TABLE IF EXISTS ' , table.
	client execute: 'CREATE TABLE ' , table , ' (i int)'.
	extraClient := self newClientWith: [ :new | new timeout: 1 ].
	extraClient connect.
	self
		should: [ extraClient execute: 'INSERT INTO ' , table , ' SELECT 1 FROM pg_sleep(3)' ]
		raise: ConnectionTimedOut.
	(Delay forSeconds: 4) wait.
	self assert: (client query: 'SELECT count(*) FROM ' , table) firstFieldOfFirstRecord equals: 0 ]
		ensure: [ [ client execute: 'DROP TABLE IF EXISTS ' , table ] on: Error do: [ :error | ] ]
]

{ #category : 'tests' }
P3CancelTest >> testStatementTimeoutIsSetByTheStartup [
	| code elapsed |
	extraClient := self newClientWith: [ :new | new statementTimeout: 1 ].
	extraClient connect.
	self assert: (extraClient query: 'SHOW statement_timeout') firstFieldOfFirstRecord equals: '1s'.
	elapsed := [ code := self errorCodeOf: [ extraClient query: 'SELECT pg_sleep(20)' ] ] timeToRun.
	self assert: code equals: '57014'.
	self assert: elapsed < 5 seconds.
	self assert: (extraClient query: 'SELECT 111') data equals: #( #( 111 ) ).
	self assert: (extraClient query: 'SELECT 222') data equals: #( #( 222 ) )
]

{ #category : 'tests' }
P3CancelTest >> testThereIsNoStatementTimeoutByDefault [
	self assert: client statementTimeout isNil.
	self assert: (client query: 'SHOW statement_timeout') firstFieldOfFirstRecord equals: '0'
]

{ #category : 'tests' }
P3CancelTest >> testTimeoutAfterTheStatementCompletedIsNotReportedAsATimeout [
	"The read times out after the server already finished the statement. The cancel then reaches an idle
	session and changes nothing, and the response read afterwards is that of a completed statement. The
	caller must not be told that the statement did not run."

	| error |
	client execute: 'CREATE TEMP TABLE p3_late_read (i int)'.
	client instVarNamed: 'connection' put: (P3LateReadStream on: client connection).
	error := [ client execute: 'INSERT INTO p3_late_read VALUES (1)'. nil ] on: Error do: [ :e | e ].
	self assert: (error isKindOf: P3Error) description: 'A completed statement was reported as ' , error class name.
	self assert: error code equals: 'P3054'.
	self assert: client isConnected.
	self assert: (client query: 'SELECT count(*) FROM p3_late_read') firstFieldOfFirstRecord equals: 1.
	self assertConnectionAnswersItsOwnQueries
]
