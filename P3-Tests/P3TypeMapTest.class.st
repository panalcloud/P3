"
I test P3TypeMap: the read-only standard table, and the extensions that a connection layers on top of it without changing it.
"
Class {
	#name : 'P3TypeMapTest',
	#superclass : 'TestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests' }
P3TypeMapTest >> testConvertersDoNotShareMappings [
	| first second block |
	block := [ :bytes :length :description | 0 ].
	first := P3Converter new.
	second := P3Converter new.
	first mapOid: 23 type: #int4 to: block.
	self
		assert: (second typeMap mappingAt: 23 ifAbsent: [ self fail ]) converter
		equals: #convertIntegerFrom:length:description:
]

{ #category : 'tests' }
P3TypeMapTest >> testDescriptionsAnswerTheTypeNameOfTheMap [
	| row parameter |
	row := P3RowFieldDescription new typeOid: 869; yourself.
	parameter := P3ParameterDescription new typeOid: 23; yourself.
	self assert: row typeName identicalTo: #oid869.
	self assert: parameter typeName identicalTo: #int4.
	parameter typeOid: 869.
	self assert: parameter typeName identicalTo: #oid869
]

{ #category : 'tests' }
P3TypeMapTest >> testExtensionAddsTypesAndFallsBackToTheStandard [
	| extension |
	extension := P3TypeMap standard extension.
	extension mapOid: 99999 type: #custom to: #convertStringFrom:length:description:.
	self assert: (extension nameAt: 99999 ifAbsent: [ nil ]) equals: #custom.
	self assert: (extension nameAt: 23 ifAbsent: [ nil ]) equals: #int4.
	self assert: (P3TypeMap standard nameAt: 99999 ifAbsent: [ nil ]) isNil
]

{ #category : 'tests' }
P3TypeMapTest >> testExtensionOverloadsWithoutChangingTheStandard [
	| extension block |
	block := [ :bytes :length :description | 0 ].
	extension := P3TypeMap standard extension.
	extension mapOid: 23 type: #int4 to: block.
	self assert: (extension mappingAt: 23 ifAbsent: [ self fail ]) converter equals: block.
	self
		assert: (P3TypeMap standard mappingAt: 23 ifAbsent: [ self fail ]) converter
		equals: #convertIntegerFrom:length:description:
]

{ #category : 'tests' }
P3TypeMapTest >> testMapArrayOidRecordsTheElementType [
	| extension mapping |
	extension := P3TypeMap standard extension.
	extension mapArrayOid: 99998 type: #_custom elementOid: 1700.
	mapping := extension mappingAt: 99998 ifAbsent: [ self fail ].
	self assert: mapping isArray.
	self assert: mapping elementOid equals: 1700.
	self assert: mapping converter equals: #convertArrayFrom:length:description:
]

{ #category : 'tests' }
P3TypeMapTest >> testRestoreOidDropsTheOverloadAndKeepsTheRest [
	| extension |
	extension := P3TypeMap standard extension.
	extension mapOid: 23 type: #int4 to: [ :b :l :d | 0 ].
	extension mapOid: 99999 type: #custom to: #convertStringFrom:length:description:.
	extension restoreOid: 23.
	self
		assert: (extension mappingAt: 23 ifAbsent: [ self fail ]) converter
		equals: #convertIntegerFrom:length:description:.
	self assert: (extension nameAt: 99999 ifAbsent: [ nil ]) equals: #custom
]

{ #category : 'tests' }
P3TypeMapTest >> testStandardCannotBeChanged [
	self
		should: [ P3TypeMap standard mapOid: 23 type: #int4 to: [ :b :l :d | 0 ] ]
		raise: Error.
	self
		assert: (P3TypeMap standard mappingAt: 23 ifAbsent: [ self fail ]) converter
		equals: #convertIntegerFrom:length:description:
]

{ #category : 'tests' }
P3TypeMapTest >> testStandardKnowsScalarAndArrayTypes [
	| int4 numericArray |
	int4 := P3TypeMap standard mappingAt: 23 ifAbsent: [ self fail ].
	self assert: int4 name equals: #int4.
	self assert: int4 converter equals: #convertIntegerFrom:length:description:.
	self deny: int4 isArray.
	numericArray := P3TypeMap standard mappingAt: 1231 ifAbsent: [ self fail ].
	self assert: numericArray name equals: #_numeric.
	self assert: numericArray elementOid equals: 1700.
	self assert: numericArray isArray
]

{ #category : 'tests' }
P3TypeMapTest >> testSupportedTypesIncludeTheExtensionAndTheStandard [
	| extension |
	extension := P3TypeMap standard extension.
	extension mapOid: 99999 type: #custom to: #convertStringFrom:length:description:.
	self assert: (extension supportedTypes includes: #custom).
	self assert: (extension supportedTypes includes: #int4).
	self deny: (P3TypeMap standard supportedTypes includes: #custom)
]

{ #category : 'tests' }
P3TypeMapTest >> testTypeNameAnswersASymbolForKnownAndUnknownOids [
	self assert: (P3TypeMap standard typeNameAt: 23) identicalTo: #int4.
	self assert: (P3TypeMap standard typeNameAt: 869) identicalTo: #oid869.
	self assert: (P3TypeMap standard typeNameAt: 869) identicalTo: #oid869.
	self assert: (P3TypeMap standard extension typeNameAt: 4294967295) identicalTo: #oid4294967295
]

{ #category : 'tests' }
P3TypeMapTest >> testUnknownNamesHaveTheDigitsOfTheOid [
	#( 0 7 10 99 100 869 1000000 4294967295 ) do: [ :oid |
		self
			assert: (P3TypeMap standard typeNameAt: oid + 1000000000)
			identicalTo: ('oid' , (oid + 1000000000) printString) asSymbol.
		self
			assert: (P3TypeMap standard extension typeNameAt: oid)
			identicalTo: ('oid' , oid printString) asSymbol ]
]

{ #category : 'tests' }
P3TypeMapTest >> testUnknownOidAnswersTheIfAbsentValue [
	self assert: (P3TypeMap standard mappingAt: 869 ifAbsent: [ #none ]) equals: #none.
	self assert: (P3TypeMap standard nameAt: 869 ifAbsent: [ 869 ]) equals: 869
]
