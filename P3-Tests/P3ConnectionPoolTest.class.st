"
P3ConnectionPoolTest holds unit tests for the P3ConnectionPool class.

I reuse the configuration of P3ClientTest.
"
Class {
	#name : 'P3ConnectionPoolTest',
	#superclass : 'TestCase',
	#instVars : [
		'pool'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'running' }
P3ConnectionPoolTest >> setUp [
	super setUp.
	pool := P3ConnectionPool new.
	pool url: P3ClientTest url
]

{ #category : 'running' }
P3ConnectionPoolTest >> tearDown [
	pool close
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testCleanConnectionIsReusedNotReplaced [
	"The checks on release must not make the pool throw good connections away: a connection that was
	used and left clean serves the next borrower, and still works."

	| first second |
	first := pool withConnection: [ :p3Client | p3Client query: 'SELECT 1'. p3Client ].
	self assert: pool size equals: 1.
	second := pool withConnection: [ :p3Client |
		self assert: (p3Client query: 'SELECT 2') firstFieldOfFirstRecord equals: 2.
		p3Client ].
	self assert: second == first.
	self assert: second isConnected.
	self assert: pool size equals: 1
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testConnectionBeyondCapacityIsClosed [
	"The pool holds at most its capacity of clean connections. The one that does not fit is closed."

	| first second |
	pool size: 1.
	first := pool acquireConnection.
	second := pool acquireConnection.
	first query: 'SELECT 1'.
	second query: 'SELECT 2'.
	pool releaseConnection: first.
	pool releaseConnection: second.
	self assert: pool size equals: 1.
	self assert: first isConnected.
	self deny: second isConnected
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testConnectionWithLostTransactionIsNotPooled [
	"After a failure inside a transaction the client refuses to reconnect silently. Pooled again, it would
	make the first request of every later borrower fail."

	pool withConnection: [ :p3Client |
		p3Client execute: 'BEGIN'.
		p3Client closeAfterFailure ].
	self assert: pool size equals: 0.
	self
		assert: (pool withConnection: [ :p3Client | (p3Client query: 'SELECT 7') firstFieldOfFirstRecord ])
		equals: 7

]

{ #category : 'tests' }
P3ConnectionPoolTest >> testConnectionWithLostTransactionIsNotPooledAfterItsError [
	"The error that reports the lost transaction is not a network error. It must not make the dead
	client look reusable."

	self
		should: [ pool withConnection: [ :p3Client |
			p3Client execute: 'BEGIN'.
			p3Client closeAfterFailure.
			p3Client query: 'SELECT 1' ] ]
		raise: P3Error.
	self assert: pool size equals: 0

]

{ #category : 'tests' }
P3ConnectionPoolTest >> testError [
	"A query the server rejects leaves the connection usable: its response was read to the end. So the
	connection goes back into the pool instead of being dropped."

	self assert: pool size equals: 0.
	self 
		should: [ pool withConnection: [ :p3Client | 
							p3Client query: 'SELECT * FROM abcdef'] ] 
		raise: P3Error.
	self assert: pool size equals: 1
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testErrorInsideTransactionIsNotPooled [
	"A connection left inside a transaction is not the next caller's to inherit: every statement it
	sends would join that transaction, and a failed one rejects them all."

	self assert: pool size equals: 0.
	self
		should: [ pool withConnection: [ :p3Client |
							p3Client execute: 'BEGIN'.
							p3Client query: 'SELECT * FROM abcdef' ] ]
		raise: P3Error.
	self assert: pool size equals: 0
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testFinishedTransactionsArePooled [
	"A transaction that the borrower committed or rolled back is finished: the connection is clean and
	goes back into the pool. Only an open or failed one does not."

	| first |
	first := pool withConnection: [ :p3Client |
		p3Client execute: 'BEGIN'.
		p3Client query: 'SELECT 1'.
		p3Client execute: 'COMMIT'.
		p3Client ].
	self assert: pool size equals: 1.
	pool withConnection: [ :p3Client |
		self assert: p3Client == first.
		p3Client execute: 'BEGIN'.
		p3Client execute: 'ROLLBACK' ].
	self assert: pool size equals: 1.
	pool withConnection: [ :p3Client |
		self assert: p3Client == first.
		self assert: p3Client transactionStatus equals: $I ]
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testOne [
	self assert: pool size equals: 0.
	self 
		assert: (pool withConnection: [ :p3Client | 
							(p3Client query: 'SELECT 1+2') firstFieldOfFirstRecord ]) 
		equals: 3.
	self 
		assert: (pool withConnection: [ :p3Client | 
							(p3Client query: 'SELECT 10-2') firstFieldOfFirstRecord ]) 
		equals: 8.
	self assert: pool size equals: 1
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testReleaseConnectionChecksTheConnection [
	"A connection returned with releaseConnection: gets the same check as one returned by withConnection:."

	| p3Client |
	p3Client := pool acquireConnection.
	p3Client execute: 'BEGIN'.
	pool releaseConnection: p3Client.
	self assert: pool size equals: 0.
	self deny: p3Client isConnected

]

{ #category : 'tests' }
P3ConnectionPoolTest >> testReleaseConnectionPoolsACleanConnection [
	| p3Client |
	p3Client := pool acquireConnection.
	self assert: (p3Client query: 'SELECT 3') firstFieldOfFirstRecord equals: 3.
	pool releaseConnection: p3Client.
	self assert: pool size equals: 1.
	self assert: pool acquireConnection == p3Client.
	self assert: pool size equals: 0.
	pool releaseConnection: p3Client
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testTransactionLeftOpenByNonLocalExitIsNotPooled [
	"Leaving the block with a non local exit, which is not an error, must be checked like a normal return."

	[ :exit |
		pool withConnection: [ :p3Client |
			p3Client execute: 'BEGIN'.
			exit value ] ] valueWithExit.
	self assert: pool size equals: 0
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testTransactionLeftOpenOnSuccessIsNotPooled [
	"A block that begins a transaction and returns normally leaves it open. The next borrower would
	run its statements inside it, with its locks and its uncommitted writes."

	pool withConnection: [ :p3Client | p3Client execute: 'BEGIN' ].
	self assert: pool size equals: 0.
	pool withConnection: [ :p3Client |
		self assert: p3Client transactionStatus equals: $I.
		self assert: (p3Client query: 'SELECT 1') firstFieldOfFirstRecord equals: 1 ]
]

{ #category : 'tests' }
P3ConnectionPoolTest >> testWarmUp [
	self assert: pool size equals: 0.
	pool warmUp.
	self assert: pool size equals: pool capacity.
	pool withConnection: [ :p3Client | 
		p3Client query: 'SELECT table_name FROM information_schema.tables' ].
	self assert: pool size equals: pool capacity.
	pool close.
	self assert: pool size equals: 0
]
