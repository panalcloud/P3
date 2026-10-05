"
I test that the converter follows the session parameters that decide how values are formatted.

Values arrive as text, so client_encoding, TimeZone, DateStyle and IntervalStyle change what that text means. The server reports every change as a ParameterStatus message, but the converter used to read those parameters once, at connect time. A statement that changed one of them made every later date, interval or string silently wrong.

Each test gets its own connection, so a parameter it changes dies with it.

I need a server. See P3ClientTest class >> url.
"
Class {
	#name : 'P3SessionParameterTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests' }
P3SessionParameterTest >> testClientEncodingChangeIsApplied [
	"chr(241) is n-tilde. Sent as LATIN1 it is one byte; decoded as UTF-8 it is not a character at
	all. Read it with the encoding the server says it is using."

	client execute: 'SET client_encoding TO ''LATIN1'''.
	self
		assert: (client query: 'SELECT chr(241)') firstFieldOfFirstRecord
		equals: (String with: (Character value: 241)).
	client execute: 'RESET client_encoding'.
	self
		assert: (client query: 'SELECT chr(241)') firstFieldOfFirstRecord
		equals: (String with: (Character value: 241))
]

{ #category : 'tests' }
P3SessionParameterTest >> testDateStyleChangeIsNotSilentlyMisread [
	"Dates and timestamps are parsed as ISO 8601. Under 'SQL, DMY' the same text means another date
	altogether: '2020-01-31' is read as the year 31. Refuse it instead of answering it."

	client execute: 'SET DateStyle TO ''SQL, DMY'''.
	self should: [ client query: 'SELECT ''2020-01-31''::date' ] raise: P3Error.
	self should: [ client query: 'SELECT ''2020-01-31 10:00''::timestamp' ] raise: P3Error.
	client execute: 'RESET DateStyle'.
	self
		assert: (client query: 'SELECT ''2020-01-31''::date') firstFieldOfFirstRecord
		equals: (Date year: 2020 month: 1 day: 31)
]

{ #category : 'tests' }
P3SessionParameterTest >> testIntervalStyleChangeIsNotSilentlyMisread [
	"P3Interval reads the 'postgres' format. Under 'sql_standard' the same interval prints as
	'1 2:00:00' and the day is simply lost."

	client execute: 'SET IntervalStyle TO ''sql_standard'''.
	self should: [ client query: 'SELECT ''1 day 02:00''::interval' ] raise: P3Error.
	client execute: 'RESET IntervalStyle'.
	self
		assert: (client query: 'SELECT ''1 day 02:00''::interval') firstFieldOfFirstRecord
		equals: (P3Interval years: 0 months: 0 days: 1 hours: 2 minutes: 0 seconds: 0)
]

{ #category : 'tests' }
P3SessionParameterTest >> testTimeZoneChangeIsApplied [
	"A timestamp without a time zone carries no offset, so it is shifted using the session's zone, which
	the converter used to be told at connect time only. SET TIME ZONE changes it and the server reports
	the change, and the same timestamp then reads with a different offset."

	| mexico brussels |
	client execute: 'SET TIME ZONE ''America/Mexico_City'''.
	self assert: client converter timezone id equals: #'America/Mexico_City'.
	mexico := (client query: 'SELECT ''2020-06-15 12:00''::timestamp') firstFieldOfFirstRecord.
	client execute: 'SET TIME ZONE ''Europe/Brussels'''.
	self assert: client converter timezone id equals: #'Europe/Brussels'.
	brussels := (client query: 'SELECT ''2020-06-15 12:00''::timestamp') firstFieldOfFirstRecord.
	self deny: mexico offset = brussels offset
]
