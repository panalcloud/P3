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
		'dateStyle',
		'intervalStyle'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

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
	
	^ self typeMap values collect: #first
]

{ #category : 'accessing' }
P3Converter class >> typeMap [
	^ IdentityDictionary newFromPairs: #(
			16 #(bool #convertBooleanFrom:length:description:) 
			17 #(bytea #convertByteArrayFrom:length:description:) 
			18 #(#'"char"' #convertCharacterFrom:length:description:)
			19 #(name #convertStringFrom:length:description:) 
			20 #(int8 #convertIntegerFrom:length:description:) 
			21 #(int2 #convertIntegerFrom:length:description:) 
			22 #(int2vector #convertIntegerVectorFrom:length:description:)
			23 #(int4 #convertIntegerFrom:length:description:) 
			24 #(regproc #convertStringFrom:length:description:)
			25 #(text #convertStringFrom:length:description:) 
			26 #(oid #convertIntegerFrom:length:description:) 
			28 #(xid #convertIntegerFrom:length:description:)
			29 #(cid #convertIntegerFrom:length:description:)
			194 #(pg_node_tree #convertStringFrom:length:description:)
			700 #(float4 #convertFloatFrom:length:description:) 
			701 #(float8 #convertFloatFrom:length:description:) 
			1042 #(bpchar #convertStringFrom:length:description:) 
			1043 #(varchar #convertStringFrom:length:description:)
			1560 #(bit #convertFixedBitStringFrom:length:description:)
			1562 #(varbit #convertBitStringFrom:length:description:)
			1700 #(numeric #convertScaledDecimalFrom:length:description:) 
			2278 #(void #convertVoidFrom:length:description:)
			"chronology"
			1082 #(date #convertDateFrom:length:description:) 
			1083 #(time #convertTimeFrom:length:description:) 
			1114 #(timestamp #convertDateAndTimeWithoutTimezoneFrom:length:description:) 
			1184 #(timestamptz #convertDateAndTimeFrom:length:description:)
			1186 #(interval #convertIntervalFrom:length:description:)
			1266 #(timetz #convertTimeWithTimezoneFrom:length:description:)
			"special"
			114 #(json #convertJsonFrom:length:description:)
			2950 #(uuid #convertUuidFrom:length:description:)
			3802 #(jsonb #convertJsonFrom:length:description:)
			"arrays"
			1000 #(#'_bool' #convertBooleanArrayFrom:length:description:)
			1007 #(#'_int4' #convertIntegerArrayFrom:length:description:)
			1009 #(#'_text' #convertStringArrayFrom:length:description:)
			1015 #(#'_varchar' #convertStringArrayFrom:length:description:)
			1022 #(#'_float8' #convertFloatArrayFrom:length:description:)
			1028 #(#'_oid' #convertIntegerArrayFrom:length:description:)
			1034 #(#'_aclitem' #convertStringArrayFrom:length:description:)
			"geometric"
			600 #(point #convertPointFrom:length:description:)
			601 #(lseg #convertLineSegmentFrom:length:description:)
			602 #(path #convertPathFrom:length:description:)
			603 #(box #convertBoxFrom:length:description:)
			604 #(polygon #convertPolygonFrom:length:description:)
			628 #(line #convertLineFrom:length:description:)
			718 #(circle #convertCircleFrom:length:description:)
			"vectors"
			30 #( oidvector #convertIntegerVectorFrom:length:description: )
		)
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
	^ map 
		at: description typeOid 
		ifPresent: [ :type | | lambda |
			lambda := type second.
	 		lambda isSymbol 
				ifTrue: [ self perform: lambda with: bytes with: length with: description ]
				ifFalse: [ lambda value: bytes value: length value: description ] ]
		ifAbsent: [ (P3Error cannotConvertTypeOid: description typeOid) signal ]
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
	| size byteArray digitValues |
	self assert: (bytes next: 2) = #[92 120]. "\x"
	size := (length - 2) // 2.
	digitValues := #(-1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 0 1 2 3 4 5 6 7 8 9 -1 -1 -1 -1 -1 -1 -1 10 11 12 13 14 15 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 10 11 12 13 14 15 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1).
	byteArray := ByteArray new: size.
	1 to: size do: [ :index | | value |
		value := digitValues at: bytes next + 1.
		value := (value bitShift: 4) + (digitValues at: bytes next + 1).
		byteArray at: index put: value ].
	^ byteArray 
]

{ #category : 'converting' }
P3Converter >> convertCharacterFrom: bytes length: length description: description [
	"""char"" (OID 18): PostgreSQL's internal single-byte type, always exactly one byte, not
	to be confused with bpchar/varchar (which read as String) or one encoded character of
	text."

	self assert: length = 1.
	^ Character value: bytes next
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
	offset := self timezone offsetForTimestamp: timestamp.
	^ offset isZero
		ifTrue: [ timestamp ]
		ifFalse: [ timestamp translateTo: offset ]
]

{ #category : 'converting-chronology' }
P3Converter >> convertDateFrom: bytes length: length description: description [
	"For this to work, the connection output format must be ISO, the default.
	See P3Converter>>#dateStyle:, which maps me away when it is not."
	
	^ (P3ISO8601Parser on: (self asciiStreamFor: bytes length: length)) parseDate
]

{ #category : 'converting' }
P3Converter >> convertFixedBitStringFrom: bytes length: length description: description [
	^ P3FixedBitString readFrom: (self asciiStreamFor: bytes length: length)
]

{ #category : 'converting' }
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
	"For this to work, the connection output format must be postgres, the default.
	See P3Converter>>#intervalStyle:, which maps me away when it is not."

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
	For this to work, the connection output format must be ISO, the default"

	| parser time offset connectionOffset translatedTime |
	parser := P3ISO8601Parser on: (self asciiStreamFor: bytes length: length).
	time := parser parseTime.
	offset := parser parseOptionalTimezoneOffset seconds.
	connectionOffset := self timezone offsetForTimestamp: (ZTimestamp today + time).
	^ offset = connectionOffset 
		ifTrue: [ time ]
		ifFalse: [ 
			translatedTime := time subtractTime: (offset - connectionOffset).
			^ translatedTime seconds < 0 
				ifTrue: [ translatedTime addSeconds: 24 * 60 * 60 ]
				ifFalse: [ translatedTime ] ]
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

{ #category : 'private' }
P3Converter >> floatDigitsFrom: stream [
	"The decimal digits at the current position, possibly none."

	^ String streamContents: [ :out |
		[ stream atEnd not and: [ stream peek isDigit ] ] whileTrue: [ out nextPut: stream next ] ]
]

{ #category : 'converting' }
P3Converter >> floatFrom: aString [
	"Read the text of a float4 or float8, as the server writes it: digits with an optional fraction and
	an optional exponent with its own sign (1e+100, -1.5e-07), or NaN, Infinity and -Infinity.
	The value is the exact decimal fraction rounded once to a double, so every double that the server
	prints with the digits that identify it is read back as the same double. A negative zero keeps its sign."

	| text stream negative wholeDigits fractionDigits mantissa exponent exponentDigits exponentNegative value |
	text := aString trimmed.
	text = 'NaN' ifTrue: [ ^ Float nan ].
	(text = 'Infinity' or: [ text = '+Infinity' ]) ifTrue: [ ^ Float infinity ].
	text = '-Infinity' ifTrue: [ ^ Float infinity negated ].
	stream := text readStream.
	negative := stream peekFor: $-.
	negative ifFalse: [ stream peekFor: $+ ].
	wholeDigits := self floatDigitsFrom: stream.
	fractionDigits := (stream peekFor: $.)
		ifTrue: [ self floatDigitsFrom: stream ]
		ifFalse: [ '' ].
	(wholeDigits isEmpty and: [ fractionDigits isEmpty ]) ifTrue: [ ^ (P3Error parsingFailed: aString) signal ].
	exponent := 0.
	((stream peekFor: $e) or: [ stream peekFor: $E ]) ifTrue: [
		exponentNegative := stream peekFor: $-.
		exponentNegative ifFalse: [ stream peekFor: $+ ].
		exponentDigits := self floatDigitsFrom: stream.
		exponentDigits isEmpty ifTrue: [ ^ (P3Error parsingFailed: aString) signal ].
		exponent := exponentNegative ifTrue: [ exponentDigits asInteger negated ] ifFalse: [ exponentDigits asInteger ] ].
	stream atEnd ifFalse: [ ^ (P3Error parsingFailed: aString) signal ].
	mantissa := (wholeDigits , fractionDigits) asInteger.
	mantissa = 0 ifTrue: [ ^ negative ifTrue: [ Float negativeZero ] ifFalse: [ 0.0 ] ].
	value := (mantissa * (10 raisedTo: exponent - fractionDigits size)) asFloat.
	^ negative ifTrue: [ value negated ] ifFalse: [ value ]
]

{ #category : 'initialize' }
P3Converter >> initialize [
	super initialize.
	asciiReadStream := String new readStream.
	asciiWriteStream := String new writeStream.
	stringWriteStream := String new writeStream.
	timestampClass := DateAndTime.
	self initializeTypeMap
]

{ #category : 'initialize' }
P3Converter >> initializeFrom: properties [
	| serverTimezone serverEncoder |
	"Try to resolve the session/connection timezone"
	serverTimezone := properties at: 'TimeZone' ifAbsent: [ 'GMT' ].
	"The fallback for unknown timezones is normally GMT but can be overwritten with ZCurrentTimezone."
	serverTimezone := [ ZTimezone id: serverTimezone ] on: Error do: [ ZCurrentTimezone value ].
	self timezone: serverTimezone.
	"Try to resolve the session/connection character encoder/decoder"
	serverEncoder := properties at: 'client_encoding' ifAbsent: [ 'UTF8' ].
	"The fallback for unknown encodings is normally UTF8 but can be overwritten ZnDefaultCharacterEncoder."
	serverEncoder := ZnCharacterEncoder newForEncoding: serverEncoder.
	self encoder: serverEncoder.
	"The output styles I can read. A missing one means the server did not report it, so assume its default."
	self dateStyle: (properties at: 'DateStyle' ifAbsent: [ nil ]).
	self intervalStyle: (properties at: 'IntervalStyle' ifAbsent: [ nil ])
]

{ #category : 'initialize' }
P3Converter >> initializeTypeMap [
	map := self class typeMap
]

{ #category : 'private' }
P3Converter >> installConvertersFor: typeOids refusing: aBlockOrNil [
	"Point typeOids at their standard converters, or at aBlockOrNil when that is not nil. The session's
	output styles decide which, and they only change when the server reports a change, so the decision is
	made here instead of on every value read. A caller that installed its own converter for one of these
	OIDs loses it when a style changes."

	| standard |
	standard := self class typeMap.
	typeOids do: [ :oid |
		| type |
		type := standard at: oid.
		self mapOid: oid type: type first to: (aBlockOrNil ifNil: [ type second ]) ]
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

	^ map at: anOoid put: { aTypename . aBlockOrSymbol }	
]

{ #category : 'accessing' }
P3Converter >> noteSessionParameter: key value: value [
	"React to a server parameter that decides how I read values. Values arrive as text, so these four
	change what that text means, and the server reports each change as a ParameterStatus message.
	Anything else I do not care about."

	key = 'client_encoding' ifTrue: [ ^ self clientEncoding: value ].
	key = 'TimeZone' ifTrue: [ ^ self serverTimezone: value ].
	key = 'DateStyle' ifTrue: [ ^ self dateStyle: value ].
	key = 'IntervalStyle' ifTrue: [ ^ self intervalStyle: value ]
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

{ #category : 'accessing' }
P3Converter >> serverTimezone: aString [
	"Shift timestamps without a time zone using the session's zone. An unknown name falls back the
	way #initializeFrom: does."

	self timezone: ([ ZTimezone id: aString ] on: Error do: [ ZCurrentTimezone value ])
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
	timezone := anObject
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
