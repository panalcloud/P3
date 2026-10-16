"
I stand in for the socket stream of a P3Client and answer one scripted response, with no server. My bytes become readable when the first request is flushed, and each later flush starts them again. What the client writes is dropped.

	P3ScriptedStream bytes: (P3ScriptedStream message: $Z payload: 'I' asByteArray)

#message:payload: builds one backend message: its tag, its length and its payload.
"
Class {
	#name : 'P3ScriptedStream',
	#superclass : 'Object',
	#instVars : [
		'input'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'instance creation' }
P3ScriptedStream class >> bytes: aByteArray [
	^ self new setBytes: aByteArray
]

{ #category : 'building' }
P3ScriptedStream class >> message: aCharacter payload: aByteArray [
	"One backend message: tag byte, Int32 length that counts itself, payload."

	^ ByteArray streamContents: [ :out |
		out nextPut: aCharacter asInteger.
		out nextPutAll: ((aByteArray size + 4) asByteArrayOfSize: 4).
		out nextPutAll: aByteArray ]
]

{ #category : 'initialization' }
P3ScriptedStream >> close [
	"There is no socket to close."
]

{ #category : 'writing' }
P3ScriptedStream >> flush [
	input reset
]

{ #category : 'testing' }
P3ScriptedStream >> isConnected [
	^ true
]

{ #category : 'testing' }
P3ScriptedStream >> isDataAvailable [
	^ input atEnd not
]

{ #category : 'reading' }
P3ScriptedStream >> next [
	^ input next
]

{ #category : 'reading' }
P3ScriptedStream >> next: count into: buffer [
	^ input next: count into: buffer
]

{ #category : 'writing' }
P3ScriptedStream >> next: count putAll: aCollection startingAt: start [
	^ aCollection
]

{ #category : 'writing' }
P3ScriptedStream >> nextPut: byte [
	^ byte
]

{ #category : 'writing' }
P3ScriptedStream >> nextPutAll: aCollection [
	^ aCollection
]

{ #category : 'initialization' }
P3ScriptedStream >> setBytes: aByteArray [
	"Start at the end: nothing is available until the first request is flushed."

	input := ReadStream on: aByteArray.
	input setToEnd
]

{ #category : 'accessing' }
P3ScriptedStream >> timeout: seconds [
	"There is nothing to wait for."
]
