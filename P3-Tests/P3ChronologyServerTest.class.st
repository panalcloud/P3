"
I test the reading of dates and timestamps against the live server, for the values that the simple ISO format cannot hold: dates before the common era, infinite values and zone offsets with seconds. The server is the oracle: it builds each value from numbers I choose, and tells me the day count, the epoch or the offset in seconds to compare with, so no text that it prints is copied into an expectation.
"
Class {
	#name : 'P3ChronologyServerTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3ChronologyServerTest >> readOf: aSelectSql [
	^ (client query: aSelectSql) firstFieldOfFirstRecord
]

{ #category : 'tests' }
P3ChronologyServerTest >> testDatesBeforeCommonEraAreTheSameDayAsOnTheServer [
	"make_date takes a negative year for BC: -44 is 44 BC. The image counts astronomical years, 44 BC is -43.
	The server gives the number of days from 0001-01-01, and the image must be that many days away.
	5 BC (astronomical -4) is a leap year with a 29th of February, and so is 1 BC (year 0)."

	#(#(1 1 1) #(1 12 31) #(1 2 29) #(5 2 29) #(44 3 15) #(100 2 28) #(1000 7 4) #(4713 11 24)) do: [ :each | | date days sql |
		sql := 'make_date(' , each first negated printString , ', ' , each second printString , ', ' , each third printString , ')'.
		date := self readOf: 'SELECT ' , sql.
		days := self readOf: 'SELECT ' , sql , ' - date ''0001-01-01'''.
		self assert: date class equals: Date.
		self assert: date year equals: 1 - each first.
		self assert: date monthIndex equals: each second.
		self assert: date dayOfMonth equals: each third.
		self
			assert: (date - (Date year: 1 month: 1 day: 1)) days
			equals: days ]
]

{ #category : 'tests' }
P3ChronologyServerTest >> testInfiniteValuesAreRefusedAndTheConnectionSurvives [
	"There is no infinite Date or DateAndTime. The failure must name the value, and the connection must
	answer the next query as itself."

	#('SELECT ''infinity''::date' 'SELECT ''-infinity''::date' 'SELECT ''infinity''::timestamp' 'SELECT ''-infinity''::timestamptz')
		do: [ :each | | error |
			error := [ self readOf: each. nil ] on: P3Error do: [ :e | e ].
			self assert: error notNil description: each , ' did not signal'.
			self assert: error code equals: 'P3038'.
			self assert: (client query: 'SELECT 7') firstFieldOfFirstRecord equals: 7.
			self assert: (client query: 'SELECT 8') firstFieldOfFirstRecord equals: 8 ].
	"The text form is the way to read them."
	self assert: (self readOf: 'SELECT ''infinity''::date::text') equals: 'infinity'
]

{ #category : 'tests' }
P3ChronologyServerTest >> testTimeWithZoneKeepsOffsetSeconds [
	"12:00:00 at +05:30:15 is 06:29:45 in UTC."

	client execute: 'SET timezone = ''UTC'''.
	self
		assert: (self readOf: 'SELECT ''12:00:00+05:30:15''::timetz')
		equals: (Time hour: 6 minute: 29 second: 45).
	self
		assert: (self readOf: 'SELECT ''12:00:00+05:30''::timetz')
		equals: (Time hour: 6 minute: 30 second: 0)
]

{ #category : 'tests' }
P3ChronologyServerTest >> testTimestampsBeforeCommonEraAreTheSameInstantAsOnTheServer [
	"The same for timestamps with and without a zone, 15:30:45.5 in UTC. The leap day of 5 BC has no
	expected value built in the image, only the instant that the server computes."

	client execute: 'SET timezone = ''UTC'''.
	#(#(1 1 1) #(5 2 29) #(44 3 15) #(1000 7 4)) do: [ :each | | seconds args parsed |
		args := each first negated printString , ', ' , each second printString , ', ' , each third printString.
		seconds := self readOf: 'SELECT extract(epoch FROM make_timestamptz(' , args , ', 15, 30, 45.5, ''UTC''))::numeric'.
		parsed := self readOf: 'SELECT make_timestamptz(' , args , ', 15, 30, 45.5, ''UTC'')'.
		self
			assert: (parsed - self unixEpoch) asNanoSeconds
			equals: (seconds * 1000000000) asInteger.
		self assert: parsed year equals: 1 - each first.
		self assert: parsed monthIndex equals: each second.
		self assert: parsed dayOfMonth equals: each third.
		self
			assert: (self readOf: 'SELECT make_timestamp(' , args , ', 15, 30, 45.5)') - parsed
			equals: Duration zero ]
]

{ #category : 'tests' }
P3ChronologyServerTest >> testZoneOffsetWithSecondsIsKept [
	"Before the standard time zones, Amsterdam is at +00:19:32. The offset and the instant must be those
	of the server, to the second."

	client execute: 'SET timezone = ''Europe/Amsterdam'''.
	#('1900-01-01 00:00:00' '1850-01-01 12:00:00' '1879-06-15 23:59:59') do: [ :each | | sql parsed |
		sql := 'make_timestamptz(' , (each first: 4) , ', ' , (each copyFrom: 6 to: 7) asInteger printString , ', ' , (each copyFrom: 9 to: 10) asInteger printString , ', ' , (each copyFrom: 12 to: 13) asInteger printString , ', ' , (each copyFrom: 15 to: 16) asInteger printString , ', ' , (each copyFrom: 18 to: 19) asInteger printString , ', ''Europe/Amsterdam'')'.
		parsed := self readOf: 'SELECT ' , sql.
		self
			assert: parsed offset asSeconds
			equals: (self readOf: 'SELECT extract(timezone FROM ' , sql , ')::int').
		self
			assert: (parsed - self unixEpoch) asSeconds
			equals: (self readOf: 'SELECT extract(epoch FROM ' , sql , ')::int8') ]
]

{ #category : 'private' }
P3ChronologyServerTest >> unixEpoch [
	^ DateAndTime year: 1970 month: 1 day: 1 hour: 0 minute: 0 second: 0 nanoSecond: 0 offset: Duration zero
]
