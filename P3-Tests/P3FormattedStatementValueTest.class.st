Class {
	#name : 'P3FormattedStatementValueTest',
	#superclass : 'P3StatementValueTest',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'accessing' }
P3FormattedStatementValueTest >> expectedFailures [
	^ #( #testFailedBatchLeavesNoRows )
]

{ #category : 'helpers' }
P3FormattedStatementValueTest >> refusedValueCode [
	^ 'P3060'
]

{ #category : 'tests' }
P3FormattedStatementValueTest >> testBatchInsideATransactionIsLeftToIt [
	"Inside the caller's transaction the batch opens none of its own; the caller commits or rolls back."

	client execute: 'CREATE TEMP TABLE p3_batch_probe (n int4)'.
	client execute: 'BEGIN'.
	(client format: 'INSERT INTO p3_batch_probe VALUES ($1)') executeBatch: { { 1 }. { 2 } }.
	self assert: client transactionStatus equals: $T.
	client execute: 'ROLLBACK'.
	self assert: (client query: 'SELECT count(*) FROM p3_batch_probe') firstFieldOfFirstRecord equals: 0
]

{ #category : 'tests' }
P3FormattedStatementValueTest >> testFailedBatchLeavesNoRows [
	"A batch is atomic. When its third row fails the first two must not stay."

	client execute: 'CREATE TEMP TABLE p3_batch_probe (n int4 PRIMARY KEY)'.
	self
		should: [ (client format: 'INSERT INTO p3_batch_probe VALUES ($1)') executeBatch: { { 1 }. { 2 }. { 'x' }. { 4 } } ]
		raise: P3Error.
	self assert: client transactionStatus equals: $I.
	self
		assert: (client query: 'SELECT count(*) FROM p3_batch_probe') firstFieldOfFirstRecord
		equals: 0
]

{ #category : 'tests' }
P3FormattedStatementValueTest >> testFractionIsAnExactDivision [
	"Written as (1/2) in SQL a fraction is an integer division and gives 0."

	self assert: (self valueOf: 'SELECT $1::numeric = 0.5' with: { 1 / 2 }) equals: true.
	self assert: (self valueOf: 'SELECT round($1 * 3)::int' with: { 1 / 3 }) equals: 1
]
