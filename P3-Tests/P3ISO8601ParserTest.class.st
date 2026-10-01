"
P3ISO8601ParserTest holds tests for P3ISO8601Parser
"
Class {
	#name : 'P3ISO8601ParserTest',
	#superclass : 'TestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3ISO8601ParserTest >> assertRefused: aBlock description: aString [
	"aBlock must signal a P3Error, and not answer a value or fail some other way."

	| outcome |
	outcome := [ aBlock value ] on: P3Error do: [ :error | error ].
	self
		assert: (outcome isKindOf: P3Error)
		description: aString , ' was not refused, it gave ' , outcome printString
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testBeforeCommonEra [
	"The server prints year 1 BC as 0001 BC. The image counts astronomical years, where 1 BC is year 0 and
	44 BC is year -43."

	self
		assert: (P3ISO8601Parser on: '0044-03-15 BC') parseDate
		equals: (Date year: -43 month: 3 day: 15).
	self
		assert: (P3ISO8601Parser on: '0001-01-01 BC') parseDate
		equals: (Date year: 0 month: 1 day: 1).
	self
		assert: (P3ISO8601Parser on: '0044-03-15 10:00:00 BC') parseDateAndTime
		equals: (DateAndTime year: -43 month: 3 day: 15 hour: 10 minute: 0 second: 0 nanoSecond: 0 offset: Duration zero).
	self
		assert: (P3ISO8601Parser on: '0044-03-15 10:00:00.5+01 BC') parseDateAndTime
		equals: (DateAndTime year: -43 month: 3 day: 15 hour: 10 minute: 0 second: 0 nanoSecond: 500000000 offset: 1 hour).
	self
		assert: (P3ISO8601Parser on: '2020-03-15') parseDate year
		equals: 2020
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testDate [
	self 
		assert: (P3ISO8601Parser on: '2020-10-12') parseDate 
		equals: (Date year: 2020 month: 10 day: 12).
	self 
		assert: (P3ISO8601Parser on: '2020-02-29') parseDate 
		equals: (Date year: 2020 month: 02 day: 29).
	self 
		assert: (P3ISO8601Parser on: '2020-01-01') parseDate 
		equals: (Date year: 2020 month: 01 day: 01).
	self 
		assert: (P3ISO8601Parser on: '2020-12-31') parseDate 
		equals: (Date year: 2020 month: 12 day: 31).
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testDateAndTime [
	self 
		assert: (P3ISO8601Parser on: '2020-10-13 10:49:48.251174+02') parseDateAndTime
		equals: (DateAndTime year: 2020 month: 10 day: 13 hour: 10 minute: 49 second: 48 nanoSecond: 251174000 offset: 2 hours).
	self 
		assert: (P3ISO8601Parser on: '2020-10-13 10:49:48.251174') parseDateAndTime
		equals: (DateAndTime year: 2020 month: 10 day: 13 hour: 10 minute: 49 second: 48 nanoSecond: 251174000 offset: Duration zero).

]

{ #category : 'tests' }
P3ISO8601ParserTest >> testDateSeparatorsAndShapeAreStrict [
	"A date in another DateStyle must not be read as a different date. Year, month and day are
	separated by a dash, the year has four digits or more, month and day have two."

	#('31/01/2020' '31.01.2020' '01/01/0031' '01.01.0031' '01-01-0031' '2020/10/12' '2020-1-2' '2020-10' '2020' '20-10-12' '2020-10-12x' '2020-10-12 BCE' '' 'x')
		do: [ :each |
			self
				assertRefused: [ (P3ISO8601Parser on: each) parseDate ]
				description: 'date ' , each printString ]
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testInfinityIsRefused [
	"Date and DateAndTime have no infinite value. Answering a date for it would make 'valid until infinity' the year 0."

	| error |
	#('infinity' '-infinity') do: [ :each |
		self
			assertRefused: [ (P3ISO8601Parser on: each) parseDate ]
			description: 'date ' , each.
		self
			assertRefused: [ (P3ISO8601Parser on: each) parseDateAndTime ]
			description: 'timestamp ' , each ].
	error := [ (P3ISO8601Parser on: '-infinity') parseDate. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil.
	self assert: error code equals: 'P3038'.
	self assert: (error messageText includesSubstring: '-infinity')
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testLeapDayBeforeCommonEra [
	"1 BC (year 0) and 5 BC (year -4) are leap years. The image refuses 29 February there when it is
	asked for it directly, but it counts the days around it correctly."

	| date timestamp |
	date := (P3ISO8601Parser on: '0005-02-29 BC') parseDate.
	self assert: date year equals: -4.
	self assert: date monthIndex equals: 2.
	self assert: date dayOfMonth equals: 29.
	self assert: date next equals: (Date year: -4 month: 3 day: 1).
	self assert: (P3ISO8601Parser on: '0001-02-29 BC') parseDate dayOfMonth equals: 29.
	timestamp := (P3ISO8601Parser on: '0005-02-29 10:00:00+01 BC') parseDateAndTime.
	self assert: timestamp year equals: -4.
	self assert: timestamp monthIndex equals: 2.
	self assert: timestamp dayOfMonth equals: 29.
	self assert: timestamp hour equals: 10.
	self assert: timestamp offset equals: 1 hour.
	"A ZTimestamp is always UTC, so 10:00 at +01:00 is 09:00"
	timestamp := (P3ISO8601Parser on: '0005-02-29 10:00:00+01 BC') timestampClass: ZTimestamp; parseDateAndTime.
	self assert: timestamp dayOfMonth equals: 29.
	self assert: timestamp hour equals: 9.
	"A 29th of February that does not exist is still an error"
	self should: [ (P3ISO8601Parser on: '0100-02-29') parseDate ] raise: DateError.
	self should: [ (P3ISO8601Parser on: '0004-02-29 BC') parseDate ] raise: DateError
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testOffsetWithSeconds [
	"Zones used before 1900 have offsets such as +00:19:32. Dropping the seconds moves the instant."

	self
		assert: (P3ISO8601Parser on: '1900-01-01 00:00:00+00:19:32') parseDateAndTime offset
		equals: 1172 seconds.
	self
		assert: (P3ISO8601Parser on: '1900-01-01 00:00:00-00:19:32') parseDateAndTime offset
		equals: -1172 seconds.
	self
		assert: (P3ISO8601Parser on: '2020-10-13 10:49:48+05:30') parseDateAndTime offset
		equals: (5 * 3600 + (30 * 60)) seconds.
	self
		assert: (P3ISO8601Parser on: '2020-10-13 10:49:48-08') parseDateAndTime offset
		equals: -8 hours.
	self
		assert: (P3ISO8601Parser on: '2020-10-13 10:49:48.5+05:30:15') parseDateAndTime offset
		equals: (5 * 3600 + (30 * 60) + 15) seconds
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testTime [
	self 
		assert: (P3ISO8601Parser on: '07:08:09') parseTime
		equals: (Time hour: 7 minute: 8 second: 9).
	self 
		assert: (P3ISO8601Parser on: '01:02:03.000123') parseTime
		equals: (Time hour: 1 minute: 2 second: 3 nanoSecond: 123000).

]

{ #category : 'tests' }
P3ISO8601ParserTest >> testTimestampAndTimeShapeAreStrict [
	#('2020-10-13 10:49' '2020-10-13 10:49:48 garbage' '2020-10-13 10:49:48+' '2020-10-13 10:49:48+x' '2020-10-13 10:49:48.' '2020-10-13 10:49:48+02:' '2020-10-1310:49:48' '13/10/2020 10:49:48' '2020-10-13' '10:49:48' '')
		do: [ :each |
			self
				assertRefused: [ (P3ISO8601Parser on: each) parseDateAndTime ]
				description: 'timestamp ' , each printString ].
	#('07:08' '7:08:09' '07:08:09x' '07:08:09.' '07-08-09' '' 'x')
		do: [ :each |
			self
				assertRefused: [ (P3ISO8601Parser on: each) parseTime ]
				description: 'time ' , each printString ]
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testValuesTheServerCanPrintStillRead [
	"Strictness must not refuse what the server writes: years of five digits, a T separator, up to nine
	digits of fraction, and a time with a zone."

	self
		assert: (P3ISO8601Parser on: '10000-01-01') parseDate
		equals: (Date year: 10000 month: 1 day: 1).
	self
		assert: (P3ISO8601Parser on: '0001-01-01') parseDate
		equals: (Date year: 1 month: 1 day: 1).
	self
		assert: (P3ISO8601Parser on: '2020-10-13T10:49:48.251174') parseDateAndTime
		equals: (DateAndTime year: 2020 month: 10 day: 13 hour: 10 minute: 49 second: 48 nanoSecond: 251174000 offset: Duration zero).
	self
		assert: (P3ISO8601Parser on: '10:49:48.123456789') parseTime
		equals: (Time hour: 10 minute: 49 second: 48 nanoSecond: 123456789).
	self
		assert: (P3ISO8601Parser on: '10:49:48.5') parseTime nanoSecond
		equals: 500000000.
	self
		assert: (P3ISO8601Parser on: '10:49:48+05:30:15') parseTimeWithOffset
		equals: { Time hour: 10 minute: 49 second: 48. (5 * 3600 + (30 * 60) + 15) seconds }.
	self
		assert: (P3ISO8601Parser on: '10:49:48') parseTimeWithOffset
		equals: { Time hour: 10 minute: 49 second: 48. 0 seconds }
]

{ #category : 'tests' }
P3ISO8601ParserTest >> testZTimestamp [
	self 
		assert: ((P3ISO8601Parser on: '2020-10-13 10:49:48.251174+02') timestampClass: ZTimestamp; parseDateAndTime)
		equals: (ZTimestamp year: 2020 month: 10 day: 13 hour: 10 minute: 49 second: 48 nanoSecond: 251174000 offset: 2 hours).
	self 
		assert: ((P3ISO8601Parser on: '2020-10-13 10:49:48.251174') timestampClass: ZTimestamp; parseDateAndTime)
		equals: (ZTimestamp year: 2020 month: 10 day: 13 hour: 10 minute: 49 second: 48 nanoSecond: 251174000 offset: Duration zero).

]
