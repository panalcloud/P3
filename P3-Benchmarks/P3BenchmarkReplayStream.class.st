"
I stand in for the socket stream of a P3Client and answer the same recorded response to every request. Each request ends with one #flush, so a flush moves me back to the first byte of the response. What the client writes is counted and dropped.

With me in place of the socket, a request runs all of the client's code with no network and no server, which measures the client alone. See P3Benchmark.

	P3BenchmarkReplayStream bytes: recordedResponse
"
Class {
	#name : 'P3BenchmarkReplayStream',
	#superclass : 'Object',
	#instVars : [
		'bytes',
		'input',
		'written'
	],
	#category : 'P3-Benchmarks',
	#package : 'P3-Benchmarks'
}

{ #category : 'instance creation' }
P3BenchmarkReplayStream class >> bytes: aByteArray [
	^ self new setBytes: aByteArray
]

{ #category : 'initialization' }
P3BenchmarkReplayStream >> close [
	"There is no socket to close"
]

{ #category : 'writing' }
P3BenchmarkReplayStream >> flush [
	"A request is complete, its response starts again at the first byte"

	input reset
]

{ #category : 'testing' }
P3BenchmarkReplayStream >> isConnected [
	^ true
]

{ #category : 'testing' }
P3BenchmarkReplayStream >> isDataAvailable [
	"Bytes are left only while a response is being read"

	^ input atEnd not
]

{ #category : 'reading' }
P3BenchmarkReplayStream >> next [
	^ input next
]

{ #category : 'reading' }
P3BenchmarkReplayStream >> next: count into: buffer [
	^ input next: count into: buffer
]

{ #category : 'writing' }
P3BenchmarkReplayStream >> next: count putAll: aCollection startingAt: start [
	written := written + count.
	^ aCollection
]

{ #category : 'writing' }
P3BenchmarkReplayStream >> nextPut: byte [
	written := written + 1.
	^ byte
]

{ #category : 'writing' }
P3BenchmarkReplayStream >> nextPutAll: aCollection [
	written := written + aCollection size.
	^ aCollection
]

{ #category : 'initialization' }
P3BenchmarkReplayStream >> setBytes: aByteArray [
	"Start at the end: nothing is available until the first request is flushed"

	bytes := aByteArray.
	input := ReadStream on: bytes.
	input setToEnd.
	written := 0
]

{ #category : 'accessing' }
P3BenchmarkReplayStream >> timeout: seconds [
	"There is nothing to wait for"
]

{ #category : 'accessing' }
P3BenchmarkReplayStream >> written [
	"The number of bytes written to me"

	^ written
]
