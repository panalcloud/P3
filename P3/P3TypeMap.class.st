"
I map PostgreSQL type OIDs to P3TypeMapping objects. The standard map (see #standard) is built once, shared and read-only. A connection works on an extension (see #extension): its own mappings are looked up first, then those of the map it extends, so a connection can add types or overload converters without touching the standard map or any other connection.
"
Class {
	#name : 'P3TypeMap',
	#superclass : 'Object',
	#instVars : [
		'mappings',
		'parent',
		'isFrozen',
		'unknownNames',
		'unknownNamesMutex'
	],
	#classVars : [
		'Standard'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'initialization' }
P3TypeMap class >> initialize [
	"Drop the standard map, so that it is built again from #newStandard when next used."

	Standard := nil
]

{ #category : 'instance creation' }
P3TypeMap class >> newStandard [
	| map |
	map := self new.
	#(
			16 #(bool #convertBooleanFrom:length:description:) 
			17 #(bytea #convertByteArrayFrom:length:description:) 
			18 #(#'"char"' #convertCharacterFrom:length:description:)
			19 #(name #convertStringFrom:length:description:) 
			20 #(int8 #convertIntegerFrom:length:description:) 
			21 #(int2 #convertIntegerFrom:length:description:) 
			23 #(int4 #convertIntegerFrom:length:description:) 
			25 #(text #convertStringFrom:length:description:) 
			26 #(oid #convertIntegerFrom:length:description:) 
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
		) pairsDo: [ :oid :type |
			map mapOid: oid type: type first to: type second ].
	^ map freeze; yourself
]

{ #category : 'accessing' }
P3TypeMap class >> standard [
	"The shared, read-only map of the types P3 reads out of the box."

	^ Standard ifNil: [ Standard := self newStandard ]
]

{ #category : 'extending' }
P3TypeMap >> add: aMapping [
	isFrozen ifTrue: [ ^ self error: 'This type map is read-only, use an extension of it' ].
	^ mappings at: aMapping oid put: aMapping
]

{ #category : 'extending' }
P3TypeMap >> extension [
	"Answer a new, empty and changeable map that falls back to me."

	^ self class new
		parent: self;
		yourself
]

{ #category : 'extending' }
P3TypeMap >> freeze [
	"After this I refuse changes."

	isFrozen := true
]

{ #category : 'initialization' }
P3TypeMap >> initialize [
	super initialize.
	mappings := IdentityDictionary new.
	unknownNames := IdentityDictionary new.
	unknownNamesMutex := Mutex new.
	isFrozen := false
]

{ #category : 'extending' }
P3TypeMap >> mapOid: anOid type: aTypeName to: aSelectorOrBlock [
	"Read values of type anOid with aSelectorOrBlock, replacing any earlier mapping of it."

	^ self add: (P3TypeMapping oid: anOid name: aTypeName converter: aSelectorOrBlock)
]

{ #category : 'accessing' }
P3TypeMap >> mappingAt: anOid ifAbsent: aBlock [
	^ mappings
		at: anOid
		ifAbsent: [ parent
			ifNil: [ aBlock value ]
			ifNotNil: [ parent mappingAt: anOid ifAbsent: aBlock ] ]
]

{ #category : 'accessing' }
P3TypeMap >> nameAt: anOid ifAbsent: aBlock [
	^ (self mappingAt: anOid ifAbsent: [ ^ aBlock value ]) name
]

{ #category : 'private' }
P3TypeMap >> newUnknownNameAt: anOid [
	"Stream 'oid' and the digits of anOid. An OID is a SmallInteger, which prints its digits straight onto the stream."

	^ (String streamContents: [ :stream |
		stream nextPutAll: 'oid'.
		anOid printOn: stream ]) asSymbol
]

{ #category : 'accessing' }
P3TypeMap >> oids [
	"The OIDs I can read, including those of the map I extend."

	^ parent
		ifNil: [ mappings keys ]
		ifNotNil: [ (parent oids , mappings keys) asSet asArray ]
]

{ #category : 'extending' }
P3TypeMap >> parent: aTypeMap [
	parent := aTypeMap
]

{ #category : 'extending' }
P3TypeMap >> restoreOid: anOid [
	"Drop my own mapping of anOid, so the one of the map I extend applies again."

	isFrozen ifTrue: [ ^ self error: 'This type map is read-only, use an extension of it' ].
	mappings removeKey: anOid ifAbsent: [ ]
]

{ #category : 'accessing' }
P3TypeMap >> supportedTypes [
	"The names of the types I can read."

	^ self oids collect: [ :oid | self nameAt: oid ifAbsent: [ oid ] ]
]

{ #category : 'accessing' }
P3TypeMap >> typeNameAt: anOid [
	"The name of the type, as a Symbol. A type I do not know is named after its OID, like #oid869."

	^ self nameAt: anOid ifAbsent: [ self unknownNameAt: anOid ]
]

{ #category : 'private' }
P3TypeMap >> unknownNameAt: anOid [
	"The Symbol is built once per OID, because the same few unknown types come back for every row of a result."

	^ unknownNamesMutex critical: [
		unknownNames at: anOid ifAbsentPut: [ self newUnknownNameAt: anOid ] ]
]
