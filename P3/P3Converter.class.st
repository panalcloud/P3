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
		'timestampClass'
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
	"For this to work, the connection output format must be ISO, the default"
	
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
	^ ScaledDecimal readFrom: (self asciiStreamFor: bytes length: length)
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
	self encoder: serverEncoder
]

{ #category : 'initialize' }
P3Converter >> initializeTypeMap [
	"My own extension of the standard map, so that #mapOid:type:to: changes no other converter."

	map := P3TypeMap standard extension
]

{ #category : 'accessing' }
P3Converter >> mapOid: anOoid type: aTypename to: aBlockOrSymbol [
	^ map mapOid: anOoid type: aTypename to: aBlockOrSymbol
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

{ #category : 'accessing' }
P3Converter >> typeMap [
	^ map
]
