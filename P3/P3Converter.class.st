"
I am P3Converter.

I convert field values to objects, taking into account their type.

I known the character encoding and timezone of the current database connection.
"
Class {
	#name : 'P3Converter',
	#superclass : 'Object',
	#instVars : [
		'encoder',
		'timezone',
		'map',
		'stringWriteStream',
		'asciiReadStream',
		'asciiWriteStream',
		'timestampClass',
		'unknownTimezoneName',
		'dateStyle',
		'intervalStyle'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'accessing' }
P3Converter class >> exactPowersOfTen [
	"10 raisedTo: 0 to 22, each exactly representable as a Float"

	^ #(1.0e0 1.0e1 1.0e2 1.0e3 1.0e4 1.0e5 1.0e6 1.0e7 1.0e8 1.0e9 1.0e10 1.0e11 1.0e12 1.0e13 1.0e14 1.0e15 1.0e16 1.0e17 1.0e18 1.0e19 1.0e20 1.0e21 1.0e22)
]

{ #category : 'accessing' }
P3Converter class >> isoDateStyleTypeOids [
	"The type OIDs whose text I read as ISO 8601: date, time, timestamp, timestamptz, timetz.
	Only DateStyle ISO produces that text. See P3Converter>>#dateStyle:."

	^ #( 1082 1083 1114 1184 1266 )
]

{ #category : 'accessing' }
P3Converter class >> postgresIntervalStyleTypeOids [
	"The type OIDs whose text I read in the 'postgres' output format: interval.
	See P3Converter>>#intervalStyle:."

	^ #( 1186 )
]

{ #category : 'accessing' }
P3Converter class >> supportedTypes [
	"Return the list of PostgreSQL internal type names that we can convert to objects."
	
	^ P3TypeMap standard supportedTypes
]

{ #category : 'accessing' }
P3Converter class >> typeMap [
	"Answer the standard type map in its old shape, a dictionary from OID to name and converter."

	| standard |
	self deprecated: 'Use P3TypeMap standard, or P3Converter>>#typeMap for the map of one converter'.
	standard := P3TypeMap standard.
	^ IdentityDictionary newFromPairs: (standard oids
		inject: OrderedCollection new
		into: [ :pairs :oid | | mapping |
			mapping := standard mappingAt: oid ifAbsent: [ nil ].
			pairs add: oid; add: { mapping name. mapping converter }; yourself ])
]

{ #category : 'input/output' }
P3Converter >> asciiCStringFrom: binaryStream [
	| byte |
	asciiWriteStream reset.
	[ (byte := binaryStream next) = 0 ]
		whileFalse: [ asciiWriteStream nextPut: byte asCharacter ].
	^ asciiWriteStream contents
]

{ #category : 'private' }
P3Converter >> asciiStreamFor: bytes length: length [
	| asciiString |
	asciiString := asciiReadStream originalContents.
	asciiString size < length
		ifTrue: [ 
			asciiReadStream := (asciiString := String new: ((length // 64) + 1) * 64) readStream ].
	bytes next: length into: asciiString. "implicit cheap ASCII conversion"
	asciiReadStream setFrom: 1 to: length.
	^ asciiReadStream 
]

{ #category : 'converting' }
P3Converter >> byteArrayFromEscapeFormat: text [
	"Read the bytea text of bytea_output = escape: printable bytes as they are, a backslash as two of
	them, any other byte as a backslash and three octal digits."

	| in |
	in := text readStream.
	^ ByteArray streamContents: [ :out |
		[ in atEnd ] whileFalse: [ | byte |
			byte := in next.
			byte = 92
				ifFalse: [ out nextPut: byte ]
				ifTrue: [
					in peek = 92
						ifTrue: [ out nextPut: in next ]
						ifFalse: [ out nextPut: (self octalValueOf: (in next: 3)) ] ] ] ]
]

{ #category : 'accessing' }
P3Converter >> clientEncoding: aString [
	"Read values with the encoding the server says it is sending. An encoding I have no encoder for
	leaves the current one in place: the values will then fail to decode, which is better than
	decoding them under a name I cannot honour."

	[ self encoder: (ZnCharacterEncoder newForEncoding: aString) ]
		on: Error
		do: [ :error | error return ]
]

{ #category : 'converting' }
P3Converter >> convert: bytes length: length description: description [
	| converter |
	converter := (map mappingAt: description typeOid ifAbsent: [ ^ (P3Error cannotConvertTypeOid: description typeOid) signal ]) converter.
	^ converter isSymbol
		ifTrue: [ self perform: converter with: bytes with: length with: description ]
		ifFalse: [ converter value: bytes value: length value: description ]
]

{ #category : 'converting' }
P3Converter >> convertBitStringFrom: bytes length: length description: description [
	^ P3BitString readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting-arrays' }
P3Converter >> convertBooleanArrayFrom: bytes length: length description: description [
	| input |
	input := ZnLimitedReadStream on: bytes limit: length.
	input := ZnCharacterReadStream on: input encoding: self encoder. 
	^ P3ArrayValueParser new 
		on: input;
		converter: [ :string | string first = $t ];
		next
]

{ #category : 'converting' }
P3Converter >> convertBooleanFrom: bytes length: length description: description [
	self assert: length = 1.
	^ bytes next = $t charCode
]

{ #category : 'converting-geometric' }
P3Converter >> convertBoxFrom: bytes length: length description: description [
	^ P3Box readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting' }
P3Converter >> convertByteArrayFrom: bytes length: length description: description [
	"The text of a bytea is \x followed by hex digits when bytea_output is hex, the default, and the
	escape format otherwise. The server does not report that setting, but the formats cannot be
	confused: the escape format writes a backslash only as two of them or as three octal digits."

	| head size byteArray digitValues |
	length < 2 ifTrue: [ ^ self byteArrayFromEscapeFormat: (bytes next: length) ].
	head := bytes next: 2.
	head = #[92 120] "\x"
		ifFalse: [ ^ self byteArrayFromEscapeFormat: head , (bytes next: length - 2) ].
	size := (length - 2) // 2.
	digitValues := #(-1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 0 1 2 3 4 5 6 7 8 9 -1 -1 -1 -1 -1 -1 -1 10 11 12 13 14 15 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 10 11 12 13 14 15 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1).
	byteArray := ByteArray new: size.
	1 to: size do: [ :index | | value |
		value := digitValues at: bytes next + 1.
		value := (value bitShift: 4) + (digitValues at: bytes next + 1).
		byteArray at: index put: value ].
	^ byteArray 
]

{ #category : 'converting' }
P3Converter >> convertCharacterFrom: bytes length: length description: description [
	"The internal single-byte type char of PostgreSQL (OID 18), not to be confused with bpchar and
	varchar (which read as String) or one encoded character of text. The server writes the zero
	byte as an empty text, and from PostgreSQL 15 a byte with the high bit set as a backslash and
	three octal digits."

	| text |
	length = 0 ifTrue: [ ^ Character value: 0 ].
	length = 1 ifTrue: [ ^ Character value: bytes next ].
	text := bytes next: length.
	^ (length = 4 and: [ text first = 92 ])
		ifTrue: [ Character value: (self octalValueOf: text allButFirst) ]
		ifFalse: [ (P3Error unreadableValue: 'char' text: text asString) signal ]
]

{ #category : 'converting-geometric' }
P3Converter >> convertCircleFrom: bytes length: length description: description [
	^ P3Circle readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting-chronology' }
P3Converter >> convertDateAndTimeFrom: bytes length: length description: description [
	"TIMESTAMP WITH TIME ZONE (TIMESTAMPTZ) is stored internally in Postgres as UTC, but represented in the timezone of the connection, with a correct offset added. In other words, Postgres does the necessary shifting, we just have to read the result. For this to work, the connection output format must be ISO, the default."
	
	^ (P3ISO8601Parser on: (self asciiStreamFor: bytes length: length))
			timestampClass: timestampClass;
			parseDateAndTime
]

{ #category : 'converting-chronology' }
P3Converter >> convertDateAndTimeWithoutTimezoneFrom: bytes length: length description: description [
	"TIMESTAMP WITHOUT TIME ZONE (TIMESTAMP) is stored internally in Postgres the way it was inserted, its representation remains constant, with no offset added. We use the timezone of the connection to do the necessary shifting. This assumes that the timezones used during insert/update and query are the same. For this to work, the connection output format must be ISO, the default."

	| timestamp offset |
	timestamp := (P3ISO8601Parser on: (self asciiStreamFor: bytes length: length))
							timestampClass: timestampClass;
							parseDateAndTime.
	offset := self sessionTimezone offsetForTimestamp: timestamp.
	^ offset isZero
		ifTrue: [ timestamp ]
		ifFalse: [ timestamp translateTo: offset ]
]

{ #category : 'converting-chronology' }
P3Converter >> convertDateFrom: bytes length: length description: description [
	"For this to work, the connection output format must be ISO, the default"
	
	^ (P3ISO8601Parser on: (self asciiStreamFor: bytes length: length)) parseDate
]

{ #category : 'converting' }
P3Converter >> convertFixedBitStringFrom: bytes length: length description: description [
	^ P3FixedBitString readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting-arrays' }
P3Converter >> convertFloatArrayFrom: bytes length: length description: description [
	| input |
	input := ZnLimitedReadStream on: bytes limit: length.
	input := ZnCharacterReadStream on: input encoding: self encoder. 
	^ P3ArrayValueParser new 
		on: input;
		converter: [ :string | self floatFrom: string ];
		next
]

{ #category : 'converting' }
P3Converter >> convertFloatFrom: bytes length: length description: description [
	^ self floatFrom: (self asciiStreamFor: bytes length: length) upToEnd
]

{ #category : 'converting-arrays' }
P3Converter >> convertIntegerArrayFrom: bytes length: length description: description [
	| input |
	input := ZnLimitedReadStream on: bytes limit: length.
	input := ZnCharacterReadStream on: input encoding: self encoder. 
	^ P3ArrayValueParser new 
		on: input;
		converter: [ :string | Integer readFrom: string base: 10 ];
		next
]

{ #category : 'converting' }
P3Converter >> convertIntegerFrom: bytes length: length description: description [
	^ Integer readFrom: (self asciiStreamFor: bytes length: length) base: 10
]

{ #category : 'converting-arrays' }
P3Converter >> convertIntegerVectorFrom: bytes length: length description: description [
	| input |
	input := ZnLimitedReadStream on: bytes limit: length.
	input := ZnCharacterReadStream on: input encoding: self encoder.
	^ P3IntegerVectorValueParser new
		  on: input;
		  next
]

{ #category : 'converting-chronology' }
P3Converter >> convertIntervalFrom: bytes length: length description: description [
	^ P3Interval readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting-special' }
P3Converter >> convertJsonFrom: bytes length: length description: description [
	| input |
	input := ZnLimitedReadStream on: bytes limit: length.
	input := ZnCharacterReadStream on: input encoding: self encoder. 
	^ (NeoJSONReader on: input)
			mapClass: NeoJSONObject;
			propertyNamesAsSymbols: true;
			next
]

{ #category : 'converting-geometric' }
P3Converter >> convertLineFrom: bytes length: length description: description [
	^ P3Line readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting-geometric' }
P3Converter >> convertLineSegmentFrom: bytes length: length description: description [
	^ P3LineSegment readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting-geometric' }
P3Converter >> convertPathFrom: bytes length: length description: description [
	^ P3Path readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting-geometric' }
P3Converter >> convertPointFrom: bytes length: length description: description [
	^ P3Point readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting-geometric' }
P3Converter >> convertPolygonFrom: bytes length: length description: description [
	^ P3Polygon readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting' }
P3Converter >> convertScaledDecimalFrom: bytes length: length description: description [
	^ self scaledDecimalFrom: (self asciiStreamFor: bytes length: length) upToEnd
]

{ #category : 'converting-arrays' }
P3Converter >> convertStringArrayFrom: bytes length: length description: description [
	| input |
	input := ZnLimitedReadStream on: bytes limit: length.
	input := ZnCharacterReadStream on: input encoding: self encoder. 
	^ P3ArrayValueParser new 
		on: input;
		next
]

{ #category : 'converting' }
P3Converter >> convertStringFrom: bytes length: length description: description [
	| endPosition |
	length = 0 ifTrue: [ ^ '' ].
	endPosition := bytes position + length.
	stringWriteStream reset.
	[ stringWriteStream nextPut: (encoder nextFromStream: bytes) ]
			doWhileTrue: [ bytes position < endPosition ].
	^ stringWriteStream contents
]

{ #category : 'converting' }
P3Converter >> convertSymbolFrom: bytes length: length description: description [
	^ (self convertStringFrom: bytes length: length description: description) asSymbol
]

{ #category : 'converting-chronology' }
P3Converter >> convertTimeFrom: bytes length: length description: description [
	"TIME [ WITHOUT TIME ZONE ] corresponds to Time, i.e. 
	both have no knowledge about the applicable time zone.
	We assume the time to be correct as there is no sensible conversion to be done.
	For this to work, the connection output format must be ISO, the default"
	
	^ (P3ISO8601Parser on: (self asciiStreamFor: bytes length: length)) parseTime
]

{ #category : 'converting-chronology' }
P3Converter >> convertTimeWithTimezoneFrom: bytes length: length description: description [
	"TIME WITH TIME ZONE corresponds to Time plus an offset. 
	Time does not hold a time zone nor an offset.
	We compare the offset coming in with the offset for that time today 
	in our connection's timezone, if they differ we correct to compensate.
	The correction is made in nanoseconds: Time arithmetic works in whole seconds and would drop
	the fraction of a second.
	For this to work, the connection output format must be ISO, the default"

	| timeAndOffset time offset connectionOffset nanoSecondsPerDay shifted seconds |
	timeAndOffset := (P3ISO8601Parser on: (self asciiStreamFor: bytes length: length)) parseTimeWithOffset.
	time := timeAndOffset first.
	offset := timeAndOffset second.
	connectionOffset := self sessionTimezone offsetForTimestamp: (ZTimestamp today + time).
	offset = connectionOffset ifTrue: [ ^ time ].
	nanoSecondsPerDay := 86400 * 1000000000.
	shifted := ((time asSeconds * 1000000000) + time nanoSecond - (offset - connectionOffset) asNanoSeconds) \\ nanoSecondsPerDay.
	seconds := shifted // 1000000000.
	^ Time
		hour: seconds // 3600
		minute: seconds // 60 \\ 60
		second: seconds \\ 60
		nanoSecond: shifted \\ 1000000000
]

{ #category : 'converting-special' }
P3Converter >> convertUuidFrom: bytes length: length description: description [
	
	^ UUID nilUUID readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting' }
P3Converter >> convertVoidFrom: bytes length: length description: description [
	self assert: length = 0.
	^ nil
]

{ #category : 'accessing' }
P3Converter >> dateStyle: aString [
	"The session's DateStyle. I read dates and timestamps as ISO 8601, which only DateStyle ISO produces.
	Under another style the same text is a different date and P3ISO8601Parser cannot tell: Postgres style
	prints 0031-01-01 as 01-01-0031, which is valid ISO for 0001-01-31. So the style decides what the
	chronology OIDs map to, the parser or a converter that refuses, and reading a value costs nothing."

	dateStyle := aString.
	self
		installConvertersFor: self class isoDateStyleTypeOids
		refusing: (self usesISODateStyle
			ifTrue: [ nil ]
			ifFalse: [ [ :bytes :length :description | (P3Error unsupportedDateStyle: dateStyle) signal ] ])
]

{ #category : 'input/output' }
P3Converter >> encodedCStringFrom: binaryStream [
	stringWriteStream reset.
	[ binaryStream peekFor: 0 ]
		whileFalse: [ stringWriteStream nextPut: (encoder nextFromStream: binaryStream) ].
	^ stringWriteStream contents
]

{ #category : 'accessing' }
P3Converter >> encoder [
	^ encoder ifNil: [ encoder := ZnCharacterEncoder utf8 ]
]

{ #category : 'accessing' }
P3Converter >> encoder: anObject [
	encoder := anObject
]

{ #category : 'converting' }
P3Converter >> floatFrom: aString [
	"Read the text of a float4 or float8, as the server writes it: digits with an optional fraction and
	an optional exponent with its own sign (1e+100, -1.5e-07), or NaN, Infinity and -Infinity.
	The value is the exact decimal fraction rounded once to a double, so every double that the server
	prints with the digits that identify it is read back as the same double. A negative zero keeps its sign.
	When the digits fit in 53 bits and the power of ten is at most 22, both are exact doubles and one
	multiplication or division rounds correctly. Otherwise the exact fraction is rounded."

	| text size index char negative mantissa digitCount fractionCount exponent exponentNegative exponentCount scale value |
	text := aString.
	(text notEmpty and: [ text first isSeparator or: [ text last isSeparator ] ]) ifTrue: [ text := text trimmed ].
	size := text size.
	size = 0 ifTrue: [ ^ (P3Error parsingFailed: aString) signal ].
	text = 'NaN' ifTrue: [ ^ Float nan ].
	index := 1.
	negative := false.
	char := text at: 1.
	char = $- ifTrue: [ negative := true. index := 2 ].
	char = $+ ifTrue: [ index := 2 ].
	(index <= size and: [ (text at: index) = $I ]) ifTrue: [
		(text copyFrom: index to: size) = 'Infinity' ifFalse: [ ^ (P3Error parsingFailed: aString) signal ].
		^ negative ifTrue: [ Float infinity negated ] ifFalse: [ Float infinity ] ].
	mantissa := digitCount := fractionCount := 0.
	[ index <= size and: [ (char := text at: index) isDigit ] ] whileTrue: [
		mantissa := mantissa * 10 + char digitValue.
		digitCount := digitCount + 1.
		index := index + 1 ].
	(index <= size and: [ (text at: index) = $. ]) ifTrue: [
		index := index + 1.
		[ index <= size and: [ (char := text at: index) isDigit ] ] whileTrue: [
			mantissa := mantissa * 10 + char digitValue.
			digitCount := digitCount + 1.
			fractionCount := fractionCount + 1.
			index := index + 1 ] ].
	digitCount = 0 ifTrue: [ ^ (P3Error parsingFailed: aString) signal ].
	exponent := 0.
	(index <= size and: [ (char := text at: index) = $e or: [ char = $E ] ]) ifTrue: [
		index := index + 1.
		exponentNegative := false.
		(index <= size and: [ (text at: index) = $- ]) ifTrue: [ exponentNegative := true. index := index + 1 ].
		(index <= size and: [ (text at: index) = $+ ]) ifTrue: [ index := index + 1 ].
		exponentCount := 0.
		[ index <= size and: [ (char := text at: index) isDigit ] ] whileTrue: [
			exponent := exponent * 10 + char digitValue.
			exponentCount := exponentCount + 1.
			index := index + 1 ].
		exponentCount = 0 ifTrue: [ ^ (P3Error parsingFailed: aString) signal ].
		exponentNegative ifTrue: [ exponent := exponent negated ] ].
	index <= size ifTrue: [ ^ (P3Error parsingFailed: aString) signal ].
	mantissa = 0 ifTrue: [ ^ negative ifTrue: [ Float negativeZero ] ifFalse: [ 0.0 ] ].
	scale := exponent - fractionCount.
	value := (mantissa < 9007199254740992 and: [ scale abs <= 22 ])
		ifTrue: [
			scale >= 0
				ifTrue: [ mantissa asFloat * (self class exactPowersOfTen at: scale + 1) ]
				ifFalse: [ mantissa asFloat / (self class exactPowersOfTen at: scale negated + 1) ] ]
		ifFalse: [ (mantissa * (10 raisedTo: scale)) asFloat ].
	^ negative ifTrue: [ value negated ] ifFalse: [ value ]
]

{ #category : 'initialize' }
P3Converter >> initialize [
	super initialize.
	encoder := ZnCharacterEncoder utf8.
	asciiReadStream := String new readStream.
	asciiWriteStream := String new writeStream.
	stringWriteStream := String new writeStream.
	timestampClass := DateAndTime.
	self initializeTypeMap
]

{ #category : 'initialize' }
P3Converter >> initializeFrom: properties [
	"Resolve the session/connection time zone, see #serverTimezone:"

	self serverTimezone: (properties at: 'TimeZone' ifAbsent: [ 'GMT' ]).
	"The character encoder/decoder, as when the server reports a change: a name that I have no encoder for
	leaves UTF-8 in place and does not fail the connect."
	self clientEncoding: (properties at: 'client_encoding' ifAbsent: [ 'UTF8' ]).
	"The output styles I can read. A missing one means the server did not report it, so assume its default."
	self dateStyle: (properties at: 'DateStyle' ifAbsent: [ nil ]).
	self intervalStyle: (properties at: 'IntervalStyle' ifAbsent: [ nil ])
]

{ #category : 'initialize' }
P3Converter >> initializeTypeMap [
	"My own extension of the standard map, so that #mapOid:type:to: changes no other converter."

	map := P3TypeMap standard extension
]

{ #category : 'private' }
P3Converter >> installConvertersFor: typeOids refusing: aBlockOrNil [
	"Point typeOids at their standard converters, or at aBlockOrNil when that is not nil. The session's
	output styles decide which, and they only change when the server reports a change, so the decision is
	made here instead of on every value read. A caller that installed its own converter for one of these
	OIDs loses it when a style changes."

	typeOids do: [ :oid |
		aBlockOrNil
			ifNil: [ map restoreOid: oid ]
			ifNotNil: [ map
				mapOid: oid
				type: (P3TypeMap standard nameAt: oid ifAbsent: [ oid ])
				to: aBlockOrNil ] ]
]

{ #category : 'accessing' }
P3Converter >> intervalStyle: aString [
	"The session's IntervalStyle. P3Interval reads the 'postgres' format; the other styles drop or move
	components, so the style decides whether the interval OID maps to P3Interval or to a converter that
	refuses. See #dateStyle: for why this is decided here."

	intervalStyle := aString.
	self
		installConvertersFor: self class postgresIntervalStyleTypeOids
		refusing: (self usesPostgresIntervalStyle
			ifTrue: [ nil ]
			ifFalse: [ [ :bytes :length :description | (P3Error unsupportedIntervalStyle: intervalStyle) signal ] ])
]

{ #category : 'accessing' }
P3Converter >> mapOid: anOoid type: aTypename to: aBlockOrSymbol [
	^ map mapOid: anOoid type: aTypename to: aBlockOrSymbol
]

{ #category : 'initialize' }
P3Converter >> noteSessionParameter: key value: value [
	"React to a server parameter that decides how I read values. Values arrive as text, so these four
	change what that text means, and the server reports each change as a ParameterStatus message.
	Anything else I do not care about."

	key = 'client_encoding' ifTrue: [ ^ self clientEncoding: value ].
	key = 'TimeZone' ifTrue: [ ^ self serverTimezone: value ].
	key = 'DateStyle' ifTrue: [ ^ self dateStyle: value ].
	key = 'IntervalStyle' ifTrue: [ ^ self intervalStyle: value ]
]

{ #category : 'converting' }
P3Converter >> octalValueOf: threeDigitBytes [
	"The value of three ASCII octal digits, like the 200 of a backslash and 200."

	^ threeDigitBytes inject: 0 into: [ :sum :digit |
		(digit between: 48 and: 55) ifFalse: [
			(P3Error unreadableValue: 'octal escape' text: threeDigitBytes asString) signal ].
		sum * 8 + (digit - 48) ]
]

{ #category : 'printing' }
P3Converter >> printOn: stream [
	super printOn: stream.
	stream nextPut: $(.
	stream print: self encoder identifier.
	stream space.
	self timezone ifNotNil: [ :tmz | stream print: tmz id ].
	stream nextPut: $)
]

{ #category : 'converting' }
P3Converter >> scaledDecimalFrom: aString [
	"Read the text of a numeric as a ScaledDecimal. NaN, Infinity and -Infinity are numeric values
	that a ScaledDecimal, being a fraction, cannot hold: reading one signals a P3Error."

	| text |
	text := aString trimmed.
	(text = 'NaN' or: [ text = 'Infinity' or: [ text = '-Infinity' ] ])
		ifTrue: [ ^ (P3Error cannotRepresentNumeric: text) signal ].
	^ ScaledDecimal readFrom: text readStream
]

{ #category : 'initialization' }
P3Converter >> serverTimezone: aString [
	"Shift times without a zone using the session's zone. A name that I cannot resolve, like a POSIX
	style UTC+3, is remembered: guessing a zone would shift values by the wrong offset, so reading a
	value that needs the zone signals instead, see #sessionTimezone."

	timezone := [ ZTimezone id: aString ] on: Error do: [ nil ].
	unknownTimezoneName := timezone ifNil: [ aString ]
]

{ #category : 'accessing' }
P3Converter >> sessionTimezone [
	"The zone of the session. Signal when the server reported a name that I cannot resolve."

	^ timezone ifNil: [ (P3Error unknownTimezone: unknownTimezoneName) signal ]
]

{ #category : 'accessing' }
P3Converter >> timestampClass [
	^ timestampClass
]

{ #category : 'accessing' }
P3Converter >> timestampClass: anObject [
	timestampClass := anObject
]

{ #category : 'accessing' }
P3Converter >> timezone [
	^ timezone
]

{ #category : 'accessing' }
P3Converter >> timezone: anObject [
	timezone := anObject.
	unknownTimezoneName := nil
]

{ #category : 'accessing' }
P3Converter >> timezoneName [
	"The name of the session zone, also when I cannot resolve it."

	^ timezone ifNil: [ unknownTimezoneName ] ifNotNil: [ :zone | zone id ]
]

{ #category : 'accessing' }
P3Converter >> typeMap [
	^ map
]

{ #category : 'testing' }
P3Converter >> usesISODateStyle [
	"DateStyle ISO is the only one whose date and timestamp text is ISO 8601. Nil means nobody told me a
	style, so assume the server default, which is ISO."

	^ dateStyle isNil or: [ dateStyle beginsWith: 'ISO' ]
]

{ #category : 'testing' }
P3Converter >> usesPostgresIntervalStyle [
	"'postgres' is the interval output format P3Interval reads. Nil means nobody told me a style, so assume
	the server default, which is postgres."

	^ intervalStyle isNil or: [ intervalStyle = 'postgres' ]
]
