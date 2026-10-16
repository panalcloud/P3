"
I test P3MessageBuffer>>#isPartial: after a read that ended inside a message, the stream is not at a message boundary and cannot be read on.
"
Class {
	#name : 'P3MessageBufferTest',
	#superclass : 'TestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests' }
P3MessageBufferTest >> testCompleteMessageIsNotPartial [
	| buffer |
	buffer := P3MessageBuffer new.
	buffer readFrom: #[ 90 0 0 0 5 73 ] readStream.
	self assert: buffer tag equals: $Z.
	self deny: buffer isPartial
]

{ #category : 'tests' }
P3MessageBufferTest >> testNextCompleteReadClearsPartial [
	| buffer |
	buffer := P3MessageBuffer new.
	self should: [ buffer readFrom: (P3StallingStream on: #[ 68 0 ]) ] raise: ConnectionTimedOut.
	buffer readFrom: #[ 90 0 0 0 5 73 ] readStream.
	self deny: buffer isPartial
]

{ #category : 'tests' }
P3MessageBufferTest >> testNothingReadIsNotPartial [
	| buffer |
	buffer := P3MessageBuffer new.
	self should: [ buffer readFrom: #[] readStream ] raise: ConnectionClosed.
	self deny: buffer isPartial
]

{ #category : 'tests' }
P3MessageBufferTest >> testReadThatStopsInsideAMessageIsPartial [
	"Stopped in the payload, in the length, or right after the tag."

	#( #[ 68 0 0 0 10 1 2 ] #[ 68 0 0 ] #[ 68 ] ) do: [ :bytes | | buffer |
		buffer := P3MessageBuffer new.
		self should: [ buffer readFrom: (P3StallingStream on: bytes) ] raise: ConnectionTimedOut.
		self assert: buffer isPartial ]
]

{ #category : 'tests' }
P3MessageBufferTest >> testTimeoutBeforeTheFirstByteIsNotPartial [
	| buffer |
	buffer := P3MessageBuffer new.
	self should: [ buffer readFrom: (P3StallingStream on: #[]) ] raise: ConnectionTimedOut.
	self deny: buffer isPartial
]
