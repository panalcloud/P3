Class {
	#name : 'P3FormattedStatementValueTest',
	#superclass : 'P3StatementValueTest',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3FormattedStatementValueTest >> insertBatch: rows [
	(client format: 'INSERT INTO p3_batch_probe VALUES ($1)') executeBatch: rows
]
