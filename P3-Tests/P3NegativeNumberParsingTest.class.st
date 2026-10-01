"
Tests that P3Converter reads signed and exponent number text from the server into the right value. Each test selects a literal and compares the object read back. Tests that keep working values green sit next to the ones that show a defect, so the boundary of the problem is visible.
"
Class {
	#name : 'P3NegativeNumberParsingTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3NegativeNumberParsingTest >> assertInterval: anIntervalSql fields: expectedFields [
	"expectedFields is years, months, days, hours, minutes and seconds, in that order."

	| interval actual |
	interval := self readOf: 'SELECT ' , anIntervalSql.
	actual := { interval years. interval months. interval days. interval hours. interval minutes. interval seconds }.
	self
		assert: ((actual with: expectedFields collect: [ :got :wanted | got closeTo: wanted ]) allSatisfy: [ :each | each ])
		description: anIntervalSql , ' was read as ' , actual printString , ' and not as ' , expectedFields printString
]

{ #category : 'helpers' }
P3NegativeNumberParsingTest >> readOf: aSelectSql [
	"Answer the first value that the server sends for aSelectSql, converted by P3."

	^ (client query: aSelectSql) firstFieldOfFirstRecord
]

{ #category : 'tests-float' }
P3NegativeNumberParsingTest >> testFloat4WithPositiveExponent [
	self assert: (self readOf: 'SELECT 1e10::float4') equals: 1.0e10
]

{ #category : 'tests-float' }
P3NegativeNumberParsingTest >> testFloatArrayWithPositiveExponent [
	self assert: (self readOf: 'SELECT ARRAY[1e20, -1e20]::float8[]') equals: #(1.0e20 -1.0e20)
]

{ #category : 'tests-float' }
P3NegativeNumberParsingTest >> testFloatWithPositiveExponent [
	"The server writes large floats as 1e+100. The sign after the e must not end the number."

	self assert: (self readOf: 'SELECT 1e100::float8') equals: 1.0e100.
	self assert: (self readOf: 'SELECT 1e15::float8') equals: 1.0e15.
	self assert: (self readOf: 'SELECT 1.5e20::float8') equals: 1.5e20.
	self assert: (self readOf: 'SELECT 123456789012345678::float8') equals: 123456789012345678 asFloat
]

{ #category : 'tests-interval' }
P3NegativeNumberParsingTest >> testIntervalWithExplicitPlusSign [
	"The server writes +3 days when the interval mixes signs. The reader must accept the plus sign."

	self assertInterval: '''-1 mon +1 day''::interval' fields: #(0 -1 1 0 0 0).
	self
		assertInterval: 'make_interval(years => -1, months => -2, days => 3, hours => -4, mins => -5, secs => -6.789)'
		fields: #(-1 -2 3 -4 -5 -6.789)
]

{ #category : 'tests-float' }
P3NegativeNumberParsingTest >> testNegativeFloatWithPositiveExponent [
	self assert: (self readOf: 'SELECT (-1e20)::float8') equals: -1.0e20.
	self assert: (self readOf: 'SELECT (-1.5e+300)::float8') equals: -1.5e300
]

{ #category : 'tests-float' }
P3NegativeNumberParsingTest >> testNegativeFloatsWithoutPositiveExponentAreRead [
	self assert: (self readOf: 'SELECT (-0.5)::float8') equals: -0.5.
	self assert: (self readOf: 'SELECT (-1.5e-7)::float8') equals: -1.5e-7.
	self assert: (self readOf: 'SELECT (-123456789.125)::float8') equals: -123456789.125.
	self assert: (self readOf: 'SELECT (-2.5)::float4') equals: -2.5
]

{ #category : 'tests-integer' }
P3NegativeNumberParsingTest >> testNegativeIntegersAreRead [
	self assert: (self readOf: 'SELECT (-32768)::int2') equals: -32768.
	self assert: (self readOf: 'SELECT (-2147483648)::int4') equals: -2147483648.
	self assert: (self readOf: 'SELECT (-9223372036854775808)::int8') equals: -9223372036854775808
]

{ #category : 'tests-interval' }
P3NegativeNumberParsingTest >> testNegativeIntervalsThatReadCorrectly [
	"Guards: these forms are read right today and must stay so."

	self assertInterval: '''-1 day -02:00:00''::interval' fields: #(0 0 -1 -2 0 0).
	self assertInterval: '''-5 months''::interval' fields: #(0 -5 0 0 0 0).
	self assertInterval: '''-1 hour''::interval' fields: #(0 0 0 -1 0 0).
	self assertInterval: '''-1 year''::interval' fields: #(-1 0 0 0 0 0)
]

{ #category : 'tests-integer' }
P3NegativeNumberParsingTest >> testNegativeNumbersInArraysAreRead [
	self assert: (self readOf: 'SELECT ARRAY[-1,-2,3]::int4[]') equals: #(-1 -2 3).
	self assert: (self readOf: 'SELECT ARRAY[-1.5,2]::float8[]') equals: #(-1.5 2.0).
	self assert: (self readOf: 'SELECT ARRAY[-1,NULL]::int4[]') equals: #(-1 nil)
]

{ #category : 'tests-integer' }
P3NegativeNumberParsingTest >> testNegativeNumericsAreRead [
	self assert: (self readOf: 'SELECT (-0.5)::numeric') equals: -1 / 2.
	self assert: (self readOf: 'SELECT (-123.456)::numeric(10,3)') equals: -123456 / 1000.
	self assert: (self readOf: 'SELECT (-0.00001)::numeric') equals: -1 / 100000.
	self assert: (self readOf: 'SELECT (-1e20)::numeric') equals: (10 raisedTo: 20) negated
]

{ #category : 'tests-geometry' }
P3NegativeNumberParsingTest >> testNegativePointAndBoxAreRead [
	| point box |
	point := self readOf: 'SELECT ''(-1,-2.5)''::point'.
	self assert: point x equals: -1.
	self assert: point y equals: -2.5.
	box := self readOf: 'SELECT ''((-1,-2),(-3,-4))''::box'.
	self assert: box printString equals: '(-1,-2),(-3,-4)'
]

{ #category : 'tests-interval' }
P3NegativeNumberParsingTest >> testNegativeTimePartCarriesSignToMinutesAndSeconds [
	"The sign of hh:mm:ss belongs to the whole time part. -01:02:03 is minus one hour, two minutes and three seconds."

	self assertInterval: '''-01:02:03''::interval' fields: #(0 0 0 -1 -2 -3).
	self assertInterval: '''-01:02:03.5''::interval' fields: #(0 0 0 -1 -2 -3.5)
]

{ #category : 'tests-interval' }
P3NegativeNumberParsingTest >> testNegativeTimePartWithZeroHours [
	"With no hours, the minus sign sits on a zero and the sign of the time part is lost."

	self assertInterval: '''-00:00:01.5''::interval' fields: #(0 0 0 0 0 -1.5).
	self assertInterval: '''-00:30:00''::interval' fields: #(0 0 0 0 -30 0).
	self assertInterval: '''1 day -00:00:01''::interval' fields: #(0 0 1 0 0 -1)
]

{ #category : 'tests-float' }
P3NegativeNumberParsingTest >> testNegativeZeroKeepsItsSign [
	self assert: (self readOf: 'SELECT (''-0'')::float8') printString equals: '-0.0'
]
