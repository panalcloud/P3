"
I test P3Interval against the live server. The server is the oracle, nothing it prints is copied into an expectation. I choose the six fields, the server builds or parses the interval, and I compare meaning: months, days and one signed time value, which is how the server stores an interval. A time part that mixes signs is not generated, see the class comment of P3Interval.
"
Class {
	#name : 'P3IntervalServerTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3IntervalServerTest >> allFields [
	^ self fixedFields , self randomFields
]

{ #category : 'private' }
P3IntervalServerTest >> assertMeaning: actual equals: expected description: aString [
	self
		assert: (actual first = expected first and: [ actual second = expected second and: [ (actual last - expected last) abs < 0.000001 ] ])
		description: aString , ': got ' , actual printString , ', wanted ' , expected printString
]

{ #category : 'fixtures' }
P3IntervalServerTest >> fixedFields [
	"Years, months, days, hours, minutes and seconds. The time part has one sign."

	^ #(
		#(0 0 0 0 0 0)
		#(1 2 3 4 5 6)
		#(0 0 0 0 0 -1.5)
		#(0 0 0 0 -30 0)
		#(0 0 0 -1 0 0)
		#(0 0 0 -1 -2 -3)
		#(0 0 1 0 0 -1)
		#(-1 0 3 0 0 0)
		#(0 -1 1 0 0 0)
		#(-1 -2 3 -4 -5 -6.789)
		#(-1 -1 -1 -1 -1 -1)
		#(0 0 0 100 0 0)
		#(0 0 0 0 0 0.000001)
		#(0 0 0 0 0 -0.000001)
		#(0 0 -400 0 59 59.999) )
]

{ #category : 'private' }
P3IntervalServerTest >> intervalFrom: fields [
	^ P3Interval
		years: fields first
		months: (fields at: 2)
		days: (fields at: 3)
		hours: (fields at: 4)
		minutes: (fields at: 5)
		seconds: fields last
]

{ #category : 'private' }
P3IntervalServerTest >> makeIntervalSqlFrom: fields [
	"The server builds the interval from the same six numbers, without any text format of mine."

	^ 'make_interval(years => {1}, months => {2}, days => {3}, hours => {4}, mins => {5}, secs => {6})'
		format: (fields collect: [ :each | each isFloat ifTrue: [ each printShowingDecimalPlaces: 6 ] ifFalse: [ each printString ] ])
]

{ #category : 'private' }
P3IntervalServerTest >> meaningOf: anInterval [
	"Months, days and the time part as one signed number of seconds: how the server stores an interval."

	^ {
		anInterval years * 12 + anInterval months.
		anInterval days.
		anInterval hours * 3600 + (anInterval minutes * 60) + anInterval seconds }
]

{ #category : 'fixtures' }
P3IntervalServerTest >> randomFields [
	"Answer 150 field tuples from a fixed seed. Year, month and day signs are independent, the time part has one sign."

	| random |
	random := Random seed: 20260930.
	^ (1 to: 150) collect: [ :each | | timeSign |
		timeSign := (random nextInt: 2) = 1 ifTrue: [ 1 ] ifFalse: [ -1 ].
		{ (random nextInt: 21) - 11.
		(random nextInt: 25) - 13.
		(random nextInt: 801) - 401.
		timeSign * ((random nextInt: 3) = 1 ifTrue: [ 0 ] ifFalse: [ (random nextInt: 200) - 1 ]).
		timeSign * ((random nextInt: 3) = 1 ifTrue: [ 0 ] ifFalse: [ (random nextInt: 60) - 1 ]).
		timeSign * ((random nextInt: 3) = 1 ifTrue: [ 0 ] ifFalse: [ ((random nextInt: 60000) - 1) / 1000.0 ]) } ]
]

{ #category : 'tests-writing' }
P3IntervalServerTest >> testBoundIntervalEqualsOneTheServerBuilds [
	"The server compares what P3 wrote with an interval it builds from the same fields."

	self allFields do: [ :fields |
		self
			assert: (self valueOf: 'SELECT $1::interval = ' , (self makeIntervalSqlFrom: fields) with: { self intervalFrom: fields })
			description: 'formatted write of ' , fields printString.
		self
			assert: (self preparedValueOf: 'SELECT $1::interval = ' , (self makeIntervalSqlFrom: fields) with: { self intervalFrom: fields })
			description: 'prepared write of ' , fields printString ]
]

{ #category : 'tests-reading' }
P3IntervalServerTest >> testIntervalInsideArithmeticIsReadWithTheSameMeaning [
	"Interval arithmetic gives mixed signs between the date and the time part, as the server decides."

	| other |
	other := self fixedFields at: 10.
	self allFields do: [ :fields | | read expected |
		read := self valueOf: 'SELECT ' , (self makeIntervalSqlFrom: fields) , ' - ' , (self makeIntervalSqlFrom: other) with: #().
		expected := (self meaningOf: (self intervalFrom: fields)) with: (self meaningOf: (self intervalFrom: other)) collect: [ :a :b | a - b ].
		self
			assertMeaning: (self meaningOf: read)
			equals: expected
			description: 'read of ' , fields printString , ' minus ' , other printString ]
]

{ #category : 'tests-writing' }
P3IntervalServerTest >> testIntervalRoundTripKeepsItsMeaning [
	"P3 writes, the server parses and returns the value, P3 reads it. A writer and a reader error that cancel out are only caught by the one-direction tests."

	self allFields do: [ :fields | | sent |
		sent := self intervalFrom: fields.
		self
			assertMeaning: (self meaningOf: (self valueOf: 'SELECT $1::interval' with: { sent }))
			equals: (self meaningOf: sent)
			description: 'formatted round trip of ' , fields printString.
		self
			assertMeaning: (self meaningOf: (self preparedValueOf: 'SELECT $1::interval' with: { sent }))
			equals: (self meaningOf: sent)
			description: 'prepared round trip of ' , fields printString ]
]

{ #category : 'tests-reading' }
P3IntervalServerTest >> testNegatedIntervalIsReadWithTheNegatedMeaning [
	"The server negates the interval, so every sign form it chooses to write is exercised."

	self allFields do: [ :fields | | read expected |
		read := self valueOf: 'SELECT -(' , (self makeIntervalSqlFrom: fields) , ')' with: #().
		expected := self meaningOf: (self intervalFrom: fields).
		self
			assertMeaning: (self meaningOf: read)
			equals: (expected collect: [ :each | each negated ])
			description: 'read of negated ' , fields printString ]
]

{ #category : 'tests-reading' }
P3IntervalServerTest >> testServerBuiltIntervalIsReadWithTheSameMeaning [
	"The server builds the interval from the fields. What P3 reads must mean the same."

	self allFields do: [ :fields | | read |
		read := self valueOf: 'SELECT ' , (self makeIntervalSqlFrom: fields) with: #().
		self
			assertMeaning: (self meaningOf: read)
			equals: (self meaningOf: (self intervalFrom: fields))
			description: 'read of ' , fields printString ]
]
