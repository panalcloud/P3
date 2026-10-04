"
I am P3Error.

I get signalled when something goes wrong in using P3Client, either an error inside the driver itself, or an error signalled by the PostgreSQL database backend server.

I should always have a unique code and a message.
Use #isLocal to distinguish between an error inside the driver itself, or an error signalled by the PostgreSQL database backend server.

Reference https://www.postgresql.org/docs/9.6/errcodes-appendix.html
"
Class {
	#name : 'P3Error',
	#superclass : 'Error',
	#instVars : [
		'info'
	],
	#category : 'P3-Core',
	#package : 'P3',
	#tag : 'Core'
}

{ #category : 'accessing' }
P3Error class >> bindCompleteExpected [
	^ self new 
		info: { $C->'P3004'. $M->'BindComplete message expected' } asDictionary; 
		yourself
]

{ #category : 'instance creation' }
P3Error class >> cannotBindObject: anObject [
	"A prepared statement has no parameter text for anObject. Its print string is neither SQL nor data, so it is refused instead of stored."

	^ self new
		info: { $C->'P3035'. $M->('Cannot bind an object of class {1} as a parameter' format: { anObject class name }) } asDictionary;
		yourself
]

{ #category : 'accessing' }
P3Error class >> cannotConvertTypeOid: typeOid [
	^ self new 
		info: { $C->'P3030'. $M->('Cannot convert type with OID {1}' format: { typeOid }) } asDictionary; 
		yourself
]

{ #category : 'instance creation' }
P3Error class >> cannotFormatObject: anObject [
	"A formatted statement has no SQL text for anObject."

	^ self new
		info: { $C->'P3031'. $M->('Cannot format an object of class {1} as SQL' format: { anObject class name }) } asDictionary;
		yourself
]

{ #category : 'instance creation' }
P3Error class >> cannotReadInfinity: aText [
	"A date or timestamp can be infinity or -infinity. Date and DateAndTime have no infinite value, and any date I answered for it would be wrong and compare as a real one."

	^ self new
		info: { $C->'P3038'. $M->('Cannot read "{1}" as a date or timestamp, it is not a finite point in time. Select it cast to text to read it' format: { aText }) } asDictionary;
		yourself
]

{ #category : 'accessing' }
P3Error class >> cannotRepresentNumeric: numericText [
	"A numeric can be NaN, Infinity or -Infinity. A ScaledDecimal is a fraction and has none of them."

	^ self new
		info: { $C->'P3034'. $M->('Cannot read numeric "{1}" as a ScaledDecimal, it is not a finite number' format: { numericText }) } asDictionary;
		yourself
]

{ #category : 'accessing' }
P3Error class >> closeCompleteExpected [
	^ self new 
		info: { $C->'P3005'. $M->'CloseComplete message expected' } asDictionary; 
		yourself
]

{ #category : 'instance creation' }
P3Error class >> commitReportedAs: resultTag [
	"COMMIT on a transaction already in the failed ($E) state does not commit: PostgreSQL
	quietly runs a ROLLBACK instead and reports that as the command tag, with no error of its
	own. P3DatabaseDriver>>commitTransaction checks the tag it gets back so a caller that
	swallowed an earlier error is not told its unit of work was saved when it was not."

	^ self new
		info: { $C->'P3051'. $M->('COMMIT was not honored, the server reports {1}' format: { resultTag }) } asDictionary;
		yourself
]

{ #category : 'instance creation' }
P3Error class >> connectionLost [
	"See P3Client>>#autoReconnect: the connection went away and I am not to replace it by myself."

	^ self new
		info: { $C->'P3052'. $M->'Connection was lost and autoReconnect is off, reconnect explicitly to continue' } asDictionary;
		yourself
]

{ #category : 'instance creation' }
P3Error class >> connectionLostInTransaction [
	"See P3Client>>#closeAfterFailure: reconnecting would continue in autocommit what the caller
	still believes is one transaction."

	^ self new
		info: { $C->'P3050'. $M->'Connection was lost inside a transaction, reconnect explicitly to continue' } asDictionary;
		yourself
]

{ #category : 'instance creation' }
P3Error class >> copyNotSupported [
	"COPY streams its data in messages of its own, which I neither produce nor read."

	^ self new
		info: { $C->'P3007'. $M->'COPY to or from STDIN/STDOUT is not supported' } asDictionary;
		yourself
]

{ #category : 'accessing' }
P3Error class >> noDataExpected [
	^ self new 
		info: { $C->'P3001'. $M->'NoData message expected' } asDictionary; 
		yourself
]

{ #category : 'accessing' }
P3Error class >> parseCompleteExpected [
	^ self new 
		info: { $C->'P3002'. $M->'ParseComplete message expected' } asDictionary; 
		yourself
]

{ #category : 'accessing' }
P3Error class >> parsingFailed: detail [
	^ self new 
		info: { $C->'P3031'. $M->('Parsing failed "{1}"' format: { detail }) } asDictionary; 
		yourself
]

{ #category : 'accessing' }
P3Error class >> passwordRequired [
	^ self new 
		info: { $C->'P3010'. $M->'Password required' } asDictionary; 
		yourself
]

{ #category : 'accessing' }
P3Error class >> postgreSQLServerDidNotHonorSSLConnectionRequest [
	^ self new 
		info: { $C->'P3040'. $M->'PostgreSQL server did not honor SSL connection request' } asDictionary; 
		yourself
]

{ #category : 'accessing' }
P3Error class >> readyForQueryExpected [
	^ self new 
		info: { $C->'P3003'. $M->'ReadyForQuery message expected' } asDictionary; 
		yourself
]

{ #category : 'instance creation' }
P3Error class >> statementClosed: statementName [
	"A closed prepared statement has no connection and can no longer run."

	^ self new
		info: { $C->'P3036'. $M->('Prepared statement "{1}" is closed' format: { statementName }) } asDictionary;
		yourself
]

{ #category : 'instance creation' }
P3Error class >> unexpectedMessage: tag [
	"A message I cannot place in the response I am reading. Its arrival means the message stream is
	out of step, so the connection can no longer be positioned."

	^ self new
		info: { $C->'P3006'. $M->('Unexpected message {1} while reading a response' format: { tag asString }) } asDictionary;
		yourself
]

{ #category : 'accessing' }
P3Error class >> unexpectedMessageDuringAuthentication [
	^ self new 
		info: { $C->'P3020'. $M->'Unexpected message during authentication' } asDictionary; 
		yourself
]

{ #category : 'accessing' }
P3Error class >> unexpectedMessageDuringStartup [
	^ self new 
		info: { $C->'P3021'. $M->'Unexpected message during startup' } asDictionary; 
		yourself
]

{ #category : 'accessing' }
P3Error class >> unsupportedAuthenticationType: type [
	^ self new 
		info: { $C->'P3022'. $M->('Unsupported authentication type {1}' format: { type }) } asDictionary; 
		yourself
]

{ #category : 'instance creation' }
P3Error class >> unsupportedDateStyle: dateStyle [
	"I read dates, times and timestamps as ISO 8601, which only DateStyle ISO produces."

	^ self new
		info: { $C->'P3032'. $M->('Cannot read dates under DateStyle "{1}", ISO is required' format: { dateStyle }) } asDictionary;
		yourself
]

{ #category : 'instance creation' }
P3Error class >> unsupportedIntervalStyle: intervalStyle [
	"P3Interval reads the 'postgres' output format only."

	^ self new
		info: { $C->'P3033'. $M->('Cannot read intervals under IntervalStyle "{1}", postgres is required' format: { intervalStyle }) } asDictionary;
		yourself
]

{ #category : 'instance creation' }
P3Error class >> unsupportedSslMode: aMode [
	"A url asks for a sslmode that P3 cannot honour. Connecting anyway would drop the TLS the url asks for."

	^ self new
		info: { $C->'P3037'. $M->('Cannot honour sslmode "{1}", only "disable" and "require" are supported. The server certificate is not verified, and connecting without TLS as a fallback is not implemented' format: { aMode }) } asDictionary;
		yourself
]

{ #category : 'accessing' }
P3Error >> code [
	"Return my unique, locale independent, 5 character string code.
	The first 2 characters are called the class.
	The special P3 class groups errors that were generated locally,
	as opposed to error generated by the PostgreSQL server"
	
	^ self info at: $C ifAbsent: [ nil ]
]

{ #category : 'accessing' }
P3Error >> description [
	"Return a textual description of the exception."

	^ String streamContents: [ :stream |
		stream << self class name.
		self isLocal 
			ifFalse: [ stream space; << 'PostgreSQL' ].
		self messageText isEmptyOrNil
			ifFalse: [ stream space; << self messageText ] ]
]

{ #category : 'accessing' }
P3Error >> info [
	"An info dictionary contains the fields as described in 
	https://www.postgresql.org/docs/9.6/protocol-error-fields.html"

	^ info ifNil: [ info := Dictionary new ]
]

{ #category : 'accessing' }
P3Error >> info: anObject [
	info := anObject
]

{ #category : 'testing' }
P3Error >> isLocal [
	"Return true when I represent an error inside P3 itself,
	as opposed to an error generated by the PostgreSQL server"
	
	^ self code 
		ifNil: [ true "if there is no code, we might have been initialized directly" ] 
		ifNotNil: [ :code | code beginsWith: 'P3' ]
]

{ #category : 'accessing' }
P3Error >> message [
	"Return my user oriented error message string.
	This could be locale dependent.
	My messageText gets initialized from this string"

	^ self info at: $M ifAbsent: [ '' ]
]

{ #category : 'accessing' }
P3Error >> messageText [
	^ messageText ifNil: [ messageText := self message ]
]
