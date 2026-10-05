"
I test P3Interval reading and printing without a server. Reading uses the text the server writes in the 'postgres' IntervalStyle. Printing must give text the server accepts as input, so a negative component never produces a doubled sign.
"
Class {
	#name : 'P3IntervalTest',
	#superclass : 'TestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3IntervalTest >> assertRead: aString fields: expectedFields [
	"expectedFields is years, months, days, hours, minutes and seconds, in that order."

	| interval actual |
	interval := P3Interval readFrom: aString readStream.
	actual := { interval years. interval months. interval days. interval hours. interval minutes. interval seconds }.
	self
		assert: ((actual with: expectedFields collect: [ :got :wanted | got closeTo: wanted ]) allSatisfy: [ :each | each ])
		description: aString printString , ' was read as ' , actual printString , ' and not as ' , expectedFields printString
]

{ #category : 'tests-printing' }
P3IntervalTest >> testPrintNegativeDateParts [
	self
		assert: (P3Interval years: -1 months: -2 days: 3 hours: -4 minutes: -5 seconds: -6)
		printString
		equals: '-1 years -2 mons 3 days -04:05:06'
]

{ #category : 'tests-printing' }
P3IntervalTest >> testPrintNegativeTimePartHasOneSign [
	self assert: (P3Interval new hours: -4; minutes: -5; seconds: -6.789; yourself) printString equals: '-04:05:06.789'.
	self assert: (P3Interval new hours: -1; yourself) printString equals: '-01:00:00'.
	self assert: (P3Interval new seconds: -1.5; yourself) printString equals: '-00:00:01.5'.
	self assert: (P3Interval new minutes: -30; yourself) printString equals: '-00:30:00'
]

{ #category : 'tests-printing' }
P3IntervalTest >> testPrintNeverDoublesASign [
	| intervals |
	intervals := {
		P3Interval new hours: -1; yourself.
		P3Interval new seconds: -1.5; yourself.
		P3Interval years: -1 months: -2 days: 3 hours: -4 minutes: -5 seconds: -6.789.
		P3Interval years: 0 months: 0 days: -1 hours: 0 minutes: 0 seconds: -1 }.
	intervals do: [ :each |
		self deny: (each printString includesSubstring: '--') description: each printString.
		self deny: (each printString includesSubstring: ':-') description: each printString ]
]

{ #category : 'tests-printing' }
P3IntervalTest >> testPrintPositiveIntervalIsUnchanged [
	self
		assert: (P3Interval years: 1 months: 2 days: 3 hours: 5 minutes: 6 seconds: 7) printString
		equals: '1 year 2 mons 3 days 05:06:07'.
	self assert: P3Interval zero printString equals: '00:00:00'
]

{ #category : 'tests-printing' }
P3IntervalTest >> testPrintedIntervalReadsBackEqual [
	| intervals |
	intervals := {
		P3Interval zero.
		P3Interval years: 1 months: 2 days: 3 hours: 4 minutes: 5 seconds: 6.
		P3Interval new hours: -1; yourself.
		P3Interval new minutes: -30; yourself.
		P3Interval new seconds: -1.5; yourself.
		P3Interval years: -1 months: -2 days: 3 hours: -4 minutes: -5 seconds: -6.
		P3Interval years: 0 months: 0 days: 1 hours: 0 minutes: 0 seconds: -1 }.
	intervals do: [ :each |
		self
			assert: (P3Interval readFrom: each printString readStream)
			equals: each ]
]

{ #category : 'tests-reading' }
P3IntervalTest >> testReadAllNegative [
	"The server writes an interval that is negative in every field with one sign per field."

	self assertRead: '-1 years -1 mons -1 days -01:01:01' fields: #(-1 -1 -1 -1 -1 -1)
]

{ #category : 'tests-reading' }
P3IntervalTest >> testReadExplicitPlusSign [
	"The server writes a plus sign on a field that follows a negative one."

	self assertRead: '-1 mons +1 day' fields: #(0 -1 1 0 0 0).
	self assertRead: '-1 years +3 days' fields: #(-1 0 3 0 0 0).
	self assertRead: '-1 years -2 mons +3 days -04:05:06' fields: #(-1 -2 3 -4 -5 -6).
	self assertRead: '1 day +02:03:04' fields: #(0 0 1 2 3 4)
]

{ #category : 'tests-reading' }
P3IntervalTest >> testReadNegativeTimePartCarriesSignToAllFields [
	self assertRead: '-01:02:03' fields: #(0 0 0 -1 -2 -3).
	self assertRead: '-12:34:56.789' fields: #(0 0 0 -12 -34 -56.789).
	self assertRead: '1 day -01:02:03' fields: #(0 0 1 -1 -2 -3)
]

{ #category : 'tests-reading' }
P3IntervalTest >> testReadNegativeTimePartWithZeroHours [
	self assertRead: '-00:00:01.5' fields: #(0 0 0 0 0 -1.5).
	self assertRead: '-00:30:00' fields: #(0 0 0 0 -30 0).
	self assertRead: '1 day -00:00:01' fields: #(0 0 1 0 0 -1)
]

{ #category : 'tests-reading' }
P3IntervalTest >> testReadPositiveIntervals [
	self assertRead: '1 year 2 mons 3 days 04:05:06' fields: #(1 2 3 4 5 6).
	self assertRead: '00:00:00' fields: #(0 0 0 0 0 0).
	self assertRead: '2 days' fields: #(0 0 2 0 0 0).
	self assertRead: '01:02:03.5' fields: #(0 0 0 1 2 3.5)
]
