"
I am P3ISO8601Parser.

I am a fast, validating ISO 8601 parser for Time, Date and DateAndTime objects.

I only accept the PostgreSQL ISO output format.

	YYYY-MM-DD hh:mm:ss.nnnnnnnnn[+|-]HH[:MM[:SS]]

The year has four digits or more, every other number two. A date or timestamp before the common era ends in ' BC', and is turned into the astronomical year that the image uses (44 BC is year -43). A time may have no fraction and no offset, and a date has no time.

Text that is not in this format is not guessed at: the same digits in another DateStyle are another date, so I signal a P3Error when anything is missing, misplaced, or left over. infinity and -infinity have no Date or DateAndTime, and signal a P3Error too.
"
Class {
	#name : 'P3ISO8601Parser',
	#superclass : 'Object',
	#instVars : [
		'stream',
		'timestampClass'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'instance creation' }
P3ISO8601Parser class >> on: stringOrReadStream [
	^ self new 
		on: stringOrReadStream readStream; 
		yourself
]

{ #category : 'private' }
P3ISO8601Parser >> astronomicalYear: aYear beforeCommonEra: isBC [
	"The server counts years before the common era from 1 BC. The image counts astronomical years,
	where 1 BC is year 0 and 44 BC is year -43."

	^ isBC ifTrue: [ 1 - aYear ] ifFalse: [ aYear ]
]

{ #category : 'private' }
P3ISO8601Parser >> expect: aCharacter [
	"Consume aCharacter, or signal when the next character is another one or there is none."

	(stream atEnd not and: [ stream peek = aCharacter ])
		ifFalse: [ ^ self failExpecting: aCharacter printString ].
	stream next
]

{ #category : 'private' }
P3ISO8601Parser >> failExpecting: aDescription [
	"The input is not in the format that I read. Signal where."

	^ (P3Error parsingFailed: 'expected ' , aDescription , ' at position ' , stream position asString , ' of ' , self inputText printString) signal
]

{ #category : 'private' }
P3ISO8601Parser >> finish [
	"Everything was read. Text after it means the input is not in the format that I read."

	stream atEnd ifFalse: [ self failExpecting: 'end of input' ]
]

{ #category : 'initialization' }
P3ISO8601Parser >> initialize [
	timestampClass := DateAndTime
]

{ #category : 'private' }
P3ISO8601Parser >> inputText [
	^ [ stream contents ] on: Error do: [ :error | '?' ]
]

{ #category : 'private' }
P3ISO8601Parser >> isLeapDayYear: aYear month: aMonth day: aDay [
	"Is this the 29th of February of a leap year in the proleptic Gregorian calendar, which is what the server uses?
	Dates at or before year 0 are the reason to ask: the image refuses 29 February there, although it
	counts the days between such dates correctly."

	^ aMonth = 2 and: [ aDay = 29 and: [ aYear \\ 4 = 0 and: [ aYear \\ 100 ~= 0 or: [ aYear \\ 400 = 0 ] ] ] ]
]

{ #category : 'initialization' }
P3ISO8601Parser >> on: readStream [
	stream := readStream 
]

{ #category : 'parsing' }
P3ISO8601Parser >> parseDate [
	"YYYY-MM-DD, with ' BC' after it for a date before the common era."

	| elements isBC year |
	self refuseInfinity.
	elements := self readDateElements.
	isBC := self readEra.
	self finish.
	year := self astronomicalYear: elements first beforeCommonEra: isBC.
	^ [ Date year: year month: elements second day: elements third ]
		on: DateError
		do: [ :error |
			(self isLeapDayYear: year month: elements second day: elements third)
				ifTrue: [ (Date year: year month: 3 day: 1) previous ]
				ifFalse: [ error pass ] ]
]

{ #category : 'parsing' }
P3ISO8601Parser >> parseDateAndTime [
	"YYYY-MM-DD hh:mm:ss[.f][+HH[:MM[:SS]]], with ' BC' after it for a time before the common era."

	| date time offset isBC year |
	self refuseInfinity.
	date := self readDateElements.
	(stream atEnd not and: [ ' T' includes: stream peek ])
		ifTrue: [ stream next ]
		ifFalse: [ ^ self failExpecting: 'a space or T between the date and the time' ].
	time := self readTimeElements.
	offset := self readOptionalOffsetInSeconds.
	isBC := self readEra.
	self finish.
	year := self astronomicalYear: date first beforeCommonEra: isBC.
	^ [ self timestampYear: year month: date second day: date third time: time offset: offset ]
		on: DateError
		do: [ :error |
			(self isLeapDayYear: year month: date second day: date third)
				ifTrue: [ (self timestampYear: year month: 2 day: 28 time: time offset: offset) + 1 day ]
				ifFalse: [ error pass ] ]
]

{ #category : 'parsing' }
P3ISO8601Parser >> parseTime [
	"hh:mm:ss with an optional fraction of a second."

	| elements |
	elements := self readTimeElements.
	self finish.
	^ Time hour: elements first minute: elements second second: elements third nanoSecond: elements fourth
]

{ #category : 'parsing' }
P3ISO8601Parser >> parseTimeWithOffset [
	"hh:mm:ss[.f] followed by an optional zone offset, +HH[:MM[:SS]]. Answer an Array with the Time and the offset as a Duration."

	| elements offset |
	elements := self readTimeElements.
	offset := self readOptionalOffsetInSeconds.
	self finish.
	^ Array
		with: (Time hour: elements first minute: elements second second: elements third nanoSecond: elements fourth)
		with: offset seconds
]

{ #category : 'private' }
P3ISO8601Parser >> readDateElements [
	"YYYY-MM-DD, the year with four digits or more, as an Array of year, month and day.
	The year is as written, a BC year is turned by #readEra."

	| year month day |
	year := self readDigitsMin: 4 max: nil.
	self expect: $-.
	month := self readDigitsMin: 2 max: 2.
	self expect: $-.
	day := self readDigitsMin: 2 max: 2.
	^ Array with: year with: month with: day
]

{ #category : 'private' }
P3ISO8601Parser >> readDigitsMin: minimum max: maximum [
	"Consume a run of decimal digits and answer its value. The run is at least minimum long, and at most
	maximum long when maximum is not nil, otherwise I signal. There is no sign and no other character."

	| value start count |
	value := 0.
	start := stream position.
	[ stream atEnd not and: [ stream peek between: $0 and: $9 ] ]
		whileTrue: [ value := value * 10 + stream next asciiValue - 48 ].
	count := stream position - start.
	(count >= minimum and: [ maximum isNil or: [ count <= maximum ] ])
		ifFalse: [ stream position: start. ^ self failExpecting: (maximum = minimum ifTrue: [ minimum asString , ' digits' ] ifFalse: [ 'at least ' , minimum asString , ' digits' ]) ].
	^ value
]

{ #category : 'private' }
P3ISO8601Parser >> readEra [
	"Consume the era that the server writes after a date before the common era, ' BC'. Answer whether it was there."

	(stream atEnd not and: [ stream peek = $  ]) ifFalse: [ ^ false ].
	stream next.
	self expect: $B.
	self expect: $C.
	^ true
]

{ #category : 'private' }
P3ISO8601Parser >> readNanoSeconds [
	"The digits after the decimal point of the seconds, as nanoseconds. Digits beyond the ninth are dropped."

	| value start count |
	value := 0.
	start := stream position.
	[ stream atEnd not and: [ stream peek between: $0 and: $9 ] ]
		whileTrue: [ value := value * 10 + stream next asciiValue - 48 ].
	count := stream position - start.
	count = 0 ifTrue: [ ^ self failExpecting: 'digits of a fraction of a second' ].
	^ count <= 9
		ifTrue: [ value * (10 raisedTo: 9 - count) ]
		ifFalse: [ value // (10 raisedTo: count - 9) ]
]

{ #category : 'private' }
P3ISO8601Parser >> readOffsetInSeconds [
	"The zone offset that follows a time, +HH, +HH:MM or +HH:MM:SS, as a signed number of seconds.
	Zones from before the standard time have offsets with seconds, such as +00:19:32."

	| sign hours minutes seconds |
	sign := stream next = $- ifTrue: [ -1 ] ifFalse: [ 1 ].
	hours := self readDigitsMin: 2 max: 2.
	minutes := seconds := 0.
	(stream atEnd not and: [ stream peek = $: ])
		ifTrue: [
			stream next.
			minutes := self readDigitsMin: 2 max: 2.
			(stream atEnd not and: [ stream peek = $: ])
				ifTrue: [
					stream next.
					seconds := self readDigitsMin: 2 max: 2 ] ].
	^ sign * ((hours * 3600) + (minutes * 60) + seconds)
]

{ #category : 'private' }
P3ISO8601Parser >> readOptionalOffsetInSeconds [
	^ (stream atEnd not and: [ '+-' includes: stream peek ])
		ifTrue: [ self readOffsetInSeconds ]
		ifFalse: [ 0 ]
]

{ #category : 'private' }
P3ISO8601Parser >> readTimeElements [
	"hh:mm:ss with an optional fraction of a second, as an Array of hours, minutes, seconds and nanoseconds."

	| hours minutes seconds nanoSeconds |
	hours := self readDigitsMin: 2 max: 2.
	self expect: $:.
	minutes := self readDigitsMin: 2 max: 2.
	self expect: $:.
	seconds := self readDigitsMin: 2 max: 2.
	nanoSeconds := (stream atEnd not and: [ stream peek = $. ])
		ifTrue: [ stream next. self readNanoSeconds ]
		ifFalse: [ 0 ].
	^ Array with: hours with: minutes with: seconds with: nanoSeconds
]

{ #category : 'private' }
P3ISO8601Parser >> refuseInfinity [
	"infinity and -infinity are valid dates and timestamps to the server, and have no value here."

	| position text |
	position := stream position.
	text := stream upToEnd.
	stream position: position.
	(text = 'infinity' or: [ text = '-infinity' ])
		ifTrue: [ ^ (P3Error cannotReadInfinity: text) signal ]
]

{ #category : 'initialization' }
P3ISO8601Parser >> timestampClass: aClass [
	"Set the class for timestamps, which will be sent #year:month:day:hour:minute:second:nanoSecond:offset:"
	
	timestampClass := aClass
]

{ #category : 'private' }
P3ISO8601Parser >> timestampYear: aYear month: aMonth day: aDay time: timeElements offset: offsetInSeconds [
	"Make a timestamp of my timestampClass. timeElements is an Array of hours, minutes, seconds and nanoseconds."

	^ timestampClass
		year: aYear
		month: aMonth
		day: aDay
		hour: timeElements first
		minute: timeElements second
		second: timeElements third
		nanoSecond: timeElements fourth
		offset: offsetInSeconds seconds
]
