"
Abstract. Tests how values bound to a statement reach the server and come back. The subclasses decide which kind of statement runs the SQL by implementing valueOf:with:, so the same tests check P3FormattedStatement and P3PreparedStatement. Results are compared on the server side where the Smalltalk reader could hide a defect of the writer.
"
Class {
	#name : 'P3StatementValueTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'testing' }
P3StatementValueTest class >> isAbstract [
	^ self == P3StatementValueTest
]

{ #category : 'helpers' }
P3StatementValueTest >> insertBatch: rows [
	"Insert each row of rows, an array holding one value, into a temporary table with one statement run as a batch. Answer nothing; the caller counts rows."

	self subclassResponsibility
]

{ #category : 'tests-text' }
P3StatementValueTest >> testArbitraryObjectIsRefused [
	"An object with no SQL meaning is refused. Its print string is neither SQL nor data."

	self assert: (self quietly: [ self valueOf: 'SELECT $1::text' with: { Object new } ]) equals: nil.
	self assert: (self quietly: [ self valueOf: 'SELECT $1::text' with: { Set with: 1 } ]) equals: nil
]

{ #category : 'tests-arrays' }
P3StatementValueTest >> testArraysReachServerIntact [
	self assert: (self valueOf: 'SELECT cardinality($1::int8[])' with: { #(1 2 3) }) equals: 3.
	self assert: (self valueOf: 'SELECT cardinality($1::int8[])' with: { #() }) equals: 0.
	self assert: (self valueOf: 'SELECT cardinality($1::int8[])' with: { #(#(1 2) #(3 4)) }) equals: 4.
	self assert: (self valueOf: 'SELECT ($1::text[])[1]' with: { #('a,b' 'c') }) equals: 'a,b'.
	self assert: (self valueOf: 'SELECT ($1::text[])[2] IS NULL' with: { { 'a'. nil } }) equals: true.
	self assert: (self valueOf: 'SELECT ''x'' = ANY($1::text[])' with: { #() }) equals: false
]

{ #category : 'tests-numbers' }
P3StatementValueTest >> testBooleansAndNil [
	self assert: (self valueOf: 'SELECT $1::boolean' with: { true }) equals: true.
	self assert: (self valueOf: 'SELECT $1::boolean' with: { false }) equals: false.
	self assert: (self valueOf: 'SELECT $1::text IS NULL' with: { nil }) equals: true
]

{ #category : 'tests-text' }
P3StatementValueTest >> testCharacterIsOneCharacterText [
	"A Character is not printed with its Smalltalk syntax $a."

	| value |
	value := self quietly: [ self valueOf: 'SELECT $1::text' with: { $a } ].
	self assert: value equals: 'a'
]

{ #category : 'tests-arrays' }
P3StatementValueTest >> testCharactersAndRefusedObjectsInArrays [
	"A Character in an array is one character text. An object with no SQL meaning is refused or
	stored unchanged, never written as its Smalltalk print string."

	self assert: (self valueOf: 'SELECT ($1::text[])[1]' with: { { $a } }) equals: 'a'.
	self assert: (self quietly: [ self valueOf: 'SELECT ($1::text[])[1]' with: { { Object new } } ]) equals: nil
]

{ #category : 'tests-dates' }
P3StatementValueTest >> testDateAndTimeBoundAsTextCarryNoQuotes [
	"A date or time bound to a text parameter is stored as its digits. The single quotes of an SQL
	literal are not part of the value."

	self
		assert: (self valueOf: 'SELECT $1::text' with: { Date newDay: 31 month: 1 year: 2024 })
		equals: '2024-01-31'.
	self
		assert: (self valueOf: 'SELECT $1::text' with: { Time hour: 13 minute: 5 second: 9 nanoSecond: 500000000 })
		equals: '13:05:09.5'
]

{ #category : 'tests-dates' }
P3StatementValueTest >> testDatesRoundTrip [
	{ Date newDay: 31 month: 1 year: 2024. Date newDay: 15 month: 3 year: 44. Date newDay: 1 month: 1 year: 1 }
		do: [ :each |
			self
				assert: (self valueOf: 'SELECT $1::date' with: { each }) = each
				description: 'Date did not round trip: ' , each printString ]
]

{ #category : 'tests-batch' }
P3StatementValueTest >> testFailedBatchLeavesNoRows [
	"A batch is one request. When its third row fails the first two must not stay."

	client execute: 'CREATE TEMP TABLE p3_batch_probe (n int4 PRIMARY KEY)'.
	self should: [ self insertBatch: { { 1 }. { 2 }. { 'x' }. { 4 } } ] raise: P3Error.
	self
		assert: (client query: 'SELECT count(*) FROM p3_batch_probe') firstFieldOfFirstRecord
		equals: 0
]

{ #category : 'tests-numbers' }
P3StatementValueTest >> testFractionIsNotRoundedDownOrRefused [
	"1/2 may be written as 0.5 or refused. Written as (1/2) in SQL it is an integer division and gives 0."

	| value |
	value := self quietly: [ self valueOf: 'SELECT $1::numeric' with: { 1 / 2 } ].
	value ifNotNil: [ self assert: value equals: 1 / 2 ]
]

{ #category : 'tests-numbers' }
P3StatementValueTest >> testLargeFloatReachesServerIntact [
	"The server compares the bound value, so the Smalltalk reader is not involved."

	self assert: (self valueOf: 'SELECT $1::float8 = ''1e100''::float8' with: { 1.0e100 }) equals: true.
	self assert: (self valueOf: 'SELECT $1::float8 = ''-1e20''::float8' with: { -1.0e20 }) equals: true.
	self assert: (self valueOf: 'SELECT $1::float8 = ''1e-300''::float8' with: { 1.0e-300 }) equals: true
]

{ #category : 'tests-negative numbers' }
P3StatementValueTest >> testNegativeFloatAfterMinus [
	self assert: (self valueOf: 'SELECT 0-$1::float8' with: { -2.5 }) equals: 2.5.
	self assert: (self valueOf: 'SELECT 0-$1::float8' with: { -1.0e-10 }) equals: 1.0e-10
]

{ #category : 'tests-negative numbers' }
P3StatementValueTest >> testNegativeIntegerAfterMinus [
	self assert: (self valueOf: 'SELECT 0-$1::int8' with: { -5 }) equals: 5.
	self assert: (self valueOf: 'SELECT 0-$1::numeric' with: { (2 raisedTo: 70) negated }) equals: (2 raisedTo: 70)
]

{ #category : 'tests-negative numbers' }
P3StatementValueTest >> testNegativeIntervalReachesServer [
	"The server compares the bound interval with one it builds itself, so the Smalltalk reader is not involved."

	| full hoursOnly secondsOnly |
	full := P3Interval new years: -1; months: -2; days: 3; hours: -4; minutes: -5; seconds: -6.789; yourself.
	hoursOnly := P3Interval new hours: -1; yourself.
	secondsOnly := P3Interval new seconds: -1.5; yourself.
	self
		assert: (self valueOf: 'SELECT $1::interval = make_interval(years => -1, months => -2, days => 3, hours => -4, mins => -5, secs => -6.789)' with: { full })
		equals: true.
	self
		assert: (self valueOf: 'SELECT $1::interval = make_interval(hours => -1)' with: { hoursOnly })
		equals: true.
	self
		assert: (self valueOf: 'SELECT $1::interval = make_interval(secs => -1.5)' with: { secondsOnly })
		equals: true
]

{ #category : 'tests-negative numbers' }
P3StatementValueTest >> testNegativeNumberInsideArray [
	self assert: (self valueOf: 'SELECT ($1::int8[])[1]' with: { #(-1 -2) }) equals: -1.
	self assert: (self valueOf: 'SELECT 0-($1::int8[])[2]' with: { #(-1 -2) }) equals: 2
]

{ #category : 'tests-negative numbers' }
P3StatementValueTest >> testNegativeScaledDecimalAfterMinus [
	self assert: (self valueOf: 'SELECT 0-$1::numeric' with: { -1.50s2 }) equals: 3 / 2.
	self assert: (self valueOf: 'SELECT 0-$1::numeric' with: { -0.05s2 }) equals: 1 / 20
]

{ #category : 'tests-numbers' }
P3StatementValueTest >> testNonFiniteFloatsReachServer [
	self assert: (self valueOf: 'SELECT $1::float8::text' with: { Float nan }) equals: 'NaN'.
	self assert: (self valueOf: 'SELECT $1::float8::text' with: { Float infinity }) equals: 'Infinity'.
	self assert: (self valueOf: 'SELECT $1::float8::text' with: { Float infinity negated }) equals: '-Infinity'
]

{ #category : 'tests-text' }
P3StatementValueTest >> testNulCharacterIsRefused [
	"PostgreSQL text cannot hold NUL, so the statement must fail instead of storing a cut value."

	self
		assert: (self quietly: [ self valueOf: 'SELECT $1::text' with: { String with: Character null } ])
		equals: nil
]

{ #category : 'tests-text' }
P3StatementValueTest >> testObjectPrintingAsSqlIsNotRun [
	"The print string of this object is a UNION. Running it adds a second row, so the value read back is not the bound object's text."

	| rows |
	rows := self quietly: [ (self rowsOf: 'SELECT $1::text' with: { P3SqlLookalike new }) ].
	rows ifNotNil: [ self assert: rows size equals: 1 ]
]

{ #category : 'tests-ordinary' }
P3StatementValueTest >> testSupportedValueTypesReachTheServerAndComeBack [
	"One ordinary value of every kind that a statement accepts, bound to a parameter of the matching
	type and read back. The builder refuses objects it has no text for, so this protects the ones it
	has: a type that stops being supported fails here, and not in an application."

	{
		{ 'SELECT $1::int8'. 42. 42 }.
		{ 'SELECT $1::int8'. -7. -7 }.
		{ 'SELECT $1::int8'. 0. 0 }.
		{ 'SELECT $1::numeric'. 2 raisedTo: 70. 2 raisedTo: 70 }.
		{ 'SELECT $1::numeric'. 12.50s2. 12.50s2 }.
		{ 'SELECT $1::numeric'. -0.25s2. -0.25s2 }.
		{ 'SELECT $1::float8'. 1.5. 1.5 }.
		{ 'SELECT $1::float8'. -2.25e10. -2.25e10 }.
		{ 'SELECT $1::boolean'. true. true }.
		{ 'SELECT $1::boolean'. false. false }.
		{ 'SELECT $1::text'. 'plain text'. 'plain text' }.
		{ 'SELECT $1::text'. #symbol. 'symbol' }.
		{ 'SELECT $1::text'. $x. 'x' }.
		{ 'SELECT $1::bytea'. #[ 0 1 92 255 ]. #[ 0 1 92 255 ] }.
		{ 'SELECT $1::date'. Date newDay: 29 month: 2 year: 2020. Date newDay: 29 month: 2 year: 2020 }.
		{ 'SELECT $1::time'. Time hour: 13 minute: 5 second: 9. Time hour: 13 minute: 5 second: 9 }.
		{ 'SELECT $1::uuid::text'. UUID fromString: '123e4567-e89b-42d3-a456-426614174000'. '123e4567-e89b-42d3-a456-426614174000' }.
		{ 'SELECT $1::text IS NULL'. nil. true } } do: [ :each |
			| value |
			value := self valueOf: each first with: { each second }.
			self
				assert: value = each third
				description: each first , ' with ' , each second printString , ' gave ' , value printString ]
]

{ #category : 'tests-text' }
P3StatementValueTest >> testTextRoundTrips [
	#('' 'plain' 'it''s' '"quoted"' 'ñ ü 日本 😀' 'a\b\' 'a;b -- c /* d */' '$1 $$ $tag$')
		do: [ :each |
			self
				assert: (self valueOf: 'SELECT $1::text' with: { each }) = each
				description: 'Text did not round trip: ' , each printString ]
]

{ #category : 'tests-dates' }
P3StatementValueTest >> testTimeKeepsFractionOfSecond [
	| value |
	value := self valueOf: 'SELECT $1::time' with: { Time hour: 13 minute: 5 second: 9 nanoSecond: 123456000 }.
	self assert: value nanoSecond equals: 123456000
]

{ #category : 'tests-dates' }
P3StatementValueTest >> testTimestampKeepsInstantAcrossOffsets [
	{ 0 hours. -5 hours. 5 hours + 30 minutes } do: [ :offset | | stamp value |
		stamp := DateAndTime year: 2024 month: 1 day: 31 hour: 10 minute: 0 second: 0 nanoSecond: 123456000 offset: offset.
		value := self valueOf: 'SELECT $1::timestamptz' with: { stamp }.
		self
			assert: value asUTC = stamp asUTC
			description: 'Instant changed for offset ' , offset printString ]
]

{ #category : 'tests-text' }
P3StatementValueTest >> testUuidReachesServerIntact [
	"A UUID is a ByteArray in the image, but the server expects the text form of a uuid, not bytea hex."

	| uuid |
	uuid := UUID fromString: '123e4567-e89b-42d3-a456-426614174000'.
	self assert: (self valueOf: 'SELECT $1::uuid::text' with: { uuid }) equals: '123e4567-e89b-42d3-a456-426614174000'.
	self assert: (self valueOf: 'SELECT ($1::uuid[])[1]::text' with: { { uuid } }) equals: '123e4567-e89b-42d3-a456-426614174000'
]
