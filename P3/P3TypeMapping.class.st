"
I am one entry of a P3TypeMap: the type OID, the type name, and the converter that reads values of that type. The converter is a selector understood by P3Converter, or a block taking bytes, length and description.
"
Class {
	#name : 'P3TypeMapping',
	#superclass : 'Object',
	#instVars : [
		'oid',
		'name',
		'converter'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'instance creation' }
P3TypeMapping class >> oid: anInteger name: aSymbol converter: aSelectorOrBlock [
	^ self new
		oid: anInteger name: aSymbol converter: aSelectorOrBlock;
		yourself
]

{ #category : 'accessing' }
P3TypeMapping >> converter [
	^ converter
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
P3TypeMapping >> oid: anInteger name: aSymbol converter: aSelectorOrBlock [
	oid := anInteger.
	name := aSymbol.
	converter := aSelectorOrBlock
]

{ #category : 'printing' }
P3TypeMapping >> printOn: stream [
	super printOn: stream.
	stream nextPut: $(; print: oid; space; print: name; nextPut: $)
]
