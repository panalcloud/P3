"
I wrap a socket stream and forward everything to it, except that the first write fails with ConnectionClosed, like a connection that the network dropped while the client still saw it as open.
"
Class {
	#name : 'P3FailingWriteStream',
	#superclass : 'Object',
	#instVars : [
		'stream',
		'armed'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'instance creation' }
P3FailingWriteStream class >> on: aStream [
	^ self new setStream: aStream
]

{ #category : 'forwarding' }
P3FailingWriteStream >> doesNotUnderstand: aMessage [
	^ aMessage sendTo: stream
]

{ #category : 'writing' }
P3FailingWriteStream >> nextPut: anObject [
	armed ifTrue: [
		armed := false.
		^ ConnectionClosed signal: 'simulated broken connection' ].
	^ stream nextPut: anObject
]

{ #category : 'initialization' }
P3FailingWriteStream >> setStream: aStream [
	stream := aStream.
	armed := true
]
