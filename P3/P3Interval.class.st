"
I am P3Interval, a time duration (INTERVAL).

I store all components separately.

I support the 'postgres' default IO format.

I can also print myself using the 'iso8601 with designators' format.

This is currently an MVP implementation.

Known limit: the sign of the time part is one sign for hours, minutes and seconds together, as in '-04:05:06'. An interval whose time part mixes signs, for example hours 1 and minutes -30, cannot be written in that format. Printing it gives text that does not mean the same interval. The server never sends such a value, because it stores the time part as one signed number, so reading is not affected. Keep the signs of hours, minutes and seconds equal when you create an interval to send.
"
Class {
	#name : 'P3Interval',
	#superclass : 'Object',
	#instVars : [
		'years',
		'months',
		'days',
		'hours',
		'minutes',
		'seconds'
	],
	#category : 'P3-Objects',
	#package : 'P3',
	#tag : 'Objects'
}

{ #category : 'private' }
P3Interval class >> readDesignator: stream [
	self skipSeparators: stream.
	^ String streamContents: [ :out |
		[ stream atEnd not and: [ stream peek isLetter ] ] whileTrue: [ out nextPut: stream next ] ]
]

{ #category : 'private' }
P3Interval class >> readDigits: stream [
	^ String streamContents: [ :out |
		[ stream atEnd not and: [ stream peek isDigit ] ] whileTrue: [ out nextPut: stream next ] ]
]

{ #category : 'instance creation' }
P3Interval class >> readFrom: stream [
	"Read the 'postgres' IntervalStyle text, for example '-1 years -2 mons +3 days -04:05:06.789'.
	Each date field has its own sign. A sign before the time part applies to hours, minutes and seconds together."

	| years months days hours minutes seconds sign number word |
	years := months := days := hours := minutes := seconds := 0.
	[ self skipSeparators: stream. stream atEnd ] whileFalse: [
		sign := self readSign: stream.
		number := self readNumber: stream.
		(stream peekFor: $:)
			ifTrue: [
				hours := sign * number.
				minutes := sign * (self readNumber: stream).
				(stream peekFor: $:) ifTrue: [ seconds := sign * (self readNumber: stream) ] ]
			ifFalse: [
				word := self readDesignator: stream.
				(word beginsWith: 'year')
					ifTrue: [ years := sign * number ]
					ifFalse: [
						(word beginsWith: 'mon')
							ifTrue: [ months := sign * number ]
							ifFalse: [
								(word beginsWith: 'day')
									ifTrue: [ days := sign * number ]
									ifFalse: [ ^ (P3Error parsingFailed: 'interval unit ' , word printString) signal ] ] ] ] ].
	^ self years: years months: months days: days hours: hours minutes: minutes seconds: seconds
]

{ #category : 'private' }
P3Interval class >> readNumber: stream [
	"Answer an unsigned Integer, or a Float when there is a fraction. A missing number is an error."

	| whole fraction |
	whole := self readDigits: stream.
	whole isEmpty ifTrue: [ ^ (P3Error parsingFailed: 'interval number expected') signal ].
	(stream peekFor: $.) ifFalse: [ ^ whole asInteger ].
	fraction := self readDigits: stream.
	^ ((whole , fraction) asInteger / (10 raisedTo: fraction size)) asFloat
]

{ #category : 'private' }
P3Interval class >> readSign: stream [
	"Answer -1 for a minus, 1 for a plus or no sign."

	(stream atEnd not and: [ stream peek = $- ]) ifTrue: [ stream next. ^ -1 ].
	(stream atEnd not and: [ stream peek = $+ ]) ifTrue: [ stream next ].
	^ 1
]

{ #category : 'private' }
P3Interval class >> skipSeparators: stream [
	[ stream atEnd not and: [ stream peek isSeparator ] ] whileTrue: [ stream next ]
]

{ #category : 'instance creation' }
P3Interval class >> years: years months: months days: days hours: hours minutes: minutes seconds: seconds [
	^ self new
		years: years;
		months: months;
		days: days;
		hours: hours;
		minutes: minutes;
		seconds: seconds;
		yourself
]

{ #category : 'instance creation' }
P3Interval class >> zero [
	^ self new
]

{ #category : 'comparing' }
P3Interval >> = anotherInterval [
	self == anotherInterval
		ifTrue: [ ^ true ].
	self class = anotherInterval class
		ifFalse: [ ^ false ].
	^ years = anotherInterval years
		and: [ months = anotherInterval months
				and: [ days = anotherInterval days
						and: [ hours = anotherInterval hours
								and: [ minutes = anotherInterval minutes
										and: [ seconds = anotherInterval seconds ] ] ] ] ]
]

{ #category : 'accessing' }
P3Interval >> days [
	^ days
]

{ #category : 'accessing' }
P3Interval >> days: anObject [
	days := anObject
]

{ #category : 'comparing' }
P3Interval >> hash [
	^ ((years hash + months hash + days hash) hashMultiply
		+ (hours hash + minutes hash + seconds hash) hashMultiply)
		hashMultiply
]

{ #category : 'accessing' }
P3Interval >> hours [
	^ hours
]

{ #category : 'accessing' }
P3Interval >> hours: anObject [
	hours := anObject
]

{ #category : 'initialization' }
P3Interval >> initialize [
	super initialize.
	years := months := days := hours := minutes := seconds := 0
]

{ #category : 'accessing' }
P3Interval >> minutes [
	^ minutes
]

{ #category : 'accessing' }
P3Interval >> minutes: anObject [
	minutes := anObject
]

{ #category : 'accessing' }
P3Interval >> months [
	^ months
]

{ #category : 'accessing' }
P3Interval >> months: anObject [
	months := anObject
]

{ #category : 'printing' }
P3Interval >> p3PrintUsing: delegate on: stream [
	"Print me on stream via double dispatch on delegate.
	Check the implementors of #p3PrintUsing:on:"

	delegate printInterval: self on: stream
]

{ #category : 'printing' }
P3Interval >> printIso8601On: stream [
	stream nextPut: $P.
	years = 0 ifFalse: [ 
		stream print: years; nextPut: $Y ].
	months = 0 ifFalse: [
		stream print: months; nextPut: $M ].
	days = 0 ifFalse: [
		stream print: days; nextPut: $D ].
	stream nextPut: $T.
	hours = 0 ifFalse: [ 
		stream print: hours; nextPut: $H ].
	minutes = 0 ifFalse: [
		stream print: minutes; nextPut: $M ].
	seconds = 0 ifFalse: [
		stream print: seconds; nextPut: $S ]
]

{ #category : 'printing' }
P3Interval >> printOn: stream [
	"Print in the 'postgres' IntervalStyle. The time part has one sign, see the class comment."

	| space |
	space := false.
	years = 0 ifFalse: [ 
		stream print: years; space.
		stream nextPutAll: (years = 1 ifTrue: [ 'year' ] ifFalse: [ 'years' ]).
		space := true ].
	months = 0 ifFalse: [
		space ifTrue: [ stream space ]. 
		stream print: months; space.
		stream nextPutAll: (months = 1 ifTrue: [ 'mon' ] ifFalse: [ 'mons' ]).
		space := true ].
	days = 0 ifFalse: [
		space ifTrue: [ stream space ]. 
		stream print: days; space.
		stream nextPutAll: (days = 1 ifTrue: [ 'day' ] ifFalse: [ 'days' ]).
		space := true ].
	space ifTrue: [ stream space ].
	self printTimePartOn: stream
]

{ #category : 'printing' }
P3Interval >> printSecondsOn: stream [
	"Seconds as digits with at most 6 decimals, the server resolution. Never an exponent."

	| microseconds fraction |
	microseconds := (seconds abs * 1000000) rounded.
	stream nextPutAll: ((microseconds // 1000000) printString padLeftTo: 2 with: $0).
	fraction := microseconds \\ 1000000.
	fraction = 0 ifTrue: [ ^ self ].
	stream
		nextPut: $.;
		nextPutAll: ((fraction printString padLeftTo: 6 with: $0) trimRight: [ :each | each = $0 ])
]

{ #category : 'printing' }
P3Interval >> printTimePartOn: stream [
	"One sign, taken from the first non zero field, then the absolute values of hours, minutes and seconds."

	| negative |
	negative := { hours. minutes. seconds }
		detect: [ :each | each ~= 0 ]
		ifFound: [ :each | each < 0 ]
		ifNone: [ false ].
	negative ifTrue: [ stream nextPut: $- ].
	stream nextPutAll: (hours abs printString padLeftTo: 2 with: $0).
	stream nextPut: $:.
	stream nextPutAll: (minutes abs printString padLeftTo: 2 with: $0).
	stream nextPut: $:.
	self printSecondsOn: stream
]

{ #category : 'accessing' }
P3Interval >> seconds [
	^ seconds
]

{ #category : 'accessing' }
P3Interval >> seconds: anObject [
	seconds := anObject
]

{ #category : 'accessing' }
P3Interval >> years [
	^ years
]

{ #category : 'accessing' }
P3Interval >> years: anObject [
	years := anObject
]
