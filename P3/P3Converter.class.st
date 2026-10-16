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
		'intervalStyle',
		'unknownTypeConverter'
	],
	#classVars : [
		'HighByteSet'
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
P3Converter class >> highByteSet [
	"The set of bytes from 128 to 255, in the form of ByteString class>>#findFirstInString:inSet:startingAt:"

	^ HighByteSet ifNil: [ HighByteSet := (ByteArray new: 256) from: 129 to: 256 put: 1; yourself ]
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

{ #category : 'converting' }
P3Converter >> cannotConvertFrom: bytes length: length description: description [
	"The converter of a type I have no converter for, see #converterFor:"

	^ (P3Error cannotConvertTypeOid: description typeOid) signal
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
	^ self
		convert: bytes
		length: length
		using: (self converterFor: description)
		description: description
]

{ #category : 'converting' }
P3Converter >> convert: bytes length: length using: aConverter description: description [
	"Read one value with aConverter, one of my selectors or a block, see #converterFor:"

	^ aConverter isSymbol
		ifTrue: [ self perform: aConverter with: bytes with: length with: description ]
		ifFalse: [ aConverter value: bytes value: length value: description ]
]

{ #category : 'converting-arrays' }
P3Converter >> convertArrayFrom: bytes length: length description: description [
	"Read an array whose element type has its own converter. Each element text is converted
	as if the server had sent it as a column of the element type."

	| input elementDescription |
	elementDescription := P3RowFieldDescription new
		typeOid: (map mappingAt: description typeOid ifAbsent: [ self error: 'Not an array type' ]) elementOid;
		yourself.
	input := ZnLimitedReadStream on: bytes limit: length.
	input := ZnCharacterReadStream on: input encoding: self encoder.
	^ P3ArrayValueParser new
		on: input;
		converter: [ :string | | encoded |
			encoded := self encoder encodeString: string.
			self convert: encoded readStream length: encoded size description: elementDescription ];
		next
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
	"TIMESTAMP WITH TIME ZONE (TIMESTAMPTZ) is stored internally in Postgres as UTC, but represented in the timezone of the connection, with a correct offset added. In other words, Postgres does the necessary shifting, we just have to read the result. For this to work, the connection output format must be ISO, the default.
	The plain form is read by #plainTimestampFrom:length:zone:, anything else by P3ISO8601Parser."

	bytes class == ReadStream
		ifTrue: [ (self plainTimestampFrom: bytes length: length zone: nil) ifNotNil: [ :timestamp | ^ timestamp ] ].
	^ (P3ISO8601Parser on: (self asciiStreamFor: bytes length: length))
			timestampClass: timestampClass;
			parseDateAndTime
]

{ #category : 'converting-chronology' }
P3Converter >> convertDateAndTimeWithoutTimezoneFrom: bytes length: length description: description [
	"TIMESTAMP WITHOUT TIME ZONE (TIMESTAMP) is stored internally in Postgres the way it was inserted, its representation remains constant, with no offset added. We use the timezone of the connection to do the necessary shifting. This assumes that the timezones used during insert/update and query are the same. For this to work, the connection output format must be ISO, the default.
	The plain form is read and shifted by #plainTimestampFrom:length:zone:, anything else by P3ISO8601Parser.
	Without a known session zone the parser path signals, as #sessionTimezone does."

	| timestamp offset |
	(bytes class == ReadStream and: [ timezone notNil ])
		ifTrue: [
			(self plainTimestampFrom: bytes length: length zone: timezone)
				ifNotNil: [ :plainTimestamp | ^ plainTimestamp ] ].
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
	"For this to work, the connection output format must be ISO, the default.
	The plain form is read by #plainDateFrom:length:, anything else by P3ISO8601Parser."

	bytes class == ReadStream
		ifTrue: [ (self plainDateFrom: bytes length: length) ifNotNil: [ :date | ^ date ] ].
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
	"Read the decimal text of an integer. Digits with an optional minus sign, which is how the server
	writes every integer type, are read straight from the bytes by #integerFrom:length:. Anything else
	is read by Integer class>>#readFrom:base:."

	bytes class == ReadStream
		ifTrue: [ (self integerFrom: bytes length: length) ifNotNil: [ :integer | ^ integer ] ].
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
	"The plain form is read by #plainScaledDecimalFrom:length:, anything else by #scaledDecimalFrom:"

	bytes class == ReadStream
		ifTrue: [ (self plainScaledDecimalFrom: bytes length: length) ifNotNil: [ :number | ^ number ] ].
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
	"Read a text value. With the standard UTF-8 encoder, which the session uses from startup on,
	#utf8StringFrom:length: reads it. That gives up on anything but plain characters of one, two and
	three bytes, and then my encoder reads the whole value, as for any other encoding."

	length = 0 ifTrue: [ ^ '' ].
	(encoder class == ZnUTF8Encoder and: [ bytes class == ReadStream ])
		ifTrue: [ (self utf8StringFrom: bytes length: length) ifNotNil: [ :string | ^ string ] ].
	^ self encodedStringFrom: bytes length: length
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
	For this to work, the connection output format must be ISO, the default.
	The plain form is read by #plainTimeFrom:length:, anything else by P3ISO8601Parser."

	bytes class == ReadStream
		ifTrue: [ (self plainTimeFrom: bytes length: length) ifNotNil: [ :time | ^ time ] ].
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

{ #category : 'converting' }
P3Converter >> converterFor: description [
	"The converter that reads the values of the column of description: the selector or block of its type
	in my map, else my unknownTypeConverter, else a selector that signals that the type cannot be read.
	The last one only signals when a value is read, so a column without values reads fine.
	Choose it once for all the rows of a result, see P3Client>>#readDataRows:, to look the type up once."

	^ (map mappingAt: description typeOid ifAbsent: [ nil ])
		ifNil: [ unknownTypeConverter ifNil: [ #cannotConvertFrom:length:description: ] ]
		ifNotNil: [ :mapping | mapping converter ]
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

{ #category : 'converting' }
P3Converter >> digitsIn: buffer from: start count: count [
	"The value of the count decimal digits in buffer from start on, or nil when one is not a digit"

	| value |
	value := 0.
	start to: start + count - 1 do: [ :index | | digit |
		digit := (buffer at: index) - 48 "$0".
		(digit >= 0 and: [ digit <= 9 ]) ifFalse: [ ^ nil ].
		value := value * 10 + digit ].
	^ value
]

{ #category : 'input/output' }
P3Converter >> encodedCStringFrom: binaryStream [
	stringWriteStream reset.
	[ binaryStream peekFor: 0 ]
		whileFalse: [ stringWriteStream nextPut: (encoder nextFromStream: binaryStream) ].
	^ stringWriteStream contents
]

{ #category : 'converting' }
P3Converter >> encodedStringFrom: bytes length: length [
	"Read the next length bytes of bytes as text with my encoder, one character at a time"

	| endPosition |
	endPosition := bytes position + length.
	stringWriteStream reset.
	[ stringWriteStream nextPut: (encoder nextFromStream: bytes) ]
		doWhileTrue: [ bytes position < endPosition ].
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

{ #category : 'converting' }
P3Converter >> integerFrom: bytes length: length [
	"Answer the integer written in the next length bytes of bytes, a ReadStream on a ByteArray, as
	decimal digits with an optional minus sign, and move past them. Answer nil and leave bytes where it
	was for any other text."

	| buffer index end negative value |
	length = 0 ifTrue: [ ^ nil ].
	buffer := bytes originalContents.
	index := bytes position + 1.
	end := bytes position + length.
	negative := (buffer at: index) = 45 "$-".
	negative ifTrue: [ index := index + 1 ].
	index > end ifTrue: [ ^ nil ].
	value := 0.
	index to: end do: [ :each | | digit |
		digit := (buffer at: each) - 48 "$0".
		(digit >= 0 and: [ digit <= 9 ]) ifFalse: [ ^ nil ].
		value := value * 10 + digit ].
	bytes skip: length.
	^ negative
		ifTrue: [ value negated ]
		ifFalse: [ value ]
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
P3Converter >> mapArrayOid: anArrayOid type: aTypeName elementOid: anElementOid [
	^ map mapArrayOid: anArrayOid type: aTypeName elementOid: anElementOid
]

{ #category : 'accessing' }
P3Converter >> mapOid: anOoid type: aTypename to: aBlockOrSymbol [
	^ map mapOid: anOoid type: aTypename to: aBlockOrSymbol
]

{ #category : 'converting' }
P3Converter >> nanoSecondsIn: buffer from: start count: count [
	"The fraction of a second written with count digits, 1 to 9, in buffer from start on, as
	nanoseconds, or nil when one is not a digit"

	^ (self digitsIn: buffer from: start count: count)
		ifNotNil: [ :value | value * (#( 100000000 10000000 1000000 100000 10000 1000 100 10 1 ) at: count) ]
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

{ #category : 'converting' }
P3Converter >> plainDateFrom: bytes length: length [
	"Answer the date written in the next length bytes of bytes, a ReadStream on a ByteArray, as
	YYYY-MM-DD, and move past them. Answer nil and leave bytes where it was for any other text, which
	P3ISO8601Parser reads: a year of more than four digits, a date before the common era, infinity."

	| buffer start year month day date |
	length = 10 ifFalse: [ ^ nil ].
	buffer := bytes originalContents.
	start := bytes position + 1.
	((buffer at: start + 4) = 45 and: [ (buffer at: start + 7) = 45 ]) ifFalse: [ ^ nil ].
	year := self digitsIn: buffer from: start count: 4.
	month := self digitsIn: buffer from: start + 5 count: 2.
	day := self digitsIn: buffer from: start + 8 count: 2.
	(year isNil or: [ month isNil or: [ day isNil ] ]) ifTrue: [ ^ nil ].
	date := [ Date year: year month: month day: day ] on: DateError do: [ :error | ^ nil ].
	bytes skip: length.
	^ date
]

{ #category : 'converting' }
P3Converter >> plainScaledDecimalFrom: bytes length: length [
	"Answer the numeric written in the next length bytes of bytes, a ReadStream on a ByteArray, as
	digits with an optional minus sign and an optional fraction, and move past them. It is a
	ScaledDecimal with as many decimals as the fraction has digits, as ScaledDecimal class>>#readFrom:
	makes it. Answer nil and leave bytes where it was for any other text, which #scaledDecimalFrom:
	reads: NaN, Infinity and -Infinity."

	| buffer index end negative mantissa point scale number |
	length = 0 ifTrue: [ ^ nil ].
	buffer := bytes originalContents.
	index := bytes position + 1.
	end := bytes position + length.
	negative := (buffer at: index) = 45 "$-".
	negative ifTrue: [ index := index + 1 ].
	mantissa := 0.
	index to: end do: [ :each | | byte digit |
		byte := buffer at: each.
		(byte = 46 "$." and: [ point isNil ])
			ifTrue: [ point := each ]
			ifFalse: [
				digit := byte - 48 "$0".
				(digit >= 0 and: [ digit <= 9 ]) ifFalse: [ ^ nil ].
				mantissa := mantissa * 10 + digit ] ].
	"At least one digit, and digits on both sides of a decimal point"
	point
		ifNil: [
			index > end ifTrue: [ ^ nil ].
			scale := 0 ]
		ifNotNil: [
			(point > index and: [ point < end ]) ifFalse: [ ^ nil ].
			scale := end - point ].
	negative ifTrue: [ mantissa := mantissa negated ].
	number := ScaledDecimal newFromNumber: mantissa / (10 raisedTo: scale) scale: scale.
	bytes skip: length.
	^ number
]

{ #category : 'converting' }
P3Converter >> plainTimeFrom: bytes length: length [
	"Answer the time written in the next length bytes of bytes, a ReadStream on a ByteArray, as
	hh:mm:ss with an optional fraction of one to nine digits, and move past them. Answer nil and leave
	bytes where it was for any other text, which P3ISO8601Parser reads."

	| buffer start hour minute second nanoSecond |
	(length = 8 or: [ length >= 10 and: [ length <= 18 ] ]) ifFalse: [ ^ nil ].
	buffer := bytes originalContents.
	start := bytes position + 1.
	((buffer at: start + 2) = 58 and: [ (buffer at: start + 5) = 58 ]) ifFalse: [ ^ nil ].
	hour := self digitsIn: buffer from: start count: 2.
	minute := self digitsIn: buffer from: start + 3 count: 2.
	second := self digitsIn: buffer from: start + 6 count: 2.
	(hour isNil or: [ minute isNil or: [ second isNil ] ]) ifTrue: [ ^ nil ].
	nanoSecond := 0.
	length > 8 ifTrue: [
		(buffer at: start + 8) = 46 ifFalse: [ ^ nil ].
		(nanoSecond := self nanoSecondsIn: buffer from: start + 9 count: length - 9) ifNil: [ ^ nil ] ].
	bytes skip: length.
	^ Time hour: hour minute: minute second: second nanoSecond: nanoSecond
]

{ #category : 'converting' }
P3Converter >> plainTimestampFrom: bytes length: length zone: aTimezoneOrNil [
	"Answer the timestamp written in the next length bytes of bytes, a ReadStream on a ByteArray, as
	YYYY-MM-DD hh:mm:ss with an optional fraction of one to nine digits and an optional offset +HH or
	+HH:MM, and move past them. It is made as P3ISO8601Parser>>#parseDateAndTime makes it. Answer nil
	and leave bytes where it was for any other text, which the parser reads: a year of more than four
	digits, a time before the common era, an offset with seconds, infinity.

	With aTimezoneOrNil, the fields are kept and the offset becomes the one of that zone, as
	DateAndTime>>#translateTo: does, see #convertDateAndTimeWithoutTimezoneFrom:length:description:."

	| buffer start end year month day hour minute second index nanoSecond offset timestamp zoneOffset |
	length >= 19 ifFalse: [ ^ nil ].
	buffer := bytes originalContents.
	start := bytes position + 1.
	end := start + length - 1.
	((buffer at: start + 4) = 45 and: [ (buffer at: start + 7) = 45
		and: [ ((buffer at: start + 10) = 32 or: [ (buffer at: start + 10) = 84 ])
		and: [ (buffer at: start + 13) = 58 and: [ (buffer at: start + 16) = 58 ] ] ] ])
			ifFalse: [ ^ nil ].
	year := self digitsIn: buffer from: start count: 4.
	month := self digitsIn: buffer from: start + 5 count: 2.
	day := self digitsIn: buffer from: start + 8 count: 2.
	hour := self digitsIn: buffer from: start + 11 count: 2.
	minute := self digitsIn: buffer from: start + 14 count: 2.
	second := self digitsIn: buffer from: start + 17 count: 2.
	(year isNil or: [ month isNil or: [ day isNil or: [ hour isNil or: [ minute isNil or: [ second isNil ] ] ] ] ])
		ifTrue: [ ^ nil ].
	index := start + 19.
	nanoSecond := 0.
	(index <= end and: [ (buffer at: index) = 46 ]) ifTrue: [ | first |
		first := index + 1.
		index := first.
		[ index <= end and: [ (buffer at: index) >= 48 and: [ (buffer at: index) <= 57 ] ] ]
			whileTrue: [ index := index + 1 ].
		(index > first and: [ index - first <= 9 ]) ifFalse: [ ^ nil ].
		nanoSecond := self nanoSecondsIn: buffer from: first count: index - first ].
	offset := 0.
	(index <= end and: [ (buffer at: index) = 43 or: [ (buffer at: index) = 45 ] ]) ifTrue: [ | hours minutes |
		index + 2 <= end ifFalse: [ ^ nil ].
		(hours := self digitsIn: buffer from: index + 1 count: 2) ifNil: [ ^ nil ].
		minutes := 0.
		index + 2 < end ifTrue: [
			((buffer at: index + 3) = 58 and: [ index + 5 = end ]) ifFalse: [ ^ nil ].
			(minutes := self digitsIn: buffer from: index + 4 count: 2) ifNil: [ ^ nil ] ].
		offset := hours * 3600 + (minutes * 60).
		(buffer at: index) = 45 ifTrue: [ offset := offset negated ].
		index := end + 1 ].
	index = (end + 1) ifFalse: [ ^ nil ].
	timestamp := [ timestampClass
			year: year month: month day: day
			hour: hour minute: minute second: second
			nanoSecond: nanoSecond
			offset: offset seconds ]
		on: DateError
		do: [ :error | ^ nil ].
	aTimezoneOrNil ifNotNil: [
		zoneOffset := aTimezoneOrNil offsetForTimestamp: timestamp.
		zoneOffset isZero ifFalse: [
			timestamp := timestampClass == DateAndTime
				ifTrue: [ DateAndTime
					year: year month: month day: day
					hour: hour minute: minute second: second
					nanoSecond: nanoSecond
					offset: zoneOffset asDuration ]
				ifFalse: [ timestamp translateTo: zoneOffset ] ] ].
	bytes skip: length.
	^ timestamp
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

{ #category : 'input/output' }
P3Converter >> textCStringFrom: binaryStream [
	"Read a zero terminated string in the connection encoding. Text that is not valid in it is read as
	Latin-1 instead: this is used for error messages, and an error must never be lost because of how
	it is spelled."

	| bytes |
	bytes := ByteArray streamContents: [ :out |
		| byte |
		[ (byte := binaryStream next) = 0 ] whileFalse: [ out nextPut: byte ] ].
	^ [ self encoder decodeBytes: bytes ]
		on: Error
		do: [ :error | error return: (String streamContents: [ :out | bytes do: [ :each | out nextPut: each asCharacter ] ]) ]
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

{ #category : 'accessing' }
P3Converter >> unknownTypeConverter: aSelectorBlockOrNil [
	"Read the values of a type without a converter with aSelectorBlockOrNil, a selector or a block like
	the ones of #mapOid:type:to:. Without one, which is the default, such a value signals a P3Error."

	unknownTypeConverter := aSelectorBlockOrNil
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

{ #category : 'converting' }
P3Converter >> utf8StringFrom: bytes length: length [
	"Decode the next length bytes of bytes, a ReadStream on a ByteArray, as UTF-8 and move past them.
	Answer nil and leave bytes where it was when they hold anything but ASCII and valid sequences of
	two and three bytes: a sequence of four bytes, an invalid one, or U+FEFF, which my encoder skips.

	The bytes are copied into a ByteString with one primitive. The primitive scan for bytes from 128 on
	runs on that copy, so it stops at the end of the value. Each run of ASCII is copied with one
	primitive, and only the other sequences are decoded one by one, in place, because a character
	never needs more room than its bytes. The result becomes a WideString at the first character
	beyond U+00FF."

	| raw string highBytes count index |
	raw := ByteString new: length.
	raw replaceFrom: 1 to: length with: bytes originalContents startingAt: bytes position + 1.
	highBytes := self class highByteSet.
	index := ByteString findFirstInString: raw inSet: highBytes startingAt: 1.
	index = 0 ifTrue: [
		bytes skip: length.
		^ raw ].
	string := raw.
	count := index - 1.
	[ index <= length ] whileTrue: [ | byte code |
		byte := raw byteAt: index.
		byte < 128
			ifTrue: [ | last |
				last := ByteString findFirstInString: raw inSet: highBytes startingAt: index.
				last := last = 0 ifTrue: [ length ] ifFalse: [ last - 1 ].
				string replaceFrom: count + 1 to: count + last - index + 1 with: raw startingAt: index.
				count := count + last - index + 1.
				index := last + 1 ]
			ifFalse: [
				(byte bitAnd: 2r11100000) = 2r11000000
					ifTrue: [ | second |
						index < length ifFalse: [ ^ nil ].
						second := raw byteAt: index + 1.
						(second bitAnd: 2r11000000) = 2r10000000 ifFalse: [ ^ nil ].
						code := ((byte bitAnd: 2r00011111) bitShift: 6) + (second bitAnd: 2r00111111).
						code < 128 ifTrue: [ ^ nil ].
						index := index + 2 ]
					ifFalse: [ | second third |
						(byte bitAnd: 2r11110000) = 2r11100000 ifFalse: [ ^ nil ].
						index + 2 <= length ifFalse: [ ^ nil ].
						second := raw byteAt: index + 1.
						third := raw byteAt: index + 2.
						((second bitAnd: 2r11000000) = 2r10000000 and: [ (third bitAnd: 2r11000000) = 2r10000000 ])
							ifFalse: [ ^ nil ].
						code := (((byte bitAnd: 2r00001111) bitShift: 12) + ((second bitAnd: 2r00111111) bitShift: 6))
							+ (third bitAnd: 2r00111111).
						(code < 2048 or: [ (code between: 16rD800 and: 16rDFFF) or: [ code = 16rFEFF ] ])
							ifTrue: [ ^ nil ].
						index := index + 3 ].
				(code > 255 and: [ string isWideString not ]) ifTrue: [
					string := (WideString new: length)
						replaceFrom: 1 to: count with: raw startingAt: 1;
						yourself ].
				string at: (count := count + 1) put: (Character value: code) ] ].
	bytes skip: length.
	^ count = length
		ifTrue: [ string ]
		ifFalse: [ string copyFrom: 1 to: count ]
]
