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
P3RequestDisciplineTest >> testCopyInInAnAbandonedResponseIsRejectedWithoutHang [
	"A response abandoned half read is drained before the next request. If it contains a COPY FROM
	STDIN the drain must refuse it too, otherwise the next, innocent, request waits for the timeout."

	| elapsed |
	client execute: 'CREATE TEMP TABLE ' , self tableName , ' (i int)'.
	[ client converter
		mapOid: 23
		type: #int4
		to: [ :bytes :length :description | Warning signal: 'abandon this response' ].
	  [ client query: 'SELECT 7; COPY ' , self tableName , ' FROM STDIN' ]
		on: Warning
		do: [ :warning | warning return: nil ] ]
		ensure: [ client converter
			mapOid: 23
			type: #int4
			to: #convertIntegerFrom:length:description: ].
	self assert: client isResponsePending.
	elapsed := [ self assertConnectionAnswersItsOwnQueries ] timeToRun.
	self assert: elapsed < 2 seconds.
	self assert: client isConnected
]

{ #category : 'tests - unexpected messages' }
P3RequestDisciplineTest >> testCopyInIsRejectedWithoutHang [
	"COPY FROM STDIN makes the server wait for data I cannot send. It has to be refused at once, by
	telling the server to abandon the copy: waiting for the timeout and closing means the request is
	never answered, and reconnecting afterwards loses the temporary table it was written for."

	| elapsed |
	client execute: 'CREATE TEMP TABLE ' , self tableName , ' (i int)'.
	elapsed := [
		self should: [ client query: 'COPY ' , self tableName , ' FROM STDIN' ] raise: P3Error ]
			timeToRun.
	self assert: elapsed < 2 seconds.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - unexpected messages' }
P3RequestDisciplineTest >> testCopyInMetWhileRecoveringFromAFailureIsRejectedWithoutHang [
	"A conversion failure in the first statement of a multiple statement query leaves the rest of the
	response unread, and the second statement is a COPY FROM STDIN. The recovery reads that response
	to its end, so it meets the CopyInResponse and has to refuse it, or it waits for a ReadyForQuery
	that the server only sends after the copy."

	| elapsed |
	client execute: 'CREATE TEMP TABLE ' , self tableName , ' (i int)'.
	elapsed := [
		[ client converter
			mapOid: 23
			type: #int4
			to: [ :bytes :length :description | 1 / 0 ].
		self should: [ client query: 'SELECT 1; COPY ' , self tableName , ' FROM STDIN' ] raise: ZeroDivide ]
			ensure: [ client converter
				mapOid: 23
				type: #int4
				to: #convertIntegerFrom:length:description: ] ]
			timeToRun.
	self assert: elapsed < 2 seconds.
	self assert: client isConnected.
	self deny: client isResponsePending.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - unexpected messages' }
P3RequestDisciplineTest >> testCopyInRejectionOwesNoResponseAfterwards [
	"The Sync that follows CopyFail replaces the one the server dropped, so exactly one ReadyForQuery was
	owed and exactly one was read. A counter left above zero would make the next request drain, a counter
	hidden at zero would leave a ReadyForQuery in the socket: the second one is caught by the two
	queries, the first by the count."

	| statement |
	client execute: 'CREATE TEMP TABLE ' , self tableName , ' (i int)'.
	statement := client prepare: 'COPY ' , self tableName , ' FROM STDIN' named: self statementName.
	self should: [ statement execute: #() ] raise: P3Error.
	self assert: client pendingResponses equals: 0.
	self assert: client transactionStatus equals: $I.
	self assertConnectionAnswersItsOwnQueries.
	"A second refusal on the same connection behaves the same"
	self should: [ statement execute: #() ] raise: P3Error.
	self assert: client pendingResponses equals: 0.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - unexpected messages' }
P3RequestDisciplineTest >> testCopyInThroughPreparedStatementInsideATransactionKeepsTheConnection [
	"The server fails the transaction, as it does for any error. Closing the connection would turn that
	into a lost transaction, which is a different thing: the caller can still roll back."

	| statement |
	client execute: 'CREATE TEMP TABLE ' , self tableName , ' (i int)'.
	client execute: 'BEGIN'.
	statement := client prepare: 'COPY ' , self tableName , ' FROM STDIN' named: self statementName.
	self should: [ statement execute: #() ] raise: P3Error.
	self assert: client isConnected.
	self assert: client transactionStatus equals: $E.
	client execute: 'ROLLBACK'.
	self assert: client transactionStatus equals: $I.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - unexpected messages' }
P3RequestDisciplineTest >> testCopyInThroughPreparedStatementIsRejectedWithoutHang [
	"In the extended protocol the server ignores the Sync that ended the request while it waits for copy
	data, and after CopyFail it discards everything until a Sync it has not yet got. Without one, no
	ReadyForQuery comes: the client would wait for the whole timeout and then drop the connection,
	taking the temporary table with it."

	| statement elapsed |
	client execute: 'CREATE TEMP TABLE ' , self tableName , ' (i int)'.
	statement := client prepare: 'COPY ' , self tableName , ' FROM STDIN' named: self statementName.
	elapsed := [
		self should: [ statement execute: #() ] raise: P3Error ]
			timeToRun.
	self assert: elapsed < 2 seconds.
	self assert: client isConnected.
	self deny: client isResponsePending.
	self assert: (client query: 'SELECT count(*) FROM ' , self tableName) firstFieldOfFirstRecord equals: 0.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - unexpected messages' }
P3RequestDisciplineTest >> testCopyOutIsRejectedCleanly [
	"COPY TO STDOUT streams its data in messages I do not read. Report that instead of failing an
	assertion, and leave the connection at the start of the next response."

	self should: [ client query: 'COPY (SELECT 1) TO STDOUT' ] raise: P3Error.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - unexpected messages' }
P3RequestDisciplineTest >> testCopyOutThroughPreparedStatementIsRejectedCleanly [
	"COPY TO STDOUT in an extended request streams CopyData and CopyDone messages after the BindComplete.
	They have to be refused and skipped, with the one ReadyForQuery that the request owes read, and with
	no extra Sync sent: only a COPY FROM STDIN needs one."

	| statement elapsed |
	statement := client prepare: 'COPY (SELECT 1) TO STDOUT' named: self statementName.
	elapsed := [ self should: [ statement execute: #() ] raise: P3Error ] timeToRun.
	self assert: elapsed < 2 seconds.
	self assert: client isConnected.
	self assert: client pendingResponses equals: 0.
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

{ #category : 'tests - ordinary requests' }
P3RequestDisciplineTest >> testPrintingAConnectedClientDoesNotChangeIt [
	"Printing, inspecting and logging read the session. On a working connection that must leave
	everything as it was."

	| session |
	session := client session.
	self assert: session equals: (client query: 'SELECT pg_backend_pid()') firstFieldOfFirstRecord.
	client printString.
	client printStateOn: (WriteStream on: String new).
	self assert: client session equals: session.
	self assert: client isConnected.
	self deny: client isTransactionLost.
	self assert: client transactionStatus equals: $I.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - abandoned responses' }
P3RequestDisciplineTest >> testPrintingTheClientKeepsTheLostTransactionGuard [
	"Printing or inspecting a client reads its session. That must not forget that a transaction was lost,
	or the next statement would run in autocommit on a new connection."

	| error |
	client execute: 'BEGIN'.
	client closeAfterFailure.
	client printString.
	client session.
	error := [ client query: 'SELECT 1'. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil description: 'The client reconnected silently after a lost transaction'.
	self assert: error code equals: 'P3050'

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

{ #category : 'tests - retrying' }
P3RequestDisciplineTest >> testReconnectInsideTransactionSignals [
	"A connection lost while a transaction was open cannot be replaced by a fresh one. The server
	rolled that transaction back, so everything the caller still believes is inside it would run in
	autocommit, and its COMMIT would succeed having committed only part of the work. An explicit
	#connect is the caller saying it knows."

	client execute: 'BEGIN'.
	self assert: client transactionStatus equals: $T.
	client closeAfterFailure.
	self should: [ client query: 'SELECT 1' ] raise: P3Error.
	client connect.
	self assert: (client query: 'SELECT 111') data equals: #( #( 111 ) )
]

{ #category : 'tests - ordinary requests' }
P3RequestDisciplineTest >> testSessionIsNilWhenTheSocketIsGone [
	"When the socket is gone without the client having been told to close, the session that it
	remembers belongs to a backend that no longer serves it. #session answers nil, and still does not
	change anything. The next request reconnects, which is another session."

	| session |
	session := client session.
	self assert: session notNil.
	(client instVarNamed: 'connection') socket close.
	self deny: client isConnected.
	self assert: client session isNil.
	self assert: client session isNil.
	self assert: (client query: 'SELECT 5') firstFieldOfFirstRecord equals: 5.
	self assert: client session notNil.
	self deny: client session = session
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

{ #category : 'tests' }
P3RequestDisciplineTest >> testTimeoutIsNotRetriedAfterRequestSent [
	"A statement that runs longer than the timeout has already reached the server. Retrying it on a fresh
	connection would run it a second time. It is cancelled instead, so it runs zero times to completion, and the
	connection stays open. The elapsed time says that it was not retried: one attempt costs the timeout, a retry
	costs the retry delay and another full timeout on top of it."

	| elapsed |
	client execute: 'DROP TABLE IF EXISTS ' , self tableName.
	client execute: 'CREATE TABLE ' , self tableName , ' (i int)'.
	extraClient := P3Client new
		url: P3ClientTest url;
		timeout: 2;
		retryCount: 1;
		retryDelay: 1;
		connect;
		yourself.
	elapsed := [
		self
			should: [ extraClient execute: 'INSERT INTO ' , self tableName , ' SELECT 1 FROM pg_sleep(3)' ]
			raise: ConnectionTimedOut ] timeToRun.
	self assert: elapsed < 4 seconds.
	self assert: extraClient isConnected.
	(Delay forSeconds: 3) wait.
	self assert: (client query: 'SELECT count(*) FROM ' , self tableName) firstFieldOfFirstRecord equals: 0
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
