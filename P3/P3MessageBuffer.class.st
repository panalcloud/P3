"
I am P3MessageBuffer.

I am a reusable buffer to hold a single protocol message read.

I try to prevent allocations as much as possible.
I grow as needed.
"
Class {
	#name : 'P3MessageBuffer',
	#superclass : 'Object',
	#instVars : [
		'tag',
		'payload',
		'size',
		'partial'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'accessing' }
P3MessageBuffer class >> retainedCapacity [
	"The largest buffer I keep for the next message. A bigger one, made for a single large message like
	a row with a big value, is replaced by a small one as soon as a message does not need it, so that one
	large message does not pin its memory for the life of the connection."

	^ 1024 * 1024
]

{ #category : 'accessing' }
P3MessageBuffer >> capacity [
	^ self rawByteBuffer size
]

{ #category : 'initialization' }
P3MessageBuffer >> initialize [
	super initialize.
	self initializeForSize: 0
]

{ #category : 'initialization' }
P3MessageBuffer >> initializeForSize: actualSize [
	| retained |
	retained := self class retainedCapacity.
	(payload isNil
		or: [ actualSize > self capacity
		or: [ self capacity > retained and: [ actualSize <= retained ] ] ])
		ifTrue: [ payload := (ByteArray new: ((actualSize // 1024) + 1) * 1024) readStream ].
	size := actualSize.
	payload setFrom: 1 to: size
]

{ #category : 'testing' }
P3MessageBuffer >> isPartial [
	"True when my last read stopped inside a message. The stream is then not at a message boundary, and
	nothing can be read from it any more."

	^ partial == true
]

{ #category : 'accessing' }
P3MessageBuffer >> payloadCopy [
	^ self rawByteBuffer copyFrom: 1 to: size
]

{ #category : 'accessing' }
P3MessageBuffer >> rawByteBuffer [
	^ payload originalContents
]

{ #category : 'reading' }
P3MessageBuffer >> readFrom: readStream [
	| byte length |
	partial := false.
	(byte := readStream next)
		ifNil: [ ^ ConnectionClosed signal ].
	partial := true.
	self tag: byte asCharacter.
	length := (self uint32From: readStream) - 4.
	self initializeForSize: length.
	length > 0
		ifTrue: [ readStream next: self size into: self rawByteBuffer ].
	partial := false
]

{ #category : 'accessing' }
P3MessageBuffer >> readStream [
	^ payload
]

{ #category : 'accessing' }
P3MessageBuffer >> size [
	^ size
]

{ #category : 'accessing' }
P3MessageBuffer >> tag [
	^ tag
]

{ #category : 'initialization' }
P3MessageBuffer >> tag: character [
	tag := character
]

{ #category : 'reading' }
P3MessageBuffer >> uint32From: stream [
	| uint32 |
	uint32 := stream next.
	uint32 := (uint32 bitShift: 8) + stream next.
	uint32 := (uint32 bitShift: 8) + stream next.
	uint32 := (uint32 bitShift: 8) + stream next.
	^ uint32
]
