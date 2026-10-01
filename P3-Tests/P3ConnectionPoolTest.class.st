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
