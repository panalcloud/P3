"
I wrap a socket stream and forward everything to it. The first time a response is read, I wait a little and then signal ConnectionTimedOut, like a read timeout that expires just after the server finished the statement.
"
Class {
	#name : 'P3LateReadStream',
	#superclass : 'Object',
	#instVars : [
		'stream',
		'armed'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'instance creation' }
P3LateReadStream class >> on: aStream [
	^ self new setStream: aStream
]

{ #category : 'forwarding' }
P3LateReadStream >> doesNotUnderstand: aMessage [
	^ aMessage sendTo: stream
]

{ #category : 'reading' }
P3LateReadStream >> next [
	armed ifTrue: [
		armed := false.
		(Delay forMilliseconds: 300) wait.
		^ ConnectionTimedOut signal: 'simulated read timeout' ].
	^ stream next
]

{ #category : 'initialization' }
P3LateReadStream >> setStream: aStream [
	stream := aStream.
	armed := true
]
