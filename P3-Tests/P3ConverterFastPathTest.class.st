"
I check that the fast readers of P3Converter, which read text, integers, numerics, dates, times and timestamps straight from the bytes of a message, answer what its general readers answer. Each test reads many random texts, valid and not, both ways: from a ReadStream, which the fast readers take, and from a P3GeneralReadStream, which they do not. The value, its class, its scale or offset, the error and the position of the stream afterwards must be the same.

JSON is checked the same way against a NeoJSONReader on a character stream over the same bytes: the classes, the order and the values of everything read, the identity of the keys, and the bytes consumed.

The texts are random with a fixed seed, so a failure can be reproduced. I need no server.
"
Class {
	#name : 'P3ConverterFastPathTest',
	#superclass : 'TestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3ConverterFastPathTest >> assertReadersAgreeOn: bytes with: selector converter: converter [
	| fast general |
	fast := self outcomeOf: selector bytes: bytes on: ReadStream converter: converter.
	general := self outcomeOf: selector bytes: bytes on: P3GeneralReadStream converter: converter.
	self
		assert: fast = general
		description: [ selector , ' of ' , bytes printString , ' answers ' , fast printString , ' instead of ' , general printString ]
]

{ #category : 'private' }
P3ConverterFastPathTest >> jsonShapeOf: anObject [
	"What two readings of a JSON text must share: the classes and the order of all values, the
	identity of the keys, and the values themselves"

	^ String streamContents: [ :out | self printJsonShapeOf: anObject on: out ]
]

{ #category : 'private' }
P3ConverterFastPathTest >> outcomeOf: selector bytes: bytes on: streamClass converter: converter [
	"Read bytes, placed between other bytes, with selector of converter from a stream of streamClass.
	Answer what can be compared: the value or the class of the error, the value's class, its scale or
	offset, and the position of the stream afterwards."

	| stream value |
	stream := streamClass on: #[ 9 ] , bytes , #[ 1 2 ].
	stream skip: 1.
	value := [ converter perform: selector with: stream with: bytes size with: nil ]
		on: Error
		do: [ :error | error class ].
	^ Array
		with: value printString
		with: value class
		with: ((value isKindOf: ScaledDecimal)
			ifTrue: [ value scale ]
			ifFalse: [ ((value isKindOf: Magnitude) and: [ value respondsTo: #offset ]) ifTrue: [ value offset ] ])
		with: stream position
]

{ #category : 'private' }
P3ConverterFastPathTest >> printJsonShapeOf: anObject on: out [
	out nextPutAll: anObject class name; nextPut: $(.
	(anObject isKindOf: Dictionary)
		ifTrue: [
			anObject keysAndValuesDo: [ :key :value |
				out print: key; nextPutAll: (key isSymbol ifTrue: [ ' symbol ' ] ifFalse: [ ' string ' ]).
				self printJsonShapeOf: value on: out ] ]
		ifFalse: [
			(anObject isArray)
				ifTrue: [ anObject do: [ :each | self printJsonShapeOf: each on: out ] ]
				ifFalse: [ out print: anObject ] ].
	out nextPut: $)
]

{ #category : 'private' }
P3ConverterFastPathTest >> randomJsonDepth: depth using: random [
	"A random JSON text: objects, lists, strings with escapes and characters beyond ASCII, numbers and
	constants, with some whitespace between the tokens"

	| pick space keys strings |
	pick := [ :choices | choices at: (random nextInteger: choices size) ].
	space := [ pick value: #( '' '' '' ' ' '  ' ) ].
	keys := #( '"id"' '"name"' '"año"' '"a b"' '"kéy"' '""' '"123"' '"x\"y"' ).
	strings := #( '""' '"text"' '"José Núñez"' '"tab\there"' '"€ 10"' '"😀"' '"a\\b\/c"' '"€—"' ).
	(depth > 2 or: [ random next < 0.4 ]) ifTrue: [
		^ pick value: (strings , #( '0' '-7' '42' '1.5' '-2.5e-3' '1E10' '12345678901234567890' 'true' 'false' 'null' )) ].
	^ random next < 0.5
		ifTrue: [
			String streamContents: [ :out |
				out nextPut: ${.
				(1 to: (random nextInteger: 4) - 1)
					do: [ :each |
						out nextPutAll: space value; nextPutAll: (pick value: keys); nextPutAll: space value; nextPut: $:;
							nextPutAll: space value; nextPutAll: (self randomJsonDepth: depth + 1 using: random) ]
					separatedBy: [ out nextPut: $, ].
				out nextPutAll: space value; nextPut: $} ] ]
		ifFalse: [
			String streamContents: [ :out |
				out nextPut: $[.
				(1 to: (random nextInteger: 4) - 1)
					do: [ :each | out nextPutAll: space value; nextPutAll: (self randomJsonDepth: depth + 1 using: random) ]
					separatedBy: [ out nextPut: $, ].
				out nextPutAll: space value; nextPut: $] ] ]
]

{ #category : 'private' }
P3ConverterFastPathTest >> randomTextOf: pieces count: count using: random [
	"Concatenate count pieces chosen at random"

	^ String new: 32 streamContents: [ :out |
		count timesRepeat: [ out nextPutAll: (pieces at: (random nextInteger: pieces size)) ] ]
]

{ #category : 'tests' }
P3ConverterFastPathTest >> testChronologyReadersAgreeWithTheParser [
	"Dates, times and timestamps in plain and other forms, valid or not: years of four and five digits,
	impossible days and hours, fractions of up to ten digits, offsets with and without minutes and
	seconds, dates before the common era and infinity. In two session zones and with both timestamp
	classes."

	| random pick two four fraction offset |
	random := Random seed: 42.
	pick := [ :choices | choices at: (random nextInteger: choices size) ].
	two := [ pick value: #( '00' '01' '09' '10' '12' '23' '24' '28' '29' '30' '31' '59' '60' '13' '02' '3' '1a' ) ].
	four := [ pick value: #( '2024' '2023' '1999' '0001' '9999' '1900' '2000' '10000' '0000' '197' '20x4' ) ].
	fraction := [ pick value: #( '' '' '' '.5' '.12' '.123456' '.1234567' '.123456789' '.1234567890' '.' '.00001' '.9x' ) ].
	offset := [ pick value: #( '' '' '+00' '+01' '-03' '+05:30' '-03:30' '+00:19:32' '+5' '+01:' '-12:45' '+14' ' BC' '+02 BC' ) ].
	#( 'UTC' 'Europe/Brussels' ) do: [ :zone |
		{ DateAndTime. ZTimestamp } do: [ :timestampClass | | converter |
			converter := P3Converter new.
			converter serverTimezone: zone; timestampClass: timestampClass.
			300 timesRepeat: [ | date time timestamp |
				date := four value , '-' , two value , '-' , two value , ((random next < 0.1) ifTrue: [ ' BC' ] ifFalse: [ '' ]).
				time := two value , ':' , two value , ':' , two value , fraction value.
				timestamp := four value , '-' , two value , '-' , two value , ((random next < 0.9) ifTrue: [ ' ' ] ifFalse: [ 'T' ]) , time , offset value.
				(random next < 0.05) ifTrue: [ timestamp := pick value: #( 'infinity' '-infinity' '2024-01-01  10:00:00' ) ].
				self assertReadersAgreeOn: date asByteArray with: #convertDateFrom:length:description: converter: converter.
				self assertReadersAgreeOn: time asByteArray with: #convertTimeFrom:length:description: converter: converter.
				self assertReadersAgreeOn: timestamp asByteArray with: #convertDateAndTimeFrom:length:description: converter: converter.
				self assertReadersAgreeOn: timestamp asByteArray with: #convertDateAndTimeWithoutTimezoneFrom:length:description: converter: converter ] ] ]
]

{ #category : 'tests' }
P3ConverterFastPathTest >> testIntegerReaderAgreesWithIntegerReadFrom [
	| random pieces converter |
	random := Random seed: 42.
	converter := P3Converter new.
	pieces := #( '0' '1' '7' '9' '42' '1000000007' '9223372036854775807' '-' '+' ' ' '.' 'e' 'a' ).
	3000 timesRepeat: [ | text |
		text := self randomTextOf: pieces count: (random nextInteger: 5) using: random.
		self assertReadersAgreeOn: text asByteArray with: #convertIntegerFrom:length:description: converter: converter ]
]

{ #category : 'tests' }
P3ConverterFastPathTest >> testJsonReaderAgreesWithNeoJSONReader [
	"Random JSON texts read by the converter and by a NeoJSONReader on a character stream over the
	same bytes. The text may have whitespace around it, which must be consumed too."

	| random converter |
	random := Random seed: 42.
	converter := P3Converter new.
	2000 timesRepeat: [ | text bytes stream value expected |
		text := (#( '' ' ' '  ' ) atRandom: random) , (self randomJsonDepth: 0 using: random) , (#( '' ' ' '   ' ) atRandom: random).
		bytes := text utf8Encoded.
		stream := (#[ 9 ] , bytes , #[ 1 2 ]) readStream.
		stream skip: 1.
		value := converter convertJsonFrom: stream length: bytes size description: nil.
		expected := (NeoJSONReader on: (ZnCharacterReadStream on: bytes readStream encoding: 'utf8'))
			mapClass: NeoJSONObject;
			propertyNamesAsSymbols: true;
			next.
		self
			assert: (self jsonShapeOf: value) = (self jsonShapeOf: expected)
			description: [ text , ' reads as ' , (self jsonShapeOf: value) , ' instead of ' , (self jsonShapeOf: expected) ].
		self assert: stream position equals: bytes size + 1 ]
]

{ #category : 'tests' }
P3ConverterFastPathTest >> testNumericReaderAgreesWithScaledDecimalReadFrom [
	| random pieces converter |
	random := Random seed: 42.
	converter := P3Converter new.
	pieces := #( '0' '1' '5' '9' '37' '1234567890123456789012' '.' '.' '-' '+' ' ' 'e' 'NaN' 'Infinity' ).
	3000 timesRepeat: [ | text |
		text := self randomTextOf: pieces count: (random nextInteger: 5) using: random.
		self assertReadersAgreeOn: text asByteArray with: #convertScaledDecimalFrom:length:description: converter: converter ]
]

{ #category : 'tests' }
P3ConverterFastPathTest >> testTextReaderAgreesWithTheEncoder [
	"Sequences of ASCII, characters of two, three and four bytes, U+FEFF, and invalid or cut sequences"

	| random pieces converter |
	random := Random seed: 42.
	converter := P3Converter new.
	pieces := {
		'a' asByteArray. 'hello world' asByteArray. (ByteArray new: 300 withAll: 120).
		'ñ' utf8Encoded. 'é' utf8Encoded. (String with: (Character value: 255)) utf8Encoded.
		'€' utf8Encoded. '—' utf8Encoded. (String with: (Character value: 16rFFFD)) utf8Encoded.
		(String with: (Character value: 128512)) utf8Encoded. #[ 16rEF 16rBB 16rBF ].
		#[ 16rC3 ]. #[ 16rC0 16r80 ]. #[ 16rED 16rA0 16r80 ]. #[ 16rFF ]. #[ 16r80 ]. #[ 16rE2 16r82 ]. #[ 16rF0 16r9F ] }.
	3000 timesRepeat: [ | bytes |
		bytes := ByteArray streamContents: [ :out |
			(random nextInteger: 6) timesRepeat: [ out nextPutAll: (pieces at: (random nextInteger: pieces size)) ] ].
		self assertReadersAgreeOn: bytes with: #convertStringFrom:length:description: converter: converter ]
]

{ #category : 'tests' }
P3ConverterFastPathTest >> testTimestampsAroundChangesOfOffsetAgreeWithTheParser [
	"Every quarter of an hour of the days on which the offset of the session zone changes, also in the
	hour that does not exist and in the hour that exists twice"

	#( #( 'Europe/Brussels' '2024-03-31' '2024-10-27' ) #( 'America/Mexico_City' '2022-04-03' '2022-10-30' ) ) do: [ :each | | converter |
		converter := P3Converter new.
		converter serverTimezone: each first.
		each allButFirst do: [ :day |
			0 to: 95 do: [ :quarter | | text |
				text := day , ' ' , (quarter // 4 printPaddedWith: $0 to: 2) , ':' , (quarter \\ 4 * 15 printPaddedWith: $0 to: 2) , ':30.25'.
				self assertReadersAgreeOn: text asByteArray with: #convertDateAndTimeWithoutTimezoneFrom:length:description: converter: converter.
				self assertReadersAgreeOn: (text , '+01') asByteArray with: #convertDateAndTimeFrom:length:description: converter: converter ] ] ]
]
