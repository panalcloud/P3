"
I measure the time and the memory P3Client needs for typical work: small queries, reading rows of each common type, a wide row, a large value, building parameters, and batch inserts.

Most benchmarks measure the client alone. The response to a request is recorded once from the server (P3BenchmarkRecordingStream); then the request runs many times against that recording (P3BenchmarkReplayStream), with no network and no server. The time and the bytes allocated are what the client costs. Benchmarks whose name says ""round trip"" or ""batch"" run over the real connection instead.

Each method whose selector starts with ""bench"" is one benchmark. Results are P3BenchmarkResult objects, per query, row, value or message.

	P3Benchmark url: 'psql://user:password@localhost:5432/database'.
	P3Benchmark run report.

	(P3Benchmark new runOnly: #(#benchDecodeText #benchDecodeWideRow)) report.

The session uses a named time zone that is not UTC, so reading a timestamp without a time zone includes the shift to that zone. Compare results of the same machine and image only.
"
Class {
	#name : 'P3Benchmark',
	#superclass : 'Object',
	#instVars : [
		'client',
		'results'
	],
	#classVars : [
		'Url'
	],
	#category : 'P3-Benchmarks',
	#package : 'P3-Benchmarks'
}

{ #category : 'running' }
P3Benchmark class >> run [
	"Run all benchmarks and answer the instance that holds the results"

	^ self new run
]

{ #category : 'accessing' }
P3Benchmark class >> url [
	"The connection string of the server to measure against, see #url:"

	^ Url
]

{ #category : 'accessing' }
P3Benchmark class >> url: stringOrUrl [
	"P3Benchmark url: 'psql://user:password@localhost:5432/database'"

	Url := stringOrUrl
]

{ #category : 'measuring' }
P3Benchmark >> add: name unit: unit count: count measurement: measurement [
	^ results add: (P3BenchmarkResult
		name: name
		unit: unit
		count: count
		microseconds: measurement first
		bytes: measurement second)
]

{ #category : 'benchmarks' }
P3Benchmark >> benchBindFormatted [
	"Building the SQL text of a formatted statement for one row of parameters"

	| statement row |
	statement := client format: 'INSERT INTO t VALUES ($1, $2, $3, $4, $5)'.
	row := self sampleRow.
	self local: 'bind formatted' unit: 'row' times: 20000 do: [ statement bind: row ]
]

{ #category : 'benchmarks' }
P3Benchmark >> benchBindPrepared [
	"Building the Bind message of a prepared statement for one row of parameters"

	| statement row |
	statement := client prepare: 'SELECT $1::int4, $2::text, $3::numeric(14,2), $4::timestamptz, $5::bool'.
	row := self sampleRow.
	[ self local: 'bind prepared' unit: 'row' times: 20000 do: [ statement bindMessageFor: row ] ]
		ensure: [ statement close ]
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeBigInteger [
	self decode: 'decode int8' expression: 'i::int8 * 1000000007'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeBoolean [
	self decode: 'decode bool' expression: 'i % 2 = 0'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeBytea [
	"16 bytes"

	self decode: 'decode bytea' expression: 'decode(md5(i::text), ''hex'')'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeDate [
	self decode: 'decode date' expression: 'date ''2020-01-01'' + i % 3000'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeFloat [
	self decode: 'decode float8' expression: '(i * 1.37)::float8'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeInteger [
	self decode: 'decode int4' expression: 'i::int4'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeIntegerArray [
	self decode: 'decode int4[5]' expression: 'ARRAY[i, i + 1, i + 2, i + 3, i + 4]'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeInterval [
	self decode: 'decode interval' expression: 'i * interval ''1 minute 3 seconds'''
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeJson [
	self decode: 'decode json' expression: 'json_build_object(''id'', i, ''name'', md5(i::text))'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeLargeText [
	"One ASCII text value of 1 MB"

	self
		replay: 'decode large text'
		unit: 'MB'
		count: 1
		times: 10
		request: [ client query: 'SELECT repeat(''abcdefghij'', 100000)' ]
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeNull [
	"The cost of a row itself: one column, always NULL"

	self decode: 'decode null' expression: 'NULL::int4'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeNumeric [
	self decode: 'decode numeric' expression: '(i * 1.37)::numeric(14,2)'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeText [
	"ASCII text of 32 characters"

	self decode: 'decode text' expression: 'md5(i::text)'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeTextNonAscii [
	"Short text with some characters outside ASCII, like names"

	self decode: 'decode text non-ascii' expression: '''José Núñez Martínez '' || i'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeTime [
	self decode: 'decode time' expression: 'time ''00:00'' + i * interval ''1.5 seconds'''
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeTimestamp [
	"A timestamp without a time zone, shifted to the session time zone"

	self decode: 'decode timestamp' expression: 'timestamp ''2020-01-01'' + i * interval ''37.5 seconds'''
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeTimestampWithTimeZone [
	self decode: 'decode timestamptz' expression: 'timestamptz ''2020-01-01'' + i * interval ''37.5 seconds'''
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeUuid [
	self decode: 'decode uuid' expression: 'md5(i::text)::uuid'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchDecodeWideRow [
	"Six columns of mixed types, as in a typical table"

	self
		decode: 'decode wide row'
		expression: 'i::int4 AS id, md5(i::text) AS name, (i * 1.37)::numeric(14,2) AS amount, timestamp ''2020-01-01'' + i * interval ''37 seconds'' AS created, i % 3 = 0 AS active, date ''2020-01-01'' + i % 900 AS day'
]

{ #category : 'benchmarks' }
P3Benchmark >> benchInsertBatch [
	"Inserting rows with a prepared statement, 1000 per batch, over the connection"

	| statement rows |
	client execute: 'CREATE TEMPORARY TABLE p3_benchmark_rows (id int4, name text, amount numeric(14,2), created timestamptz, active bool)'.
	[ statement := client prepare: 'INSERT INTO p3_benchmark_rows VALUES ($1, $2, $3, $4, $5)'.
	  rows := Array new: 1000 withAll: self sampleRow.
	  [ self overConnection: 'insert batch' unit: 'row' count: rows size times: 5 request: [ statement executeBatch: rows ] ]
		ensure: [ statement close ] ]
		ensure: [ client execute: 'DROP TABLE p3_benchmark_rows' ]
]

{ #category : 'benchmarks' }
P3Benchmark >> benchQuery [
	"A simple query with a one-row result, client only"

	self replay: 'query' unit: 'query' count: 1 times: 20000 request: [ client query: 'SELECT 1' ]
]

{ #category : 'benchmarks' }
P3Benchmark >> benchQueryPrepared [
	"A prepared statement with a one-row result, client only"

	| statement |
	statement := client prepare: 'SELECT 1'.
	[ self replay: 'query prepared' unit: 'query' count: 1 times: 20000 request: [ statement query: #() ] ]
		ensure: [ statement close ]
]

{ #category : 'benchmarks' }
P3Benchmark >> benchQueryRoundTrip [
	"A simple query with a one-row result, over the connection"

	self overConnection: 'query round trip' unit: 'query' count: 1 times: 2000 request: [ client query: 'SELECT 1' ]
]

{ #category : 'accessing' }
P3Benchmark >> benchmarkSelectors [
	^ (self class selectors select: [ :each | each beginsWith: 'bench' ]) asSortedCollection asArray
]

{ #category : 'measuring' }
P3Benchmark >> decode: name expression: anSqlExpression [
	"Measure reading rows of one column, the value of anSqlExpression for i from 1 to #rowCount"

	| query |
	query := 'SELECT ' , anSqlExpression , ' FROM generate_series(1, ' , self rowCount printString , ') i'.
	^ self replay: name unit: 'row' count: self rowCount times: 10 request: [ client query: query ]
]

{ #category : 'initialization' }
P3Benchmark >> initialize [
	super initialize.
	results := OrderedCollection new
]

{ #category : 'measuring' }
P3Benchmark >> local: name unit: unit times: count do: aBlock [
	"Measure work of the client that needs no response, like building a message"

	^ self add: name unit: unit count: count measurement: (self measure: aBlock times: count)
]

{ #category : 'measuring' }
P3Benchmark >> measure: aBlock times: count [
	"Answer the microseconds and the bytes allocated for count evaluations of aBlock, after a warm-up
	and a garbage collection. VM parameter 34 is the number of bytes allocated since startup."

	| start allocated |
	3 timesRepeat: aBlock.
	Smalltalk garbageCollect.
	allocated := Smalltalk vm parameterAt: 34.
	start := Time microsecondClockValue.
	count timesRepeat: aBlock.
	^ Array
		with: Time microsecondClockValue - start
		with: (Smalltalk vm parameterAt: 34) - allocated
]

{ #category : 'measuring' }
P3Benchmark >> overConnection: name unit: unit count: unitsPerRequest times: count request: aBlock [
	"Measure the request of aBlock with the network and the server included"

	^ self add: name unit: unit count: unitsPerRequest * count measurement: (self measure: aBlock times: count)
]

{ #category : 'measuring' }
P3Benchmark >> record: aBlock [
	"Evaluate aBlock once over the real connection and answer the bytes of the response it read"

	| recorder |
	recorder := P3BenchmarkRecordingStream on: client connection.
	self useStream: recorder during: aBlock.
	^ recorder bytes
]

{ #category : 'measuring' }
P3Benchmark >> replay: name unit: unit count: unitsPerRequest times: count request: aBlock [
	"Measure the client alone: record the response to the request of aBlock once, then evaluate aBlock
	count times against the recording"

	| bytes measurement |
	bytes := self record: aBlock.
	measurement := self
		useStream: (P3BenchmarkReplayStream bytes: bytes)
		during: [ self measure: aBlock times: count ].
	^ self add: name unit: unit count: unitsPerRequest * count measurement: measurement
]

{ #category : 'printing' }
P3Benchmark >> report [
	"One line per result"

	^ String streamContents: [ :stream |
		results
			do: [ :each | stream print: each ]
			separatedBy: [ stream cr ] ]
]

{ #category : 'accessing' }
P3Benchmark >> results [
	"The P3BenchmarkResult of each benchmark that ran, in order"

	^ results
]

{ #category : 'accessing' }
P3Benchmark >> rowCount [
	"The number of rows of each result that is read"

	^ 10000
]

{ #category : 'running' }
P3Benchmark >> run [
	"Run all benchmarks"

	^ self runOnly: self benchmarkSelectors
]

{ #category : 'running' }
P3Benchmark >> runOnly: selectors [
	"Run the benchmarks named by selectors on one new connection"

	client := P3Client new url: self class url.
	[ client connect.
	  client execute: 'SET TIME ZONE ''Europe/Brussels'''.
	  selectors do: [ :each | self perform: each ] ]
		ensure: [ client close ]
]

{ #category : 'accessing' }
P3Benchmark >> sampleRow [
	"Parameters of the types an application binds most"

	^ Array
		with: 42
		with: 'Núñez 42'
		with: 1234.56s2
		with: (DateAndTime year: 2024 month: 1 day: 1 hour: 12 minute: 0 second: 0)
		with: true
]

{ #category : 'measuring' }
P3Benchmark >> useStream: aStream during: aBlock [
	"P3Client has no setter for its socket stream, so swap the instance variable for the duration of aBlock"

	| socket |
	socket := client connection.
	client instVarNamed: #connection put: aStream.
	^ aBlock ensure: [ client instVarNamed: #connection put: socket ]
]
