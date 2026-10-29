"
I am one entry of a P3TypeMap: the type OID, the type name, and the converter that reads values of that type. The converter is a selector understood by P3Converter, or a block taking bytes, length and description. An array type also knows the OID of its element type, and is read through the converter of that type.
"
Class {
	#name : 'P3TypeMapping',
	#superclass : 'Object',
	#instVars : [
		'oid',
		'name',
		'converter',
		'elementOid'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'instance creation' }
P3TypeMapping class >> arrayOid: anInteger name: aSymbol elementOid: anElementInteger [
	^ self new
		oid: anInteger name: aSymbol converter: #convertArrayFrom:length:description: elementOid: anElementInteger;
		yourself
]

{ #category : 'instance creation' }
P3TypeMapping class >> oid: anInteger name: aSymbol converter: aSelectorOrBlock [
	^ self new
		oid: anInteger name: aSymbol converter: aSelectorOrBlock elementOid: nil;
		yourself
]

{ #category : 'accessing' }
P3TypeMapping >> converter [
	^ converter
]

{ #category : 'accessing' }
P3TypeMapping >> elementOid [
	"The OID of the element type, or nil when I am not an array type."

	^ elementOid
]

{ #category : 'testing' }
P3TypeMapping >> isArray [
	^ elementOid notNil
]

{ #category : 'accessing' }
P3TypeMapping >> name [
	^ name
]

{ #category : 'accessing' }
P3TypeMapping >> oid [
	^ oid
]

{ #category : 'initialization' }
P3TypeMapping >> oid: anInteger name: aSymbol converter: aSelectorOrBlock elementOid: anIntegerOrNil [
	oid := anInteger.
	name := aSymbol.
	converter := aSelectorOrBlock.
	elementOid := anIntegerOrNil
]

{ #category : 'printing' }
P3TypeMapping >> printOn: stream [
	super printOn: stream.
	stream nextPut: $(; print: oid; space; print: name; nextPut: $)
]
