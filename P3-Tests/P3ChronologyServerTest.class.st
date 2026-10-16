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
P3ChronologyServerTest >> testChronologyValuesAreFollowedByTheNextColumn [
	| record |
	client execute: 'SET timezone = ''UTC'''.
	record := (client query: 'SELECT date ''2024-02-29'', 7, timestamp ''2024-01-01 10:00:00.5'', ''x'', time ''10:00:00'', 8, timestamptz ''2024-01-01 10:00:00+00'', 9') firstRecord.
	self
		assert: record
		equals: {
			Date year: 2024 month: 2 day: 29. 7.
			DateAndTime year: 2024 month: 1 day: 1 hour: 10 minute: 0 second: 0 nanoSecond: 500000000 offset: Duration zero. 'x'.
			Time hour: 10 minute: 0 second: 0. 8.
			DateAndTime year: 2024 month: 1 day: 1 hour: 10 minute: 0 second: 0 nanoSecond: 0 offset: Duration zero. 9 }
]

{ #category : 'tests' }
P3ChronologyServerTest >> testDatesAndTimestampsAtTheLimitsOfFourDigitYears [
	"The year has four digits up to 9999 and more after it"

	client execute: 'SET timezone = ''UTC'''.
	#( #( 1 1 1 ) #( 9999 12 31 ) #( 10000 1 1 ) #( 2024 2 29 ) #( 1900 2 28 ) ) do: [ :each | | sql |
		sql := each first printString , ', ' , each second printString , ', ' , each third printString.
		self
			assert: (self readOf: 'SELECT make_date(' , sql , ')')
			equals: (Date year: each first month: each second day: each third).
		self
			assert: (self readOf: 'SELECT make_timestamp(' , sql , ', 23, 59, 59)')
			equals: (DateAndTime year: each first month: each second day: each third hour: 23 minute: 59 second: 59 nanoSecond: 0 offset: Duration zero) ]
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
P3ChronologyServerTest >> testFractionsOfASecondOfEveryLength [
	"The server writes as many digits of the fraction as it needs, up to six"

	client execute: 'SET timezone = ''UTC'''.
	#( '0' '0.1' '0.12' '0.123' '0.1234' '0.12345' '0.123456' '0.000001' '0.5' ) do: [ :seconds | | nanoSeconds |
		nanoSeconds := (seconds asNumber * 1000000000) rounded.
		self
			assert: (self readOf: 'SELECT make_timestamp(2020, 1, 2, 3, 4, ' , seconds , ')') nanoSecond
			equals: nanoSeconds.
		self
			assert: (self readOf: 'SELECT make_timestamptz(2020, 1, 2, 3, 4, ' , seconds , ', ''UTC'')') nanoSecond
			equals: nanoSeconds.
		self
			assert: (self readOf: 'SELECT make_time(3, 4, ' , seconds , ')') nanoSecond
			equals: nanoSeconds ]
]

{ #category : 'tests' }
P3ChronologyServerTest >> testInfiniteValuesAreRefusedAndTheConnectionSurvives [
	"There is no infinite Date or DateAndTime. The failure must name the value, and the connection must
	answer the next query as itself."

	#('SELECT ''infinity''::date' 'SELECT ''-infinity''::date' 'SELECT ''infinity''::timestamp' 'SELECT ''-infinity''::timestamptz')
		do: [ :each | | error |
			error := [ self readOf: each. nil ] on: P3Error do: [ :e | e ].
			self assert: error notNil description: each , ' did not signal'.
			self assert: error code equals: 'P3035'.
			self assert: (client query: 'SELECT 7') firstFieldOfFirstRecord equals: 7.
			self assert: (client query: 'SELECT 8') firstFieldOfFirstRecord equals: 8 ].
	"The text form is the way to read them."
	self assert: (self readOf: 'SELECT ''infinity''::date::text') equals: 'infinity'
]

{ #category : 'tests - ordinary values' }
P3ChronologyServerTest >> testOrdinaryDatesStillRead [
	"The parser got strict. Every date the server prints for a year of the common era must still read,
	for years of four digits and of five, and be the day that the server counts."

	#(#(1 1 1) #(1 12 31) #(4 2 29) #(1900 3 1) #(1970 1 1) #(2000 2 29) #(2020 10 13) #(9999 12 31) #(10000 1 1) #(12345 6 7)) do: [ :each | | sql date |
		sql := 'make_date(' , each first printString , ', ' , each second printString , ', ' , each third printString , ')'.
		date := self readOf: 'SELECT ' , sql.
		self assert: date class equals: Date.
		self assert: date year equals: each first.
		self assert: date monthIndex equals: each second.
		self assert: date dayOfMonth equals: each third.
		self
			assert: (date - (Date year: 1 month: 1 day: 1)) days
			equals: (self readOf: 'SELECT ' , sql , ' - date ''0001-01-01''') ]
]

{ #category : 'tests - ordinary values' }
P3ChronologyServerTest >> testOrdinaryTimestampsStillReadInEveryZone [
	"Timestamps with and without a fraction of a second, shown in zones with whole hour, half hour and
	quarter hour offsets and in daylight saving time. The offset and the instant are the server's."

	#('UTC' 'Europe/Amsterdam' 'America/New_York' 'Asia/Kolkata' 'Pacific/Chatham' 'America/St_Johns') do: [ :zone |
		client execute: 'SET timezone = ''' , zone , ''''.
		#('0' '45' '45.1' '45.123456' '59.999999') do: [ :seconds | | sql parsed epoch |
			sql := 'make_timestamptz(2020, 7, 4, 13, 30, ' , seconds , ', ''UTC'')'.
			parsed := self readOf: 'SELECT ' , sql.
			epoch := self readOf: 'SELECT extract(epoch FROM ' , sql , ')::numeric'.
			self
				assert: (parsed - self unixEpoch) asNanoSeconds
				equals: (epoch * 1000000000) asInteger.
			self
				assert: parsed offset asSeconds
				equals: (self readOf: 'SELECT extract(timezone FROM ' , sql , ')::int') ] ]
]

{ #category : 'tests - ordinary values' }
P3ChronologyServerTest >> testOrdinaryTimestampsWithoutZoneAndTimesStillRead [
	"timestamp, time and timetz, with and without a fraction. The session is in UTC so that nothing is
	shifted and the fields can be compared as they are."

	client execute: 'SET timezone = ''UTC'''.
	self
		assert: (self readOf: 'SELECT make_timestamp(2020, 10, 13, 10, 49, 48.251174)')
		equals: (DateAndTime year: 2020 month: 10 day: 13 hour: 10 minute: 49 second: 48 nanoSecond: 251174000 offset: Duration zero).
	self
		assert: (self readOf: 'SELECT make_timestamp(2020, 10, 13, 0, 0, 0)')
		equals: (DateAndTime year: 2020 month: 10 day: 13 hour: 0 minute: 0 second: 0 nanoSecond: 0 offset: Duration zero).
	self
		assert: (self readOf: 'SELECT make_time(7, 8, 9)')
		equals: (Time hour: 7 minute: 8 second: 9).
	self
		assert: (self readOf: 'SELECT make_time(23, 59, 59.999999)')
		equals: (Time hour: 23 minute: 59 second: 59 nanoSecond: 999999000).
	self
		assert: (self readOf: 'SELECT make_time(0, 0, 0)')
		equals: (Time hour: 0 minute: 0 second: 0).
	self
		assert: (self readOf: 'SELECT ''12:00:00+02''::timetz')
		equals: (Time hour: 10 minute: 0 second: 0).
	self
		assert: (self readOf: 'SELECT ''12:00:00.5-03:30''::timetz')
		equals: (Time hour: 15 minute: 30 second: 0 nanoSecond: 500000000)
]

{ #category : 'tests' }
P3ChronologyServerTest >> testServerTimezoneAnswersTheNameOfAnUnknownZone [
	client execute: 'SET TIME ZONE ''<+03>-03'''.
	self assert: client serverTimezone equals: '<+03>-03'.
	client execute: 'SET TIME ZONE ''Europe/Amsterdam'''.
	self assert: client serverTimezone equals: 'Europe/Amsterdam'
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

{ #category : 'tests - ordinary values' }
P3ChronologyServerTest >> testTimeWithZoneShiftsAcrossMidnight [
	"01:00 at +05:00 is 20:00 of the day before in UTC, 23:30 at -05:00 is 04:30 of the next day.
	The fraction of a second is kept through the shift."

	client execute: 'SET timezone = ''UTC'''.
	self
		assert: (self readOf: 'SELECT ''01:00:00+05''::timetz')
		equals: (Time hour: 20 minute: 0 second: 0).
	self
		assert: (self readOf: 'SELECT ''23:30:00.25-05''::timetz')
		equals: (Time hour: 4 minute: 30 second: 0 nanoSecond: 250000000).
	self
		assert: (self readOf: 'SELECT ''00:00:00+00''::timetz')
		equals: (Time hour: 0 minute: 0 second: 0)
]

{ #category : 'tests' }
P3ChronologyServerTest >> testTimestampWithoutZoneReadsFailWhenTheSessionZoneIsUnknown [
	| timestamp |
	client execute: 'SET TIME ZONE ''<+03>-03'''.
	self should: [ client query: 'SELECT ''2020-01-31 10:00''::timestamp' ] raise: P3Error.
	self assert: (client query: 'SELECT ''2020-01-31 10:00''::timestamptz') hasData.
	client execute: 'SET TIME ZONE ''Europe/Amsterdam'''.
	timestamp := (client query: 'SELECT ''2020-01-31 10:00''::timestamp') firstFieldOfFirstRecord.
	self assert: timestamp hour equals: 10
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
P3ChronologyServerTest >> testTimestampsWithoutZoneTakeTheOffsetOfTheSessionZone [
	"A timestamp without a zone keeps its fields and gets the offset of the session zone, in standard
	and in daylight saving time. Both values are far from a change of offset."

	| winter summer |
	client execute: 'SET timezone = ''Europe/Brussels'''.
	winter := self readOf: 'SELECT make_timestamp(2024, 1, 15, 12, 0, 0)'.
	summer := self readOf: 'SELECT make_timestamp(2024, 7, 15, 12, 0, 0.123456)'.
	self
		assert: winter
		equals: (DateAndTime year: 2024 month: 1 day: 15 hour: 12 minute: 0 second: 0 nanoSecond: 0 offset: 1 hour).
	self assert: winter offset asSeconds equals: 3600.
	self
		assert: summer
		equals: (DateAndTime year: 2024 month: 7 day: 15 hour: 12 minute: 0 second: 0 nanoSecond: 123456000 offset: 2 hours).
	self assert: summer offset asSeconds equals: 7200
]

{ #category : 'tests' }
P3ChronologyServerTest >> testUnknownServerTimezoneIsNotReplacedByTheImageZone [
	| converter error |
	converter := P3Converter new.
	converter serverTimezone: 'UTC+3'.
	error := [ converter sessionTimezone. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil.
	self assert: error code equals: 'P3036'.
	self assert: (error messageText includesSubstring: 'UTC+3').
	converter serverTimezone: 'Europe/Amsterdam'.
	self assert: converter sessionTimezone id equals: 'Europe/Amsterdam'
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
