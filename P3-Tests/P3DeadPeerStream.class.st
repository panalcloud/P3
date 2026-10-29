"
I wrap a socket stream whose other end is gone but that still accepts writes, as a TCP socket does after the peer closed it. I answer false to #isConnected and forward everything else.
"
Class {
	#name : 'P3DeadPeerStream',
	#superclass : 'Object',
	#instVars : [
		'stream'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'instance creation' }
P3DeadPeerStream class >> on: aStream [
	^ self new setStream: aStream
]

{ #category : 'forwarding' }
P3DeadPeerStream >> doesNotUnderstand: aMessage [
	^ aMessage sendTo: stream
]

{ #category : 'testing' }
P3DeadPeerStream >> isConnected [
	^ false
]

{ #category : 'initialization' }
P3DeadPeerStream >> setStream: aStream [
	stream := aStream
]
