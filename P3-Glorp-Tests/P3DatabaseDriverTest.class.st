"
I test P3DatabaseDriver's transaction protocol directly against a P3Client connection, without a Glorp session.

Once a transaction is in the failed ($E) state, COMMIT does not commit: PostgreSQL quietly runs a ROLLBACK instead and reports that as the command tag, with no error of its own. #commitTransaction must not let that pass as success.

Configure the connection through P3ClientTest class >> #url:, like the other tests in P3-Tests.
"
Class {
	#name : 'P3DatabaseDriverTest',
	#superclass : 'TestCase',
	#instVars : [
		'driver'
	],
	#category : 'P3-Glorp-Tests',
	#package : 'P3-Glorp-Tests'
}

{ #category : 'private' }
P3DatabaseDriverTest >> failTransaction [
	"Put the connection's transaction into the failed state the way ordinary application
	code does: an error inside BEGIN...COMMIT, caught and discarded."

	driver beginTransaction.
	[ driver connection query: 'SELECT 1/0' ] on: Error do: [ :error | ]
]

{ #category : 'private' }
P3DatabaseDriverTest >> serverPreparedStatementCount [
	"Answer the number of statements prepared in the session of the driver connection."

	^ (driver connection query: 'SELECT count(*) FROM pg_prepared_statements') firstFieldOfFirstRecord
]

{ #category : 'running' }
P3DatabaseDriverTest >> setUp [
	super setUp.
	driver := P3DatabaseDriver new.
	driver connection: (P3Client new
		url: P3ClientTest url;
		timeout: 10;
		connect;
		yourself)
]

{ #category : 'running' }
P3DatabaseDriverTest >> tearDown [
	driver connection ifNotNil: [ :aConnection |
		[ aConnection close ] on: Error do: [ :error | ] ].
	super tearDown
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingAStringToByteaSendsItsBytes [
	"Glorp gives the value of a bytea column as a String of bytes, which can hold a 0 byte"

	| bytes |
	bytes := String withAll: { Character null. $a. Character value: 255 }.
	driver connection execute: 'CREATE TEMP TABLE p3_binding_test (b bytea)'.
	driver basicExecuteSQLString: 'INSERT INTO p3_binding_test VALUES (?)' binding: { bytes }.
	driver basicExecuteSQLString: 'INSERT INTO p3_binding_test VALUES (?)' bindingRows: { { bytes } }.
	self
		assert: (driver connection query: 'SELECT b = ''\x0061ff''::bytea FROM p3_binding_test') data
		equals: #( #( true ) #( true ) )
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingAfterAnErrorInATransactionStillWorks [
	"A statement that fails inside a transaction stays usable after the rollback."

	driver beginTransaction.
	self should: [ driver basicExecuteSQLString: 'SELECT ?::int / ?::int' binding: #( 1 0 ) ] raise: P3Error.
	driver rollbackTransaction.
	self
		assert: (driver basicExecuteSQLString: 'SELECT ?::int / ?::int' binding: #( 7 1 )) upToEnd
		equals: #( #( 7 ) ).
	self assert: driver preparedStatementCount equals: 1
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingKeepsQuestionMarksInLiteralsAndIdentifiers [
	"A ? inside a string literal or a quoted identifier is not a placeholder."

	self
		assert: (driver basicExecuteSQLString: 'SELECT ''?'''' ?'' AS "a?b", ?::text' binding: #( 'x' )) upToEnd
		equals: #( #( '?'' ?' 'x' ) )
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingNumbersPlaceholdersInOrder [
	"Glorp writes ? placeholders. The driver sends them as $1, $2 in the same order."

	self
		assert: (driver basicExecuteSQLString: 'SELECT ?::int * 10 + ?::int' binding: #( 2 3 )) upToEnd
		equals: #( #( 23 ) )
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingPreparesEachStatementOnce [
	"The same SQL with other values runs the statement prepared the first time."

	driver basicExecuteSQLString: 'SELECT ?::int' binding: #( 1 ).
	self
		assert: (driver basicExecuteSQLString: 'SELECT ?::int' binding: #( 2 )) upToEnd
		equals: #( #( 2 ) ).
	self assert: driver preparedStatementCount equals: 1.
	self assert: self serverPreparedStatementCount equals: 1
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingRowsAnswersTheRowCountOfEachRow [
	"Each row of values runs the statement once. The driver answers the row count of each run, in order, and its rowCount is their sum."

	| counts |
	driver connection execute: 'CREATE TEMP TABLE p3_binding_test (i int)'.
	counts := driver basicExecuteSQLString: 'INSERT INTO p3_binding_test VALUES (?)' bindingRows: #( #( 1 ) #( 2 ) #( 3 ) ).
	self assert: counts asArray equals: #( 1 1 1 ).
	counts := driver basicExecuteSQLString: 'UPDATE p3_binding_test SET i = i * 10 WHERE i = ?' bindingRows: #( #( 1 ) #( 9 ) #( 3 ) ).
	self assert: counts asArray equals: #( 1 0 1 ).
	self assert: driver rowCount equals: 2.
	self
		assert: (driver connection query: 'SELECT i FROM p3_binding_test ORDER BY i') data
		equals: #( #( 2 ) #( 10 ) #( 30 ) )
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingRowsLargerThanTheBatchSizeRunEveryRow [
	"Rows are sent in requests of at most batchSize rows. All of them run, in order."

	| counts |
	driver batchSize: 2.
	driver connection execute: 'CREATE TEMP TABLE p3_binding_test (n serial, i int)'.
	counts := driver
		basicExecuteSQLString: 'INSERT INTO p3_binding_test (i) VALUES (?)'
		bindingRows: ((1 to: 5) collect: [ :each | { each } ]).
	self assert: counts asArray equals: #( 1 1 1 1 1 ).
	self
		assert: (driver connection query: 'SELECT i FROM p3_binding_test ORDER BY n') data
		equals: #( #( 1 ) #( 2 ) #( 3 ) #( 4 ) #( 5 ) )
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingSendsNilAsNull [

	self
		assert: (driver basicExecuteSQLString: 'SELECT ?::int IS NULL' binding: #( nil )) upToEnd
		equals: #( #( true ) )
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingSetsTheRowCount [

	driver connection execute: 'CREATE TEMP TABLE p3_binding_test (i int)'.
	driver connection execute: 'INSERT INTO p3_binding_test VALUES (1), (2), (3)'.
	driver basicExecuteSQLString: 'UPDATE p3_binding_test SET i = i + ? WHERE i > ?' binding: #( 10 1 ).
	self assert: driver rowCount equals: 2
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testBindingWithoutValuesRunsASimpleQuery [
	"No values: nothing is prepared."

	self assert: (driver basicExecuteSQLString: 'SELECT 1' binding: #()) upToEnd equals: #( #( 1 ) ).
	self assert: driver preparedStatementCount equals: 0.
	self assert: self serverPreparedStatementCount equals: 0
]

{ #category : 'tests' }
P3DatabaseDriverTest >> testCommitTransactionAfterFailureDoesNotLeaveDataCommitted [
	"Reproduce with a real write, not just an expectation that commitTransaction raises: a
	caller that swallows the earlier error and believes its write was saved must still find
	the row gone, since the server had already rolled it back."

	driver connection execute: 'CREATE TEMP TABLE p3_commit_test (i int)'.
	driver beginTransaction.
	driver connection execute: 'INSERT INTO p3_commit_test VALUES (1)'.
	[ driver connection query: 'SELECT 1/0' ] on: Error do: [ :error | ].
	[ driver commitTransaction ] on: Error do: [ :error | ].
	self
		assert: (driver connection query: 'SELECT count(*) FROM p3_commit_test') data
		equals: #( #( 0 ) )
]

{ #category : 'tests' }
P3DatabaseDriverTest >> testCommitTransactionAfterFailureSignals [
	"PostgreSQL answers a COMMIT on a failed transaction with the command tag 'ROLLBACK' and
	no error of its own. commitTransaction must not let that pass silently."

	self failTransaction.
	self should: [ driver commitTransaction ] raise: P3Error
]

{ #category : 'tests' }
P3DatabaseDriverTest >> testCommitTransactionAfterSuccessStillCommits [
	"An ordinary, successful commit must not turn into an error."

	driver connection execute: 'CREATE TEMP TABLE p3_commit_test (i int)'.
	driver beginTransaction.
	driver connection execute: 'INSERT INTO p3_commit_test VALUES (1)'.
	driver commitTransaction.
	self
		assert: (driver connection query: 'SELECT count(*) FROM p3_commit_test') data
		equals: #( #( 1 ) )
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testDriverSupportsBinding [

	self assert: driver supportsBinding.
	self assert: driver supportsBindingRows
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testLogoutForgetsPreparedStatements [

	driver basicExecuteSQLString: 'SELECT ?::int' binding: #( 1 ).
	driver logout.
	self assert: driver preparedStatementCount equals: 0
]

{ #category : 'tests - binding' }
P3DatabaseDriverTest >> testPreparedStatementsAreLimited [
	"Statements past the limit close the least recently used one, on the server too."

	driver preparedStatementLimit: 3.
	1 to: 5 do: [ :each |
		driver basicExecuteSQLString: 'SELECT ?::int + ' , each printString binding: #( 1 ) ].
	driver basicExecuteSQLString: 'SELECT ?::int + 3' binding: #( 1 ).
	driver basicExecuteSQLString: 'SELECT ?::int + 6' binding: #( 1 ).
	self assert: driver preparedStatementCount equals: 3.
	self assert: self serverPreparedStatementCount equals: 3.
	self
		assert: (driver connection query: 'SELECT statement FROM pg_prepared_statements ORDER BY statement') data
		equals: #( #( 'SELECT $1::int + 3' ) #( 'SELECT $1::int + 5' ) #( 'SELECT $1::int + 6' ) )
]
