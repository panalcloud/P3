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
	"Put the connection's transaction into the failed ($E) state the way ordinary application
	code does: an error inside BEGIN...COMMIT, caught and discarded."

	driver beginTransaction.
	[ driver connection query: 'SELECT 1/0' ] on: Error do: [ :error | ].
	self assert: driver connection transactionStatus equals: $E
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
