"
Tests that P3FormattedStatement writes negative numbers so that a preceding minus sign does not start a SQL line comment. The literal tests inspect the bound SQL text. The server tests run the statement and check the result.
"
Class {
	#name : 'P3FormattedStatementNegativeNumberTest',
	#superclass : 'TestCase',
	#instVars : [
		'client'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3FormattedStatementNegativeNumberTest >> assertNoLineCommentIn: aValue [
	"A line comment ends the statement at the server, so the bound text must not hold two consecutive minus signs."

	| sql |
	sql := self boundSqlFor: aValue.
	self deny: (sql includesSubstring: '--') description: 'Bound SQL starts a comment: ' , sql
]

{ #category : 'helpers' }
P3FormattedStatementNegativeNumberTest >> boundSqlFor: aValue [
	"Answer the SQL text that a formatted statement writes when aValue is bound to $1 after a minus sign."

	^ (client format: 'SELECT 0-$1') bind: { aValue }
]

{ #category : 'running' }
P3FormattedStatementNegativeNumberTest >> setUp [
	super setUp.
	client := P3Client new.
	client url: P3ClientTest url.
	client timeout: 10. "second"
	client connect
]

{ #category : 'running' }
P3FormattedStatementNegativeNumberTest >> tearDown [
	client ifNotNil: [ client close ].
	super tearDown
]

{ #category : 'tests-literal' }
P3FormattedStatementNegativeNumberTest >> testLargeNegativeIntegerDoesNotStartComment [
	"A LargeNegativeInteger prints through a different class than a SmallInteger."

	self assertNoLineCommentIn: 100 factorial negated
]

{ #category : 'tests-server' }
P3FormattedStatementNegativeNumberTest >> testNegativeFloatAndDecimalSubtractionReadBack [
	self assert: (self valueOf: 'SELECT 0-$1::float8' with: { -2.5 }) equals: 2.5.
	self assert: (self valueOf: 'SELECT 0-$1::numeric' with: { -1.50s2 }) equals: 1.5
]

{ #category : 'tests-literal' }
P3FormattedStatementNegativeNumberTest >> testNegativeFloatDoesNotStartComment [
	self assertNoLineCommentIn: -2.5
]

{ #category : 'tests-literal' }
P3FormattedStatementNegativeNumberTest >> testNegativeNumberAfterMinusKeepsTrailingText [
	"Text after the placeholder must still be part of the statement."

	| sql |
	sql := (client format: 'SELECT 1-$1 AS a, ''kept'' AS b') bind: { -5 }.
	self assert: (sql includesSubstring: '''kept''')
]

{ #category : 'tests-server' }
P3FormattedStatementNegativeNumberTest >> testNegativeNumberDoesNotDropTrailingFilter [
	"The owner filter after the negative number must still apply. When it is lost as a comment, both rows match."

	| count |
	count := self
		valueOf: 'SELECT count(*) FROM (VALUES (1, ''a''), (10, ''b'')) AS t(balance, owner) WHERE balance > 0-$1 AND owner = $2'
		with: { -5. 'nobody' }.
	self assert: count equals: 0
]

{ #category : 'tests-server' }
P3FormattedStatementNegativeNumberTest >> testNegativeNumberStillMatchesTrailingFilter [
	"With the filter kept, the matching owner is found."

	| count |
	count := self
		valueOf: 'SELECT count(*) FROM (VALUES (1, ''a''), (10, ''b'')) AS t(balance, owner) WHERE balance > 0-$1 AND owner = $2'
		with: { -5. 'b' }.
	self assert: count equals: 1
]

{ #category : 'tests-literal' }
P3FormattedStatementNegativeNumberTest >> testNegativeScaledDecimalDoesNotStartComment [
	"A ScaledDecimal is printed by printScaledDecimal:on:, which is a separate code path."

	self assertNoLineCommentIn: -1.50s2
]

{ #category : 'tests-literal' }
P3FormattedStatementNegativeNumberTest >> testNegativeZeroFloatDoesNotStartComment [
	"-0.0 prints with a leading minus sign although it compares equal to zero."

	self assertNoLineCommentIn: -0.0
]

{ #category : 'tests-literal' }
P3FormattedStatementNegativeNumberTest >> testPositiveNumbersAreUnchanged [
	"The guard against comments must not change how positive numbers read."

	self assert: (self boundSqlFor: 5) equals: 'SELECT 0-5'.
	self assert: (self boundSqlFor: 2.5) equals: 'SELECT 0-2.5'.
	self assert: (self boundSqlFor: 1.50s2) equals: 'SELECT 0-1.50'
]

{ #category : 'tests-literal' }
P3FormattedStatementNegativeNumberTest >> testSmallNegativeIntegerDoesNotStartComment [
	"An integer is written with its own sign, so -5 after a minus sign gives 0--5."

	self assertNoLineCommentIn: -5
]

{ #category : 'tests-server' }
P3FormattedStatementNegativeNumberTest >> testSubtractingNegativeIntegerReadsBack [
	"0 minus -5 is 5. With a comment the statement is cut and the value is wrong or the query fails."

	self assert: (self valueOf: 'SELECT 0-$1' with: { -5 }) equals: 5
]

{ #category : 'helpers' }
P3FormattedStatementNegativeNumberTest >> valueOf: sqlTemplate with: arguments [
	"Format sqlTemplate, run it with arguments and answer the single value read back."

	^ ((client format: sqlTemplate) query: arguments) firstFieldOfFirstRecord
]
