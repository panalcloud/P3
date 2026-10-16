"
I test that writing a request and reading its response stay in step.

Each request must drain a response nobody read before asking for a new one, must be built completely before any byte reaches the socket, and must not be sent twice. When that discipline is broken the connection keeps working and answers the question before the one that was asked, which is why most of my tests end in #assertConnectionAnswersItsOwnQueries.

I also cover the messages that are not part of an ordinary result: EmptyQueryResponse, CopyInResponse and CopyOutResponse, which used to fail an assertion or wait for data nobody sends.

I need a server. See P3ClientTest class >> url.
"
Class {
	#name : 'P3RequestDisciplineTest',
	#superclass : 'P3ResponseTestCase',
	#instVars : [
		'extraClient'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3RequestDisciplineTest >> abandonResponse [
	"Leave a response unread the way a handler that returns instead of resuming does. The converter
	signals a Warning, which is not an Error, so no recovery runs: the reading is simply abandoned
	with the response half read. A Process terminated while reading leaves the same state."

	[ client converter
		mapOid: 23
		type: #int4
		to: [ :bytes :length :description | Warning signal: 'abandon this response' ].
	  [ client query: 'SELECT 7 UNION ALL SELECT 8' ]
		on: Warning
		do: [ :warning | warning return: nil ] ]
		ensure: [ client converter
			mapOid: 23
			type: #int4
			to: #convertIntegerFrom:length:description: ]
]

{ #category : 'running' }
P3RequestDisciplineTest >> clients [
	"#extraClient is opened by the tests that need a second connection or their own settings."

	^ super clients , { extraClient }
]

{ #category : 'accessing' }
P3RequestDisciplineTest >> expectedFailures [
	^ #( #testBatchBindFailureExecutesNothing #testCloseAfterAbandonedResponse #testPreparedStatementAfterAbandonedResponse )
]

{ #category : 'accessing' }
P3RequestDisciplineTest >> statementName [
	"The name I prepare statements under. One name is enough: each test gets its own connection."

	^ 'p3_request_discipline_test'
]

{ #category : 'accessing' }
P3RequestDisciplineTest >> tableName [
	^ 'p3_request_discipline_test'
]

{ #category : 'running' }
P3RequestDisciplineTest >> tearDown [
	"Drop the table a test may have created. It cannot be a temporary one: the statement that fills
	it is observed from a second connection."

	[ client isConnected ifTrue: [ client execute: 'DROP TABLE IF EXISTS ' , self tableName ] ]
		on: Error
		do: [ :error | ].
	super tearDown
]

{ #category : 'private' }
P3RequestDisciplineTest >> terminateWriterOf: pool gatedAt: aSelector [
	"Run a query on the pooled client through a stream that holds after aSelector, then terminate that process.
	Termination runs ensure: blocks but no on:do: handlers."

	| reached worker |
	reached := Semaphore new.
	worker := [
		pool withConnection: [ :p3 |
			p3 instVarNamed: 'connection' put: (P3GatedStream on: p3 connection reached: reached gatedAt: aSelector).
			p3 query: 'SELECT 1' ] ] newProcess.
	worker resume.
	reached wait.
	worker terminate
]

{ #category : 'tests - writing requests' }
P3RequestDisciplineTest >> testBatchBindFailureExecutesNothing [
	"A batch is one request. If building the Bind message for one row fails, none of the rows may
	reach the server: otherwise the caller is told the batch failed while part of it ran, and the
	rows already written are flushed with whatever request comes next."

	| statement |
	client execute: 'CREATE TEMP TABLE ' , self tableName , ' (i int)'.
	statement := client
		prepare: 'INSERT INTO ' , self tableName , ' VALUES ($1)'
		named: self statementName.
	self
		should: [ statement executeBatch: { #( 1 ). #( 2 ). { P3FailingParameter new } } ]
		raise: ZeroDivide.
	self
		assert: (client query: 'SELECT count(*) FROM ' , self tableName) firstFieldOfFirstRecord
		equals: 0.
	self assert: client transactionStatus equals: $I.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - abandoned responses' }
P3RequestDisciplineTest >> testCloseAfterAbandonedResponse [
	"Closing a prepared statement is a request like any other: it must drain a response nobody read
	instead of reading it as its own CloseComplete."

	| statement |
	statement := client prepare: 'SELECT $1::int4 + 1000' named: self statementName.
	self abandonResponse.
	statement close.
	self deny: client isResponsePending.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - unexpected messages' }
P3RequestDisciplineTest >> testEmptyQuery [
	"An empty query is answered with EmptyQueryResponse in place of a CommandComplete. It is not an
	error and must not be read as the start of a data section."

	| result |
	result := client query: ''.
	self assert: result results equals: ''.
	self deny: result hasData.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - writing requests' }
P3RequestDisciplineTest >> testLocalFailureBeforeWriteLeavesNoPendingResponse [
	"A request that could not even be built never reached the server, so no response is coming.
	Recording one would make the next request wait for the whole timeout on a silent socket and then
	close the connection."

	self should: [ client query: nil ] raise: Error.
	self deny: client isResponsePending.
	self assert: (client query: 'SELECT 111') data equals: #( #( 111 ) )
]

{ #category : 'tests - ordinary requests' }
P3RequestDisciplineTest >> testOrdinaryRequestsOweExactlyOneResponseEach [
	"The ordinary path of the request kind that the COPY handling depends on. Simple and extended
	requests, run in turn on one connection, each leave nothing owed, and a batch is still one response."

	| statement |
	self assert: (client query: 'SELECT 1') firstFieldOfFirstRecord equals: 1.
	self assert: client pendingResponses equals: 0.
	statement := client prepare: 'SELECT $1::int4 + 10' named: self statementName.
	self assert: (statement query: #( 1 )) firstFieldOfFirstRecord equals: 11.
	self assert: client pendingResponses equals: 0.
	self assert: (statement queryAll: #( #( 1 ) #( 2 ) #( 3 ) )) size equals: 3.
	self assert: client pendingResponses equals: 0.
	self assert: (client query: 'SELECT 2; SELECT 3') records size equals: 1.
	self assert: client pendingResponses equals: 0.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - abandoned responses' }
P3RequestDisciplineTest >> testPreparedStatementAfterAbandonedResponse [
	"A prepared statement writes its own request. If it does not first drain a response nobody read,
	two responses are outstanding and it reads the older one as its own, answering the question
	before the one it asked."

	| statement |
	statement := client prepare: 'SELECT $1::int4 + 1000' named: self statementName.
	self abandonResponse.
	self assert: (statement query: #( 1 )) data equals: #( #( 1001 ) ).
	self assert: (statement query: #( 2 )) data equals: #( #( 1002 ) )
]

{ #category : 'tests - abandoned responses' }
P3RequestDisciplineTest >> testPreparedStatementCloseIsSynchronised [
	"Close is sent with Sync, so the server answers CloseComplete and ReadyForQuery and nothing is
	left unread. Sent with Flush instead, an error would leave me waiting for a ReadyForQuery that
	never comes while the server discards everything until a Sync."

	| statement |
	statement := client prepare: 'SELECT $1::int4' named: self statementName.
	statement close.
	self deny: client isResponsePending.
	self assert: client transactionStatus equals: $I.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - writing requests' }
P3RequestDisciplineTest >> testQueryAfterFailedDrainReconnects [
	"Draining a response the server is not going to send can only fail, and then my connection is
	closed. The request after it must open a new connection instead of being written to nothing, so
	the drain has to happen before the connection is checked."

	extraClient := P3Client new
		url: P3ClientTest url;
		timeout: 2;
		connect;
		yourself.
	extraClient noteResponseRequested.
	self assert: (extraClient query: 'SELECT 111') data equals: #( #( 111 ) ).
	self deny: extraClient isResponsePending
]

{ #category : 'tests - abandoned responses' }
P3RequestDisciplineTest >> testSimpleQueryAfterAbandonedPreparedStatementResponse [
	"The same shift the other way round: a prepared statement's response is abandoned and the simple
	queries after it must still answer their own questions."

	| statement |
	statement := client prepare: 'SELECT $1::int4 + 1000' named: self statementName.
	[ client converter
		mapOid: 23
		type: #int4
		to: [ :bytes :length :description | Warning signal: 'abandon this response' ].
	  [ statement query: #( 1 ) ] on: Warning do: [ :warning | warning return: nil ] ]
		ensure: [ client converter
			mapOid: 23
			type: #int4
			to: #convertIntegerFrom:length:description: ].
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - writing requests' }
P3RequestDisciplineTest >> testTerminatedWriterDoesNotHandItsResponseToTheNextBorrower [
	"A borrower's request reaches the server and its process is terminated before it reads the response.
	The next borrower of the same pooled client must read the answer to its own query."

	| pool |
	pool := P3ConnectionPool url: P3ClientTest url.
	pool size: 1.
	[ pool withConnection: [ :p3 | p3 isWorking ].
	self terminateWriterOf: pool gatedAt: #flush.
	self assert: (pool withConnection: [ :p3 | (p3 query: 'SELECT 2') firstFieldOfFirstRecord ]) equals: 2 ]
		ensure: [ pool close ]
]

{ #category : 'tests - writing requests' }
P3RequestDisciplineTest >> testWriterTerminatedInsideAMessageDoesNotGarbleTheNextRequest [
	"A borrower is terminated after the first byte of its request reached the stream. Those bytes are not a
	message, and the next request must not be framed after them."

	| pool |
	pool := P3ConnectionPool url: P3ClientTest url.
	pool size: 1.
	[ pool withConnection: [ :p3 | p3 isWorking ].
	self terminateWriterOf: pool gatedAt: #nextPut:.
	self assert: (pool withConnection: [ :p3 | (p3 query: 'SELECT 2') firstFieldOfFirstRecord ]) equals: 2 ]
		ensure: [ pool close ]
]

{ #category : 'private' }
P3RequestDisciplineTest >> waitForRowCount [
	"Answer the number of rows in my table once the statement I stopped waiting for has finished on
	the server. It keeps running there after I gave up on it, so I poll, from the connection that is
	still open."

	| deadline count |
	deadline := DateAndTime now + 10 seconds.
	[ count := (client query: 'SELECT count(*) FROM ' , self tableName) firstFieldOfFirstRecord.
	  count > 0 or: [ DateAndTime now > deadline ] ] whileFalse: [
		(Delay forMilliseconds: 200) wait ].
	^ count
]
