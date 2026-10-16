"
I am the outcome of one benchmark of P3Benchmark: the total time in microseconds and the bytes allocated for count units of work. A unit is a query, a row, a value or a message, see #unit.

I answer the time and allocation per unit, which is what is compared between two runs.
"
Class {
	#name : 'P3BenchmarkResult',
	#superclass : 'Object',
	#instVars : [
		'name',
		'unit',
		'count',
		'microseconds',
		'bytes'
	],
	#category : 'P3-Benchmarks',
	#package : 'P3-Benchmarks'
}

{ #category : 'instance creation' }
P3BenchmarkResult class >> name: aString unit: unitName count: anInteger microseconds: microseconds bytes: bytes [
	^ self new
		setName: aString unit: unitName count: anInteger microseconds: microseconds bytes: bytes;
		yourself
]

{ #category : 'accessing' }
P3BenchmarkResult >> bytes [
	"The bytes allocated in total"

	^ bytes
]

{ #category : 'accessing' }
P3BenchmarkResult >> bytesPerUnit [
	^ bytes // count
]

{ #category : 'accessing' }
P3BenchmarkResult >> count [
	^ count
]

{ #category : 'accessing' }
P3BenchmarkResult >> microseconds [
	^ microseconds
]

{ #category : 'accessing' }
P3BenchmarkResult >> microsecondsPerUnit [
	^ microseconds / count
]

{ #category : 'accessing' }
P3BenchmarkResult >> name [
	^ name
]

{ #category : 'printing' }
P3BenchmarkResult >> printOn: stream [
	"name: 1.234 us/row, 512 B/row"

	stream
		nextPutAll: name;
		nextPutAll: ': '.
	self microsecondsPerUnit asFloat printOn: stream showingDecimalPlaces: 3.
	stream
		nextPutAll: ' us/';
		nextPutAll: unit;
		nextPutAll: ', ';
		print: self bytesPerUnit;
		nextPutAll: ' B/';
		nextPutAll: unit
]

{ #category : 'initialization' }
P3BenchmarkResult >> setName: aString unit: unitName count: anInteger microseconds: totalMicroseconds bytes: totalBytes [
	name := aString.
	unit := unitName.
	count := anInteger.
	microseconds := totalMicroseconds.
	bytes := totalBytes
]

{ #category : 'accessing' }
P3BenchmarkResult >> unit [
	^ unit
]
