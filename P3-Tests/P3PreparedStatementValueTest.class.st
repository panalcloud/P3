Class {
	#name : 'P3PreparedStatementValueTest',
	#superclass : 'P3StatementValueTest',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3PreparedStatementValueTest >> insertBatch: rows [
	| statement |
	statement := client prepare: 'INSERT INTO p3_batch_probe VALUES ($1)'.
	[ statement executeBatch: rows ] ensure: [ statement close ]
]

{ #category : 'helpers' }
P3PreparedStatementValueTest >> rowsOf: sqlTemplate with: arguments [
	| statement |
	statement := client prepare: sqlTemplate.
	^ [ (statement query: arguments) records ] ensure: [ statement close ]
]

{ #category : 'helpers' }
P3PreparedStatementValueTest >> valueOf: sqlTemplate with: arguments [
	^ self preparedValueOf: sqlTemplate with: arguments
]
