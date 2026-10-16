Class {
	#name : 'P3FormattedStatementValueTest',
	#superclass : 'P3StatementValueTest',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'accessing' }
P3FormattedStatementValueTest >> expectedFailures [
	^ #( #testDateAndTimeBoundAsTextCarryNoQuotes #testTimeKeepsFractionOfSecond )
]

{ #category : 'helpers' }
P3FormattedStatementValueTest >> refusedValueCode [
	^ 'P3060'
]

{ #category : 'tests' }
P3FormattedStatementValueTest >> testFractionIsAnExactDivision [
	"Written as (1/2) in SQL a fraction is an integer division and gives 0."

	self assert: (self valueOf: 'SELECT $1::numeric = 0.5' with: { 1 / 2 }) equals: true.
	self assert: (self valueOf: 'SELECT round($1 * 3)::int' with: { 1 / 3 }) equals: 1
]
