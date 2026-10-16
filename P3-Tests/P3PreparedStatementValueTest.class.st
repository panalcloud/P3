Class {
	#name : 'P3PreparedStatementValueTest',
	#superclass : 'P3StatementValueTest',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3PreparedStatementValueTest >> refusedValueCode [
	^ 'P3061'
]

{ #category : 'helpers' }
P3PreparedStatementValueTest >> rowsOf: sqlTemplate with: arguments [
	| statement |
	statement := client prepare: sqlTemplate.
	^ [ (statement query: arguments) records ] ensure: [ statement close ]
]

{ #category : 'tests' }
P3PreparedStatementValueTest >> testFractionIsRefused [
	"A parameter text is a decimal, and most fractions have no exact decimal text."

	self assertRefused: [ self valueOf: 'SELECT $1::numeric' with: { 1 / 3 } ]
]

{ #category : 'helpers' }
P3PreparedStatementValueTest >> valueOf: sqlTemplate with: arguments [
	^ self preparedValueOf: sqlTemplate with: arguments
]
