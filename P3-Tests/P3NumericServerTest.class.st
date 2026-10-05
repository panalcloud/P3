"
I test numeric values against the live server. The server builds finite values as mantissa / 10^scale and the image computes the same fraction with integers, so no text format is shared. NaN and the infinities have no ScaledDecimal: reading one signals a P3Error and the connection must keep answering its own queries after it.
"
Class {
	#name : 'P3NumericServerTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3NumericServerTest >> assertConnectionAnswersItsOwnQueries [
	"Two queries in a row: a response left unread shifts the first answer to the second query."

	self assert: (self readOf: 'SELECT 111') equals: 111.
	self assert: (self readOf: 'SELECT 222') equals: 222
]

{ #category : 'private' }
P3NumericServerTest >> errorOf: aBlock [
	"Answer the P3Error that aBlock signals. Fail when it signals nothing or another kind."

	^ [ aBlock value. self fail: 'a non finite numeric was read as a value' ]
		on: P3Error
		do: [ :error | error ]
]

{ #category : 'private' }
P3NumericServerTest >> nonFiniteLiterals [
	"The infinities of a numeric exist from PostgreSQL 14."

	^ (client isServerVersionAtLeastMajor: 14 minor: 0)
		ifTrue: [ #('NaN' 'Infinity' '-Infinity') ]
		ifFalse: [ #('NaN') ]
]

{ #category : 'fixtures' }
P3NumericServerTest >> pairs [
	"Mantissa and scale. The value is mantissa / 10^scale."

	| random |
	random := Random seed: 20260930.
	^ {
		0 -> 0.
		1 -> 0.
		-1 -> 3.
		15 -> 1.
		-25 -> 2.
		100 -> 2.
		(10 raisedTo: 30) -> 12.
		(10 raisedTo: 30) negated + 1 -> 12.
		1 -> 12 } , ((1 to: 100) collect: [ :each |
			((random nextInteger: (10 raisedTo: 28)) * ((random nextInteger: 2) = 1 ifTrue: [ 1 ] ifFalse: [ -1 ])) -> (random nextInteger: 12) ])
]

{ #category : 'private' }
P3NumericServerTest >> readOf: aSelectSql [
	^ (client query: aSelectSql) firstFieldOfFirstRecord
]

{ #category : 'private' }
P3NumericServerTest >> serverSqlOfPair: aPair [
	"The server multiplies by a negative power of ten, which is exact. A division would round to the digits the server chooses."

	^ '(({1})::numeric * power(10::numeric, {2}))' format: { aPair key printString. aPair value negated printString }
]

{ #category : 'tests-reading' }
P3NumericServerTest >> testConnectionAnswersItsOwnQueriesAfterNonFiniteNumeric [
	self nonFiniteLiterals do: [ :literal |
		self errorOf: [ self readOf: 'SELECT ''' , literal , '''::numeric' ].
		self assertConnectionAnswersItsOwnQueries ]
]

{ #category : 'tests-reading' }
P3NumericServerTest >> testFiniteNumericBuiltByServerIsReadExactly [
	self pairs do: [ :pair | | read |
		read := self readOf: 'SELECT ' , (self serverSqlOfPair: pair).
		self
			assert: read = (pair key / (10 raisedTo: pair value))
			description: pair printString , ': got ' , read printString ]
]

{ #category : 'tests-reading' }
P3NumericServerTest >> testNonFiniteNumericAmongFiniteRowsFailsTheWholeQuery [
	"The rows around the value are not returned: the error names the value that cannot be read, a partial result would hide it."

	| error |
	error := self errorOf: [
		self readOf: 'SELECT x FROM (VALUES (1.5::numeric), (''NaN''::numeric), (2.5::numeric)) AS v(x)' ].
	self assert: error code equals: 'P3034'.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests-reading' }
P3NumericServerTest >> testNonFiniteNumericInPreparedStatementSignalsP3Error [
	| error |
	error := self errorOf: [ self preparedValueOf: 'SELECT ''NaN''::numeric' with: #() ].
	self assert: error code equals: 'P3034'.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests-reading' }
P3NumericServerTest >> testNonFiniteNumericSignalsP3Error [
	self nonFiniteLiterals do: [ :literal | | error |
		error := self errorOf: [ self readOf: 'SELECT ''' , literal , '''::numeric' ].
		self assert: error code equals: 'P3034'.
		self assert: error isLocal.
		self assert: (error messageText includesSubstring: literal) description: error messageText ]
]
