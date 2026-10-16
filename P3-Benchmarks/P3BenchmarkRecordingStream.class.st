"
I wrap the socket stream of a P3Client and keep a copy of every byte read through me. P3Benchmark uses me to record the response to one request, which P3BenchmarkReplayStream then answers again without a server.

All messages I do not implement go to the wrapped stream.
"
Class {
	#name : 'P3BenchmarkRecordingStream',
	#superclass : 'ProtoObject',
	#instVars : [
		'stream',
		'log'
	],
	#category : 'P3-Benchmarks',
	#package : 'P3-Benchmarks'
}

{ #category : 'instance creation' }
P3BenchmarkRecordingStream class >> on: aStream [
	^ self basicNew setStream: aStream
]

{ #category : 'accessing' }
P3BenchmarkRecordingStream >> bytes [
	"The bytes read through me so far"

	^ log contents
]

{ #category : 'reflective operations' }
P3BenchmarkRecordingStream >> doesNotUnderstand: aMessage [
	^ aMessage sendTo: stream
]

{ #category : 'reading' }
P3BenchmarkRecordingStream >> next [
	| byte |
	byte := stream next.
	byte ifNotNil: [ log nextPut: byte ].
	^ byte
]

{ #category : 'reading' }
P3BenchmarkRecordingStream >> next: count into: buffer [
	| answer |
	answer := stream next: count into: buffer.
	log next: count putAll: buffer startingAt: 1.
	^ answer
]

{ #category : 'initialization' }
P3BenchmarkRecordingStream >> setStream: aStream [
	stream := aStream.
	log := WriteStream on: (ByteArray new: 1024)
]
