"
I answer the bytes I was given like a socket stream and signal ConnectionTimedOut when they run out, like a socket that stops sending.
"
Class {
	#name : 'P3StallingStream',
	#superclass : 'Object',
	#instVars : [
		'bytes'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'instance creation' }
P3StallingStream class >> on: aByteArray [
	^ self new setBytes: aByteArray
]

{ #category : 'reading' }
P3StallingStream >> next [
	^ bytes atEnd
		ifTrue: [ ConnectionTimedOut signal ]
		ifFalse: [ bytes next ]
]

{ #category : 'reading' }
P3StallingStream >> next: count into: aBuffer [
	1 to: count do: [ :index | aBuffer at: index put: self next ].
	^ aBuffer
]

{ #category : 'initialization' }
P3StallingStream >> setBytes: aByteArray [
	bytes := aByteArray readStream
]
