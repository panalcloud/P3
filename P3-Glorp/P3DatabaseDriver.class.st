"
I am P3DatabaseDriver, a Glorp Database Driver using the P3Client for PostgreSQL.

Installation

  PharoDatabaseAccessor DefaultDriver: P3DatabaseDriver.

Configure your session using a Glorp Login object

  Login new
    database: PostgreSQLPlatform new;
    username: 'username';
    password: 'password';
    connectString: 'host:5432_databasename';
    encodingStrategy: #utf8;
    yourself.

Binding

I support binding (#supportsBinding). A statement with ? placeholders runs as a P3PreparedStatement with the values of #basicExecuteSQLString:binding:. #basicExecuteSQLString:bindingRows: runs it once per row of values, many rows in one network round trip, and answers the row count of each row.

I keep the #preparedStatementLimit most recently used prepared statements, by their SQL with ? placeholders, and close the least recently used one past the limit. #batchSize is the maximum number of rows in one request.

A String bound to a bytea parameter is sent as its bytes, since Glorp gives bytea values as a String of bytes.
"
Class {
	#name : 'P3DatabaseDriver',
	#superclass : 'DatabaseDriver',
	#instVars : [
		'rowCount',
		'preparedStatements',
		'preparedStatementLimit',
		'batchSize'
	],
	#category : 'P3-Glorp',
	#package : 'P3-Glorp'
}

{ #category : 'private' }
P3DatabaseDriver class >> postgresPlaceholdersIn: aString [
	"Answer aString with each ? placeholder replaced by $1, $2, ... in order.
	A ? inside a string literal or a double quoted identifier is kept. A quote inside them is written twice."

	| index quote |
	index := 0.
	quote := nil.
	^ String new: aString size + 16 streamContents: [ :out |
		aString do: [ :each |
			quote
				ifNil: [
					(each = $' or: [ each = $" ]) ifTrue: [ quote := each ].
					each = $?
						ifTrue: [ out nextPut: $$; print: (index := index + 1) ]
						ifFalse: [ out nextPut: each ] ]
				ifNotNil: [
					each = quote ifTrue: [ quote := nil ].
					out nextPut: each ] ] ]
]

{ #category : 'executing' }
P3DatabaseDriver >> basicExecuteSQLString: aString [
	| result |
	result := connection query: aString.
	rowCount := result totalRowCount.
	^ (result hasData ifTrue: [ result data ] ifFalse: [ #() ]) readStream
]

{ #category : 'executing' }
P3DatabaseDriver >> basicExecuteSQLString: aString binding: aCollection [
	"Run aString, with a ? for each value of aCollection, as a prepared statement.
	Without values it runs as a simple query, like #basicExecuteSQLString:."

	| statement result |
	aCollection isEmpty ifTrue: [ ^ self basicExecuteSQLString: aString ].
	statement := self preparedStatementFor: aString.
	result := statement query: (self values: aCollection for: statement).
	rowCount := result totalRowCount.
	^ (result hasData ifTrue: [ result data ] ifFalse: [ #() ]) readStream
]

{ #category : 'executing' }
P3DatabaseDriver >> basicExecuteSQLString: aString bindingRows: aCollectionOfRows [
	"Run the prepared statement for aString once for each row of values, in requests of at most
	#batchSize rows: each request is one network round trip. Answer the row count of each run, in
	order. rowCount is their sum. Rows are not expected to answer data."

	| statement counts rows |
	statement := self preparedStatementFor: aString.
	rows := aCollectionOfRows asArray collect: [ :each | self values: each for: statement ].
	counts := OrderedCollection new: rows size.
	1 to: rows size by: self batchSize do: [ :start |
		(statement queryAll: (rows copyFrom: start to: (start + self batchSize - 1 min: rows size)))
			do: [ :each | counts add: each totalRowCount ] ].
	rowCount := counts inject: 0 into: [ :sum :each | sum + each ].
	^ counts asArray
]

{ #category : 'accessing' }
P3DatabaseDriver >> batchSize [
	"The maximum number of rows sent in one request by #basicExecuteSQLString:bindingRows:."

	^ batchSize ifNil: [ 500 ]
]

{ #category : 'accessing' }
P3DatabaseDriver >> batchSize: anInteger [

	batchSize := anInteger
]

{ #category : 'transactions' }
P3DatabaseDriver >> beginTransaction [
	connection execute: 'BEGIN TRANSACTION'
]

{ #category : 'transactions' }
P3DatabaseDriver >> commitTransaction [
	"After an error inside the transaction the server answers COMMIT with the tag ROLLBACK and no error of its own."

	| result |
	result := connection execute: 'COMMIT TRANSACTION'.
	result = 'COMMIT' ifFalse: [ (P3Error commitReportedAs: result) signal ]
]

{ #category : 'accessing' }
P3DatabaseDriver >> connect: aLogin [
	connection := self connectionClass new.
	connection 
		host: aLogin host;
		port: aLogin port asInteger;
		database: aLogin databaseName;
		user: aLogin username;
		password: aLogin password.
	connection connect
]

{ #category : 'accessing' }
P3DatabaseDriver >> connectSSL: aLogin [
	connection := self connectionClass new.
	connection
		setSSL;
		host: aLogin host;
		port: aLogin port asInteger;
		database: aLogin databaseName;
		user: aLogin username;
		password: aLogin password.
	connection connectSSL
]

{ #category : 'accessing' }
P3DatabaseDriver >> connectionClass [
	^ P3Client
]

{ #category : 'testing' }
P3DatabaseDriver >> isConnected [
	^ connection notNil and: [ connection isConnected ]
]

{ #category : 'login' }
P3DatabaseDriver >> logout [
	"Closing the connection ends its server session, and the statements prepared in it."

	preparedStatements := nil.
	connection ifNotNil: [
		connection close.
		connection := nil ]
]

{ #category : 'accessing' }
P3DatabaseDriver >> preparedStatementCount [

	^ self preparedStatements size
]

{ #category : 'private' }
P3DatabaseDriver >> preparedStatementFor: aString [
	"Answer the prepared statement for aString, a statement with ? placeholders.
	The most recently used statements are kept, up to #preparedStatementLimit. The least recently
	used one is closed when a new one goes over the limit."

	| statement |
	statement := self preparedStatements removeKey: aString ifAbsent: [ nil ].
	statement ifNil: [ statement := connection prepare: (self class postgresPlaceholdersIn: aString) ].
	self preparedStatements at: aString put: statement.
	[ self preparedStatements size > self preparedStatementLimit ] whileTrue: [
		(self preparedStatements removeKey: self preparedStatements keys first) close ].
	^ statement
]

{ #category : 'accessing' }
P3DatabaseDriver >> preparedStatementLimit [
	"The number of prepared statements kept on the connection."

	^ preparedStatementLimit ifNil: [ 256 ]
]

{ #category : 'accessing' }
P3DatabaseDriver >> preparedStatementLimit: anInteger [

	preparedStatementLimit := anInteger
]

{ #category : 'accessing' }
P3DatabaseDriver >> preparedStatements [
	"Prepared statements by their source with ? placeholders, least recently used first."

	^ preparedStatements ifNil: [ preparedStatements := OrderedDictionary new ]
]

{ #category : 'transactions' }
P3DatabaseDriver >> rollbackTransaction [
	connection execute: 'ROLLBACK TRANSACTION'
]

{ #category : 'accessing' }
P3DatabaseDriver >> rowCount [
	^ rowCount
]

{ #category : 'testing' }
P3DatabaseDriver >> supportsBinding [
	"Statements with ? placeholders run as prepared statements, see #basicExecuteSQLString:binding:."

	^ true
]

{ #category : 'testing' }
P3DatabaseDriver >> supportsBindingRows [
	"Many rows of values run in one request, see #basicExecuteSQLString:bindingRows:."

	^ true
]

{ #category : 'private' }
P3DatabaseDriver >> values: aCollection for: aPreparedStatement [
	"Answer the values to bind to aPreparedStatement. Glorp gives the value of a bytea column as a
	String of bytes. It is sent as a ByteArray, since text can not hold every byte, the 0 byte included."

	| values |
	values := aCollection asArray.
	aPreparedStatement paramDescriptions doWithIndex: [ :each :index |
		(each typeOid = 17 and: [ (values at: index) isString ]) ifTrue: [
			values == aCollection ifTrue: [ values := values copy ].
			values at: index put: (values at: index) asByteArray ] ].
	^ values
]
