"
Tests for the low severity fixes of the P3 correctness review: empty results, empty prepared queries and signed description fields. Each test runs against the live server through the client of P3StatementTestCase.
"
Class {
	#name : 'P3LowSeverityTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'tests' }
P3LowSeverityTest >> boundValuesDuring: aBlock [
	"Answer the input values of every P3StatementBoundEvent emitted while aBlock runs."

	| bound |
	bound := OrderedCollection new.
	P3LogEvent announcer
		when: P3StatementBoundEvent
		do: [ :event | bound add: event inputValues ]
		for: self.
	[ aBlock value ] ensure: [ P3LogEvent announcer unsubscribe: self ].
	^ bound asArray
]

{ #category : 'tests' }
P3LowSeverityTest >> testApplicationNameDefaultsToThePharoVersionAndCanBeChanged [
	| name other |
	name := (client query: 'SELECT current_setting(''application_name'')') firstFieldOfFirstRecord.
	self assert: name equals: P3Client defaultApplicationName.
	self assert: (name beginsWith: 'Pharo ').
	other := P3Client new url: client url.
	other applicationName: 'payroll'.
	[ self assert: (other query: 'SELECT current_setting(''application_name'')') firstFieldOfFirstRecord equals: 'payroll' ]
		ensure: [ other close ].
	other := P3Client new url: client url.
	other applicationName: nil.
	[ self assert: (other query: 'SELECT current_setting(''application_name'')') firstFieldOfFirstRecord equals: '' ]
		ensure: [ other close ]
]

{ #category : 'tests' }
P3LowSeverityTest >> testBatchRunsAsOneImplicitTransaction [
	| insert |
	client execute: 'CREATE TEMP TABLE p3l_batch(i int PRIMARY KEY)'.
	insert := client prepare: 'INSERT INTO p3l_batch VALUES ($1)'.
	self should: [ insert executeBatch: { { 1 }. { 2 }. { 2 } } ] raise: P3Error.
	self assert: (client query: 'SELECT count(*) FROM p3l_batch') firstFieldOfFirstRecord equals: 0.
	self should: [ (client prepare: 'VACUUM') executeBatch: { #(). #() } ] raise: P3Error.
	self assert: (client query: 'SELECT 5') firstFieldOfFirstRecord equals: 5
]

{ #category : 'tests' }
P3LowSeverityTest >> testBoundEventIsEmittedOncePerRowOfTheSentRequest [
	| statement rows bound |
	statement := client prepare: 'SELECT $1::int + 1'.
	rows := { { 1 }. { 2 }. { 3 } }.
	bound := self boundValuesDuring: [ statement executeBatch: rows ].
	self assert: bound equals: rows.
	bound := self boundValuesDuring: [ statement query: #( 7 ) ].
	self assert: bound equals: { #( 7 ) }
]

{ #category : 'tests' }
P3LowSeverityTest >> testByteaReadsTheEscapeFormat [
	| sql |
	sql := 'SELECT ''\x00ff415c7e5c5c''::bytea, ''\x''::bytea, ''\x5c78''::bytea'.
	client execute: 'SET bytea_output = escape'.
	self assert: (client query: sql) firstRecord equals: { #[0 255 65 92 126 92 92]. #[]. #[92 120] }.
	client execute: 'SET bytea_output = hex'.
	self assert: (client query: sql) firstRecord equals: { #[0 255 65 92 126 92 92]. #[]. #[92 120] }
]

{ #category : 'tests' }
P3LowSeverityTest >> testCharTypeReadsEveryByteValue [
	| values |
	values := (client query: 'SELECT 0::"char", 65::"char", 92::"char", (-128)::"char", (-1)::"char"') firstRecord.
	self assert: values equals: { Character value: 0. $A. $\. Character value: 128. Character value: 255 }
]

{ #category : 'tests' }
P3LowSeverityTest >> testConnectionEventCarriesNoSecrets [
	| other events event |
	other := P3Client new url: 'psql://someone:s3cret@db.example:5432/payroll'.
	(other instVarNamed: 'properties')
		at: 'backend_secret_key' put: 424242;
		at: 'backend_process_id' put: 7.
	events := OrderedCollection new.
	P3LogEvent announcer
		when: P3ConnectionEstablishedEvent
		do: [ :each | events add: each ]
		for: self.
	[ other logConnected ] ensure: [ P3LogEvent announcer unsubscribe: self ].
	self assert: events size equals: 1.
	event := events first.
	self deny: (event settings includesKey: #password).
	self deny: (event properties includesKey: 'backend_secret_key').
	self assert: event user equals: 'someone'.
	self assert: event host equals: 'db.example'.
	self assert: (event properties at: 'backend_process_id') equals: 7.
	self deny: (event printString includesSubstring: 's3cret').
	self assert: other password equals: 's3cret'.
	self assert: ((other instVarNamed: 'properties') at: 'backend_secret_key') equals: 424242
]

{ #category : 'tests' }
P3LowSeverityTest >> testDescriptionFieldsAreSigned [
	| sql fields |
	sql := 'SELECT tableoid, version() FROM pg_class LIMIT 1'.
	fields := (client prepare: sql) fieldDescriptions.
	self assert: fields first attributeNumber equals: -6.
	self assert: fields first typeSize equals: 4.
	self assert: fields second typeSize equals: -1.
	self assert: fields second attributeNumber equals: 0.
	fields := (client query: sql) descriptions.
	self assert: fields first attributeNumber equals: -6.
	self assert: fields second typeSize equals: -1
]

{ #category : 'tests' }
P3LowSeverityTest >> testEmptyPreparedQueryKeepsTheConnection [
	#( '' '-- only a comment' ) do: [ :sql | | result |
		result := (client prepare: sql) query: #().
		self deny: result hasData.
		self assert: result firstFieldOfFirstRecord isNil.
		self assert: client isConnected.
		self assert: (client query: 'SELECT 5') firstFieldOfFirstRecord equals: 5.
		self assert: (client query: 'SELECT 6') firstFieldOfFirstRecord equals: 6 ]
]

{ #category : 'tests' }
P3LowSeverityTest >> testEscapeFormatTextWithoutAServer [
	| converter |
	converter := P3Converter new.
	self assert: (converter byteArrayFromEscapeFormat: 'a\\b\000\377z' asByteArray) equals: #[97 92 98 0 255 122].
	self should: [ converter byteArrayFromEscapeFormat: '\9zz' asByteArray ] raise: P3Error.
	self should: [ converter octalValueOf: 'xyz' asByteArray ] raise: P3Error
]

{ #category : 'tests' }
P3LowSeverityTest >> testFirstFieldOfEmptyResultIsNil [
	self assert: (client query: 'SELECT 1 WHERE false') firstFieldOfFirstRecord isNil.
	self assert: (client query: 'SELECT 1 WHERE false') firstRecord isNil
]

{ #category : 'tests' }
P3LowSeverityTest >> testMessageBufferReleasesTheMemoryOfOneLargeMessage [
	| buffer small |
	buffer := P3MessageBuffer new.
	buffer initializeForSize: 100.
	small := buffer rawByteBuffer.
	buffer initializeForSize: 200.
	self assert: buffer rawByteBuffer == small.
	buffer initializeForSize: 3 * 1024 * 1024.
	self assert: buffer capacity >= (3 * 1024 * 1024).
	self assert: buffer size equals: 3 * 1024 * 1024.
	buffer initializeForSize: 50.
	self assert: buffer capacity < P3MessageBuffer retainedCapacity.
	self assert: buffer size equals: 50.
	buffer initializeForSize: 2 * 1024 * 1024.
	buffer initializeForSize: P3MessageBuffer retainedCapacity.
	self assert: buffer capacity < (2 * 1024 * 1024)
]

{ #category : 'tests' }
P3LowSeverityTest >> testNoBoundEventWhenTheRequestCannotBeBuilt [
	| statement bound |
	statement := client prepare: 'SELECT $1::int + 1'.
	bound := self boundValuesDuring: [
		self should: [ statement executeBatch: { { 1 }. { Object new } } ] raise: Error ].
	self assert: bound isEmpty.
	self assert: (client query: 'SELECT 5') firstFieldOfFirstRecord equals: 5
]

{ #category : 'tests' }
P3LowSeverityTest >> testResultSourceIsThatOfItsOwnStatementWhenProcessesShareAClient [
	| statements done wrong |
	statements := #( 1 2 ) collect: [ :each | client prepare: 'SELECT $1::int + ' , each printString ].
	done := statements collect: [ :each | Semaphore new ].
	wrong := OrderedCollection new.
	statements with: done do: [ :statement :semaphore |
		[ [ 40 timesRepeat: [ | result |
				result := statement query: #( 1 ).
				result source = statement source ifFalse: [ wrong add: result source ] ] ]
			ensure: [ semaphore signal ] ] fork ].
	done do: [ :semaphore | semaphore waitTimeoutMilliseconds: 60000 ].
	self assert: wrong isEmpty
]

{ #category : 'tests' }
P3LowSeverityTest >> testServerGettersWaitForARunningRequest [
	| order finished |
	order := OrderedCollection new.
	finished := Semaphore new.
	[ [ client query: 'SELECT pg_sleep(1)'. order add: #request ]
		ensure: [ finished signal ] ] fork.
	(Delay forMilliseconds: 300) wait.
	client serverEncoding.
	order add: #getter.
	finished waitTimeoutMilliseconds: 10000.
	self assert: order asArray equals: #( #request #getter )
]

{ #category : 'tests' }
P3LowSeverityTest >> testServerTimezoneAnswersTheNameOfAnUnknownZone [
	client execute: 'SET TIME ZONE ''<+03>-03'''.
	self assert: client serverTimezone equals: '<+03>-03'.
	client execute: 'SET TIME ZONE ''Europe/Amsterdam'''.
	self assert: client serverTimezone equals: 'Europe/Amsterdam'
]

{ #category : 'tests' }
P3LowSeverityTest >> testServerVersionComparisonReadsOddVersionStrings [
	| properties |
	properties := client instVarNamed: 'properties'.
	#( ('18beta1' 18 0 true) ('18beta1' 17 5 true) ('18beta1' 19 0 false) ('18' 18 0 true) ('18' 18 1 false)
		('beta' 1 0 false) ('16.3' 16 3 true) ('16.3' 16 4 false) ('17.2 (Debian)' 17 2 true) )
		do: [ :each |
			properties at: 'server_version' put: each first.
			self assert: (client isServerVersionAtLeastMajor: (each at: 2) minor: (each at: 3)) equals: (each at: 4) ]
]

{ #category : 'tests' }
P3LowSeverityTest >> testStartupPinsTheOutputFormats [
	| record |
	record := (client query: 'SELECT current_setting(''DateStyle''), current_setting(''IntervalStyle''), current_setting(''extra_float_digits''), current_setting(''client_encoding'')') firstRecord.
	self assert: (record first beginsWith: 'ISO').
	self assert: (record at: 2) equals: 'postgres'.
	self assert: (record at: 3) equals: '3'.
	self assert: (record at: 4) equals: 'UTF8'
]

{ #category : 'tests' }
P3LowSeverityTest >> testTimestampWithoutZoneReadsFailWhenTheSessionZoneIsUnknown [
	| timestamp |
	client execute: 'SET TIME ZONE ''<+03>-03'''.
	self should: [ client query: 'SELECT ''2020-01-31 10:00''::timestamp' ] raise: P3Error.
	self assert: (client query: 'SELECT ''2020-01-31 10:00''::timestamptz') hasData.
	client execute: 'SET TIME ZONE ''Europe/Amsterdam'''.
	timestamp := (client query: 'SELECT ''2020-01-31 10:00''::timestamp') firstFieldOfFirstRecord.
	self assert: timestamp hour equals: 10
]

{ #category : 'tests' }
P3LowSeverityTest >> testTotalRowCountWithCommandsWithoutCount [
	self assert: (client query: 'SELECT 1; CREATE TEMP TABLE p3l_x(i int)') totalRowCount equals: 1.
	self assert: (client query: 'CREATE TEMP TABLE p3l_y(i int)') totalRowCount equals: 0.
	self assert: (client query: 'BEGIN; INSERT INTO p3l_y VALUES (1), (2); COMMIT') totalRowCount equals: 2
]

{ #category : 'tests' }
P3LowSeverityTest >> testUnixSocketHostIsADirectoryOrTheSocketFile [
	| directory |
	directory := FileLocator temp resolve.
	client host: directory fullName; port: 5433.
	self assert: client isUsingUnixSocket.
	self assert: client unixSocketFile fullName equals: (directory / '.s.PGSQL.5433') fullName.
	client host: (directory / 'some-socket-file') fullName.
	self assert: client unixSocketFile fullName equals: (directory / 'some-socket-file') fullName
]

{ #category : 'tests' }
P3LowSeverityTest >> testUnknownServerTimezoneIsNotReplacedByTheImageZone [
	| converter error |
	converter := P3Converter new.
	converter serverTimezone: 'UTC+3'.
	error := [ converter sessionTimezone. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil.
	self assert: error code equals: 'P3039'.
	self assert: (error messageText includesSubstring: 'UTC+3').
	converter serverTimezone: 'Europe/Amsterdam'.
	self assert: converter sessionTimezone id equals: 'Europe/Amsterdam'
]
