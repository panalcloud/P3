"
I wrap a socket stream and forward everything to it. The first time my gated selector is sent, #flush or #nextPut:, I forward it, signal #reached and then hold on a gate that nobody opens. A process held there has written a complete request (#flush) or only its first byte (#nextPut:), and has not yet returned from writing it.
"
Class {
	#name : 'P3GatedStream',
	#superclass : 'Object',
	#instVars : [
		'stream',
		'reached',
		'gate',
		'armed',
		'gatedSelector'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'instance creation' }
P3GatedStream class >> on: aStream reached: aSemaphore gatedAt: aSelector [
	^ self new setStream: aStream reached: aSemaphore gatedAt: aSelector
]

{ #category : 'forwarding' }
P3GatedStream >> doesNotUnderstand: aMessage [
	^ aMessage sendTo: stream
]

{ #category : 'writing' }
P3GatedStream >> flush [
	stream flush.
	self holdAfter: #flush
]

{ #category : 'private' }
P3GatedStream >> holdAfter: aSelector [
	(armed and: [ aSelector = gatedSelector ]) ifFalse: [ ^ self ].
	armed := false.
	reached signal.
	gate wait
]

{ #category : 'writing' }
P3GatedStream >> nextPut: anObject [
	stream nextPut: anObject.
	self holdAfter: #nextPut:.
	^ anObject
]

{ #category : 'initialization' }
P3GatedStream >> setStream: aStream reached: aSemaphore gatedAt: aSelector [
	stream := aStream.
	reached := aSemaphore.
	gatedSelector := aSelector.
	gate := Semaphore new.
	armed := true
]
