"
I am P3Client, a lean and mean PostgreSQL client.

PostgreSQL, often simply Postgres, is a free and open-source, ACID-compliant and transactional object-relational database management system (ORDBMS).

I use frontend/backend protocol 3.0 (PostgreSQL version 7.4 [2003] and later), implementing the simple query cycle. I support plaintext and md5 password authentication. When SQL queries return row data, I efficiently convert incoming data to objects. I support most common PostgreSQL types (P3Converter supportedTypes).

I can be configured manually or through a URL.

  P3Client new url: 'psql://username:password@localhost:5432/databasename?sslmode=require'.

Not all properties need to be specified, the minimum is the following URL.

  P3Client new url: 'psql://user@localhost'.

I have a minimal public protocol, basically #query: (#execute: is an alias).

Opening a connection to the server (#open) and running the authentication and startup protocols (#connect) are done automatically when needed from #query.

I also support SSL connections. Use #connectSSL to initiate such a connection.

I represent a single database connection or session, I am not thread safe.


Examples 

Here is the simplest test that does an actual query, it should return true.

    (P3Client new url: 'psql://sven@localhost') in: [ :client |
        [ client isWorking ] ensure: [ client close ] ].

Here is how to create a simple table with some rows in it.

    (P3Client new url: 'psql://sven@localhost') in: [ :client |
        client execute: 'DROP TABLE IF EXISTS table1'.
        client execute: 'CREATE TABLE table1 (id INTEGER, name TEXT, enabled BOOLEAN)'.
        client execute: 'INSERT INTO table1 (id, name, enabled) VALUES (1, ''foo'', true)'.
        client execute: 'INSERT INTO table1 (id, name, enabled) VALUES (2, ''bar'', false)'.
        client close ].
	
Now we can query the contents of the simple table we just created.

    (P3Client new url: 'psql://sven@localhost') in: [ :client |
        [ client query: 'SELECT * FROM table1' ] ensure: [ client close ] ].

The result is an instance of P3Result

    a P3Result('SELECT 2' 2 records 3 columns)

P3Result contains 3 elements,  results, descriptions & data:
- Results is a string (collection of strings for multiple embedded queries) indicating successful execution.
- Descriptions is a collection of row field description objects.
- Data is a collection of rows with fully converted field values as objects.

The data itself is an array with 2 sub arrays, one for each record.

    #( #(1 'foo' true) #(2 'bar' false) )

Finally we can clean up.

    (P3Client new url: 'psql://sven@localhost') in: [ :client |
        [ client execute: 'DROP TABLE table1' ] ensure: [ client close ] ].


References 

-  https://postgresql.org
-  https://en.wikipedia.org/wiki/PostgreSQL
-  https://www.postgresql.org/docs/9.6/static/protocol.html


See also P3DatabaseDriver, an interface between Glorp, an advanced object-relational mapper, and me.

"
Class {
	#name : 'P3Client',
	#superclass : 'Object',
	#instVars : [
		'connection',
		'session',
		'settings',
		'properties',
		'converter',
		'message',
		'access',
		'transactionStatus',
		'notifications',
		'pendingResponses',
		'transactionLost',
		'discardedError',
		'extendedRequest',
		'connectionGeneration',
		'connectionLost'
	],
	#category : 'P3-Core',
	#package : 'P3',
	#tag : 'Core'
}

{ #category : 'accessing' }
P3Client class >> defaultApplicationName [
	"The name of this Pharo, major and minor version."

	^ 'Pharo {1}.{2}' format: { SystemVersion current major. SystemVersion current minor }
]

{ #category : 'instance creation' }
P3Client class >> url: anUrl [
	^ self new url: anUrl 
]

{ #category : 'private' }
P3Client >> abandonCopyIn [
	"The server sent CopyInResponse and waits for data that I do not send. Tell it to abandon the copy:
	it answers with an ErrorResponse, and the response then ends normally.

	How it ends depends on the request. A simple query ends with the ReadyForQuery that follows the
	error. An extended one does not: during copy-in the server ignores Flush and Sync, so the Sync that
	ended the request was dropped, and after the error it discards every message until a Sync that
	it has not got. Send that one now. It replaces the one that was dropped, so the number of
	responses owed does not change and it is not counted. A second Sync after a simple query would
	be answered with a ReadyForQuery that nobody reads."

	self
		writeMessage: (self newMessageBuilder
			nextPutString: 'COPY FROM STDIN is not supported by P3';
			yourself) asBytes
		tag: $f.
	extendedRequest ifTrue: [ self writeMessage: #[] tag: $S ]
]

{ #category : 'accessing' }
P3Client >> applicationName [
	"The application_name the server shows in pg_stat_activity and its logs. Defaults to the Pharo
	version, like Pharo 13.1. Nil sends none."

	^ settings at: #applicationName ifAbsent: [ self class defaultApplicationName ]
]

{ #category : 'accessing' }
P3Client >> applicationName: aStringOrNil [
	"Set the application_name sent with the startup, so it holds for connections opened after this call."

	settings at: #applicationName put: aStringOrNil
]

{ #category : 'private' }
P3Client >> applyUnknownTypesSetting [
	self converter unknownTypeConverter: (self isUnknownTypesAsTextEnabled
		ifTrue: [ #convertStringFrom:length:description: ])
]

{ #category : 'private' }
P3Client >> asCString: string [
	"The bytes of string in UTF-8, ended by a zero byte. The user, database, password and options are
	sent before the session has an encoding, and UTF-8 is the one that the startup packet asks for."

	^ string utf8Encoded , #[0]
]

{ #category : 'private' }
P3Client >> attemptRequest: writeBlock response: readBlock canRetry: aBoolean [
	"One try of #runRequest:response:, under the monitor. Answer #retry when the request did not reach the
	server and aBoolean allows another try, otherwise the result of readBlock."

	[ self ensureResponseRead.
	self ensureConnected.
	writeBlock value ]
		on: NetworkError
		do: [ :error |
			self closeAfterFailure.
			aBoolean ifFalse: [ error pass ].
			^ #retry ].
	^ self readResponse: readBlock
]

{ #category : 'private - authentication' }
P3Client >> authenticationTypes [
	^ { 
		0 -> #Ok. 
		2 -> #KerberosV5. 
		3 -> #CleartextPassword. 
		5 -> #MD5Password.
		6 -> #SCMCredential.
		7 -> #GSS.
		9 -> #SSPI.
		10 -> #SASL } asDictionary
]

{ #category : 'accessing' }
P3Client >> autoReconnect [
	"Do I open a new connection by myself when the one I had was lost? Default true.
	When false, the next request signals a P3Error and #connect is the explicit way back, as in libpq's PQreset."

	^ settings at: #autoReconnect ifAbsent: [ true ]
]

{ #category : 'accessing' }
P3Client >> autoReconnect: aBoolean [
	"See #autoReconnect"

	settings at: #autoReconnect put: aBoolean
]

{ #category : 'accessing' }
P3Client >> backendProcessId [
	"The process id of the server side of my connection, or nil when I am not connected."

	^ properties at: 'backend_process_id' ifAbsent: [ nil ]
]

{ #category : 'protocol' }
P3Client >> basicRunExtendedQueryResults: fieldDescriptions [
	"Read the response to a request of Bind and Execute messages ended by one Sync: one result per
	Execute, then one ReadyForQuery."

	| queryStarted |
	queryStarted := Time millisecondClockValue.
	self readMessage.
	^ Array streamContents: [ :out |
		[ "each result will use the same start"
		  properties at: #query_started ifAbsentPut: queryStarted.
		  out nextPut: (self runExtendedQueryResult: fieldDescriptions).
		  self readMessage tag = $Z ] whileFalse ]
]

{ #category : 'protocol' }
P3Client >> basicRunQueryResult [
	"Read the response to a Query message: one result per statement the query contained, ended by one
	ReadyForQuery. #readMessage consumes asynchronous messages, so I only see the tags below."

	| result |
	result := P3Result new.
	self readMessage.
	[ self readQueryResultInto: result.
	  self readMessage tag = $Z ] whileFalse.
	result source: (properties at: #sql_source ifAbsent: nil).
	self logResult: result.
	^ result
]

{ #category : 'initialize-release' }
P3Client >> beThreadSafe [
	"Configure me so that I can be safely used from multiple threads/processes during important operations"
	
	access := Monitor new
]

{ #category : 'cancelling' }
P3Client >> cancel [
	"Ask the server to stop the statement my connection is running. The request goes over a new connection,
	because mine is busy reading the answer, so I do not wait for my monitor and any process can call me.
	Answer whether a request was sent, which is not whether it had an effect: the server gives no answer,
	and ignores the request when the statement has finished by then. A statement that is stopped fails
	with a P3Error 57014 and leaves my connection usable. I signal when the server cannot be reached."

	| stream request |
	(properties includesKey: 'backend_secret_key') ifFalse: [ ^ false ].
	request := self cancelRequestMessage.
	stream := self newSocketStream.
	[ self isSSL ifTrue: [ stream := self secureStreamOn: stream ].
	stream nextPutAll: request; flush.
	"The server closes the connection once it has the request."
	[ stream next ] on: Error do: [ :ignored | ] ]
		ensure: [ [ stream close ] on: Error do: [ :ignored | ] ].
	^ true
]

{ #category : 'cancelling' }
P3Client >> cancelRequestMessage [
	"The CancelRequest for the statement my connection runs: its length, the code 1234 5678, and the
	process id and secret key the server gave me at startup."

	^ ByteArray streamContents: [ :out |
		out nextPutAll: #[ 0 0 0 16 4 210 22 46 ].
		out nextPutAll: ((properties at: 'backend_process_id') asByteArrayOfSize: 4).
		out nextPutAll: ((properties at: 'backend_secret_key') asByteArrayOfSize: 4) ]
]

{ #category : 'private' }
P3Client >> clearSSL [
	settings removeKey: #ssl ifAbsent: [ ]
]

{ #category : 'private' }
P3Client >> clearSession [
	session := nil.
	pendingResponses := 0.
	transactionStatus := nil.
	transactionLost := false.
	connectionLost := false.
	extendedRequest := false
]

{ #category : 'private messages' }
P3Client >> clearTextPasswordMessage [
	self password ifNil: [ P3Error passwordRequired signal ].
	^ self asCString: self password
]

{ #category : 'initialize-release' }
P3Client >> close [
	"Cleanly close my connection with the server"

	connection ifNotNil: [
		self logDisconnected. 
		[ 
			self writeMessage: #[] tag: $X.
			connection close ] on: Error do: [  ].
		
		self clearSession.
		connection := nil
		 ]
]

{ #category : 'private' }
P3Client >> closeAfterFailure [
	"Close because something went wrong, not because the caller asked.

	A connection lost while a transaction was open or failed cannot simply be replaced: the server
	rolled that transaction back, and the statements the caller still believes are inside it would run
	in autocommit on a new connection, with its COMMIT succeeding on part of the work. Remember that,
	so the next use says so instead of reconnecting silently. An explicit #close or #connect clears it.

	Outside a transaction the connection is replaced on the next use, see #ensureConnected. Remember
	that it was lost, to tell the application that the session state went with it."

	| lost |
	connection ifNil: [ ^ self ].
	lost := 'TE' includes: (transactionStatus ifNil: [ $I ]).
	self close.
	transactionLost := lost.
	connectionLost := true
]

{ #category : 'private' }
P3Client >> closeMessageFor: aName type: aChar [
	"The Close message for a prepared statement ($S) or a portal ($P), as a tag -> payload association.
	See #writeExtendedRequest:."

	^ $C -> (self newMessageBuilder
		nextPutByte: aChar asInteger;
		nextPutString: aName;
		yourself) asBytes
]

{ #category : 'accessing' }
P3Client >> compactUrl [
	^ self url
		scheme: #psql;
		password: nil;
		queryRemoveAll;
		yourself
]

{ #category : 'public' }
P3Client >> connect [
	"Connect me to a PostgreSQL database. 
	Run the authentication and startup protocols. Configure the session."

	self critical: [ 
		self
			ensureOpen;
			connectInternal;
			clearSSL;
			logConnected ]
]

{ #category : 'protocol' }
P3Client >> connectInternal [
	"Run the authentication and startup protocols. Configure the session."
	
	self 
		writeMessage: self startupMessage;
		reset;
		runAuthentication;
		runStartup;
		initializeConverter.
	connectionGeneration := connectionGeneration + 1
]

{ #category : 'public' }
P3Client >> connectSSL [
	"Connect me to a PostgreSQL database over an encrypted SSL connection. 
	Run the authentication and startup protocols. Configure the session."

	self critical: [
		self
			ensureOpen;
			upgradeToSSL;
			connectInternal;
			setSSL;
			logConnected ]
]

{ #category : 'accessing' }
P3Client >> connectTimeout [
	"Return the timeout in seconds for resolving the host name and reaching the server, the default being
	10 seconds. It is separate from #timeout, which bounds waiting for the server once connected."

	^ settings at: #connectTimeout ifAbsent: [ 10 ]
]

{ #category : 'accessing' }
P3Client >> connectTimeout: seconds [
	settings at: #connectTimeout put: seconds
]

{ #category : 'accessing' }
P3Client >> connection [
	"Return the network connection I am using.
	When I am not connected, return nil."
	
	^ connection
]

{ #category : 'accessing' }
P3Client >> connectionGeneration [
	"How many connections I have opened. A server session lives as long as one generation:
	what was prepared under an older one is gone."

	^ connectionGeneration
]

{ #category : 'accessing' }
P3Client >> converter [
	"Return the converter that I am using.
	It holds the character encoding and timezone of the current database connection."
	
	^ converter ifNil: [ converter := P3Converter new ]
]

{ #category : 'private' }
P3Client >> converter: anObject [
	converter := anObject
]

{ #category : 'private' }
P3Client >> createPreparedStatementNamed: name withParameters: parameterDescriptions andFields: rowDescriptions [
	| preparedStatement |
	preparedStatement := P3PreparedStatement 
		newWith: self 
		name: name 
		parameters: parameterDescriptions 
		fields: rowDescriptions.
	(properties at: 'prepared_statements' ifAbsentPut: [ Dictionary new ])
		at: name put: preparedStatement.
	^ preparedStatement
]

{ #category : 'private' }
P3Client >> critical: block [
	^ access
		ifNil: block
		ifNotNil: [ access critical: block ]
]

{ #category : 'accessing' }
P3Client >> database [
	"Return the database name I (want to) connect to.
	For the default, nil is used."
	
	^ settings at: #database ifAbsent: [ nil ]
]

{ #category : 'initialize-release' }
P3Client >> database: string [
	"Set the name of the database to connect to.
	Set to nil or do not set to use the default."
	
	settings at: #database put: string
]

{ #category : 'private' }
P3Client >> defaultStatementNameFor: query [
	"The server keeps at most 63 bytes of a statement name, in the connection encoding, and refuses a name
	that is in use. A query that fits is its own name. A longer one is cut to whole characters and ends in
	a digest of the entire query, so two queries that share their first 63 bytes still get different names."

	| encoder digest prefix |
	encoder := self converter encoder.
	(encoder encodeString: query) size <= 63
		ifTrue: [ ^ query ].
	digest := (MD5 hashMessage: (encoder encodeString: query)) hex.
	prefix := query.
	[ (encoder encodeString: prefix) size + 1 + digest size > 63 ]
		whileTrue: [ prefix := prefix allButLast ].
	^ prefix , '_' , digest
]

{ #category : 'private' }
P3Client >> describeMessageFor: aName type: aChar [
	"The Describe message for a prepared statement ($S) or a portal ($P), as a tag -> payload
	association. See #writeExtendedRequest:."

	^ $D -> (self newMessageBuilder
		nextPutByte: aChar asInteger;
		nextPutString: aName;
		yourself) asBytes
]

{ #category : 'protocol' }
P3Client >> discardResponse [
	"Read what is left of the responses I am in the middle of, up to and including the ReadyForQuery
	that ends the last one. Messages are length prefixed, so I skip a payload without interpreting it.
	Asynchronous messages are still processed, because they carry state and notifications that arrive
	once. An ErrorResponse is kept as #discardedError rather than signalled: signalling would replace
	the error I am recovering from, or surprise a caller that is not in a query at all.

	A CopyInResponse in what is left is a COPY FROM STDIN that nobody will feed. The server waits for
	data before it goes on, so I abandon the copy, see #abandonCopyIn, or the ReadyForQuery never comes."

	[ self isResponsePending ] whileTrue: [
		message readFrom: connection.
		message tag = $Z ifTrue: [ self noteReadyForQuery ].
		message tag = $E ifTrue: [ self noteDiscardedError ].
		message tag = $G ifTrue: [ self abandonCopyIn ].
		self isAsynchronousMessage ifTrue: [ self processAsynchronousMessage ] ]
]

{ #category : 'protocol' }
P3Client >> discardResponseOrClose [
	"Discard the rest of the response I am in the middle of. If that cannot be done my connection can
	no longer be positioned, so close it: reconnecting on the next use is correct, while reusing it
	would answer one request with another's response."

	[ self discardResponse ] on: Error do: [ :error | self closeAfterFailure ]
]

{ #category : 'accessing' }
P3Client >> discardedError [
	"The first ErrorResponse I read while discarding a response, if any. Nobody was waiting for it, so
	it is kept here for inspection instead of being signalled. Cleared by #reset."

	^ discardedError
]

{ #category : 'accessing' }
P3Client >> enableUnknownTypesAsText: aBoolean [
	"When true, a column of a type that has no converter is answered as the text the server sent.
	The default is false: such a column signals a P3Error, because the caller is reading data that it
	does not handle. The setting holds for the connection that is open and for later ones."

	settings at: #unknownTypesAsText put: aBoolean.
	self applyUnknownTypesSetting
]

{ #category : 'private' }
P3Client >> ensureConnected [
	"Open my connection when it is not open. Refuse to reconnect after a connection was lost inside a
	transaction, see #closeAfterFailure.

	A connection that was open and went away on its own is replaced, unless autoReconnect is off: then
	I signal and wait for an explicit #connect. A replacement is a new server session, so I signal
	P3ConnectionReplaced after it is open. A first connect, or one after an explicit #close, is neither."

	| replacing |
	self isConnected ifTrue: [ ^ self ].
	transactionLost ifTrue: [ ^ P3Error connectionLostInTransaction signal ].
	replacing := connectionGeneration > 0 and: [ connectionLost or: [ connection notNil ] ].
	(replacing and: [ self autoReconnect not ])
		ifTrue: [ ^ P3Error connectionLost signal ].
	self isSSL
		ifTrue: [ self connectSSL ]
		ifFalse: [ self connect ].
	replacing ifTrue: [ P3ConnectionReplaced signal ]
]

{ #category : 'private' }
P3Client >> ensureOpen [
	connection ifNil: [ self open ]
]

{ #category : 'protocol' }
P3Client >> ensureResponseRead [
	"Before asking for a new response, make sure the previous one was read. A response left unread
	would be answered to the next request, so discard it rather than let it be mistaken for mine."

	self isResponsePending ifTrue: [ self discardResponseOrClose ]
]

{ #category : 'error handling' }
P3Client >> errorNoticeInfo: payload [
	"The fields of an ErrorResponse or NoticeResponse. Their text is in the connection encoding: it
	quotes user data and may be translated."

	| info fieldType |
	info := Dictionary new.
	[ (fieldType := payload next) isZero ] 
		whileFalse: [ 
			info 
				at: fieldType asCharacter 
				put: (self converter textCStringFrom: payload) ].
	^ info
]

{ #category : 'public' }
P3Client >> execute: query [
	"Execute an SQL query against PostgreSQL, assuming no rows will be returned.
	Result is a string (collection of strings for multiple embedded queries) indicating successful execution.
	This is an alias for #query returning just the command result."
	
	| result |
	result := self query: query.
	^ result results
]

{ #category : 'private' }
P3Client >> forgetPreparedStatementNamed: name [
	properties 
		at: 'prepared_statements' 
		ifPresent: [ :preparedStatements | 
			preparedStatements removeKey: name ifAbsent: [ ] ]
]

{ #category : 'public' }
P3Client >> format: anSQLTemplateString [
	"Create and return a P3FormattedStatement based on anSQLTemplateString and bound to me.
	The template contains numbered placeholders, $1, $2, etc, that are filled with concrete
	arguments when the statement is executed. 
	This should be safer and more correct than building a query manually."
	
	^ P3FormattedStatement new
		client: self;
		sql: anSQLTemplateString;
		yourself
]

{ #category : 'private' }
P3Client >> giveUpReading: aNetworkError [
	"The server did not answer in time, or the connection failed, while I read a response.

	A timeout that stopped between two messages leaves the connection in step, and the server is still
	running the statement: ask it to stop with #cancel, then read what it sends back, an error and
	ReadyForQuery, so the connection stays usable. Every other failure, and a timeout inside a message,
	cannot be read on, so I close."

	(aNetworkError isKindOf: ConnectionTimedOut)
		ifFalse: [ ^ self closeAfterFailure ].
	message isPartial ifTrue: [ ^ self closeAfterFailure ].
	([ self cancel ] on: Error do: [ :error | false ])
		ifTrue: [ self discardResponseOrClose ]
		ifFalse: [ self closeAfterFailure ]
]

{ #category : 'private - authentication' }
P3Client >> handleAuthentication: code [
	| type |
	type := self authenticationTypes 
		at: code 
		ifAbsent: [ (P3Error unsupportedAuthenticationType: code) signal ].
	properties at: #'authentication_type' ifAbsentPut: type. "else OK will overwrite"
	^ self perform: #handleAuthentication , type
]

{ #category : 'private - authentication' }
P3Client >> handleAuthenticationCleartextPassword [
	self writeMessage: self clearTextPasswordMessage tag: $p.
	^ false
]

{ #category : 'private - authentication' }
P3Client >> handleAuthenticationGSS [
	(P3Error unsupportedAuthenticationType: #GSS) signal
]

{ #category : 'private - authentication' }
P3Client >> handleAuthenticationKerberosV5 [
	(P3Error unsupportedAuthenticationType: #KerberosV5) signal
]

{ #category : 'private - authentication' }
P3Client >> handleAuthenticationMD5Password [
	| salt |
	salt := message readStream next: 4.
	self writeMessage: (self md5PasswordMessage: salt) tag: $p.
	^ false
]

{ #category : 'private - authentication' }
P3Client >> handleAuthenticationOk [
	^ true
]

{ #category : 'private - authentication' }
P3Client >> handleAuthenticationSASL [
	| saslAuthenticationMechanisms |
	saslAuthenticationMechanisms := Array streamContents: [ :out | | line |
		[ (line := self converter asciiCStringFrom: message readStream) isEmpty ]
			whileFalse: [ out nextPut: line ] ].
	(saslAuthenticationMechanisms includes: 'SCRAM-SHA-256')
		ifTrue: [
			self runSASLSCRAMSHA256Authentication. 
			^ false ].
	(P3Error unsupportedAuthenticationType: #SASL) signal
]

{ #category : 'private - authentication' }
P3Client >> handleAuthenticationSCMCredential [
	(P3Error unsupportedAuthenticationType: #SCMCredential) signal
]

{ #category : 'private - authentication' }
P3Client >> handleAuthenticationSSPI [
	(P3Error unsupportedAuthenticationType: #SSPI) signal
]

{ #category : 'accessing' }
P3Client >> host [
	"Return the host name I (want to) connect to.
	The default is localhost."

	^ settings at: #host ifAbsentPut: [ 'localhost' ]
]

{ #category : 'initialize-release' }
P3Client >> host: string [
	"Set the name of the host to connect to.
	If not set, defaults to localhost."
	
	settings at: #host put: string
]

{ #category : 'initialization' }
P3Client >> initialize [
	super initialize.
	
	settings := IdentityDictionary new.
	properties := Dictionary new.
	notifications := OrderedCollection new.
	pendingResponses := 0.
	transactionLost := false.
	extendedRequest := false.
	connectionGeneration := 0.
	connectionLost := false.
	
	self beThreadSafe
]

{ #category : 'private' }
P3Client >> initializeConverter [
	self converter initializeFrom: properties.
	self converter timestampClass: self timestampClass.
	self applyUnknownTypesSetting.
	"A new connection has a new converter, so the enums that were loaded are loaded again."
	(settings at: #loadEnums ifAbsent: [ false ]) ifTrue: [ self loadEnums ]
]

{ #category : 'testing' }
P3Client >> isAsynchronousMessage [
	"Is the message I am positioned on one the server can send between any two messages?
	Such a message is not part of any request's response sequence."

	^ 'NSA' includes: message tag
]

{ #category : 'testing' }
P3Client >> isConnected [
	"Return true when my connection is in working order (from my end)"

	^ connection notNil
			and: [ connection isConnected 
				and: [ session notNil ] ]
]

{ #category : 'private' }
P3Client >> isFatalError: errorInfo [
	"Did the server end the session with this ErrorResponse? Its severity is FATAL or PANIC, and it closes the
	socket right after sending it. V is the severity in a form that is not translated, S is the translated one."

	| severity |
	severity := errorInfo at: $V ifAbsent: [ errorInfo at: $S ifAbsent: [ '' ] ].
	^ severity = 'FATAL' or: [ severity = 'PANIC' ]
]

{ #category : 'testing' }
P3Client >> isResponsePending [
	"Is a response I asked for still unread? True between writing a Query or Sync message and reading
	the ReadyForQuery that ends the last outstanding response. See #pendingResponses."

	^ pendingResponses > 0
]

{ #category : 'testing' }
P3Client >> isSSL [
	"Return true if my current connection is SSL encrypted"
	
	^ settings at: #ssl ifAbsent: [ false ]
]

{ #category : 'testing' }
P3Client >> isServerVersionAtLeastMajor: major minor: minor [
	"Return true when the server version if at least major.minor, false otherwise. Elements that are not
	numbers, like the 18beta1 of a pre-release, read as their leading digits, and a missing minor as 0."
	
	| numbers |
	numbers := ($. split: self serverVersion) collect: [ :each |
		Integer readFrom: each ifFail: [ 0 ] ].
	^ numbers first > major
		or: [ numbers first = major
			and: [ (numbers at: 2 ifAbsent: [ 0 ]) >= minor ] ]
]

{ #category : 'testing' }
P3Client >> isTransactionLost [
	"Was my connection closed by a failure while a transaction was open or failed? Then I refuse to
	reconnect silently, see #closeAfterFailure."

	^ transactionLost
]

{ #category : 'testing' }
P3Client >> isUnknownTypesAsTextEnabled [
	^ settings at: #unknownTypesAsText ifAbsent: [ false ]
]

{ #category : 'testing' }
P3Client >> isUsingUnixSocket [
	"Following the PostgreSQL convention a host starting with a / is a Unix Socket directory, see #unixSocketFile"
	
	^ self host notNil and: [ self host first = $/ ]
]

{ #category : 'testing' }
P3Client >> isWorking [
	"Do a trivial query to confirm that I can interact with the server.
	Return true if successful"
	
	| n result |
	n := 999 atRandom.
	result := self query: ('SELECT {1} AS N' format: { n }).
	^ result result = 'SELECT 1' and: [ result firstFieldOfFirstRecord = n ]
]

{ #category : 'convenience' }
P3Client >> listDatabases [
	"Return the list of known database names.
	I can only be connected to a single database, see #database"
	
	^ (self query: 'SELECT datname FROM pg_database ORDER BY 1') firstColumnData
]

{ #category : 'enums' }
P3Client >> listEnums [
	"Return the ENUMs defined in the database, in any schema, as a collection of #(type OID, type name,
	array type OID). The name is qualified with its schema when the type is not in my search path.
	See also #loadEnums"

	^ (self query: 'SELECT t.oid, CASE WHEN pg_type_is_visible(t.oid) THEN t.typname::text ELSE n.nspname || ''.'' || t.typname END, t.typarray
		FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
		WHERE t.oid IN (SELECT DISTINCT enumtypid FROM pg_enum)') data
]

{ #category : 'convenience' }
P3Client >> listSchemas [
	"Return the list of known schema or namespace names"
	
	^ (self query: 'SELECT schema_name FROM information_schema.schemata ORDER BY 1') firstColumnData
]

{ #category : 'convenience' }
P3Client >> listTablesInSchema: schemaName [
	"Return the list of known table names in a given schema as table name, table type pairs."
	
	| statement |
	statement := self format: 'SELECT table_name, table_type FROM information_schema.tables WHERE table_schema = $1 ORDER BY 1'.
	^ (statement query: { schemaName } ) data
]

{ #category : 'enums' }
P3Client >> loadEnums [
	"Define converters for all ENUM types of the database, and for the arrays of them, converting their
	values to Symbols. In PSQL ENUMs constitute distinct type OIDs and must be thus be defined before
	they can be used in results, an ENUM that is not defined signals a P3Error when it is read.
	Since new ENUMs can be added at any time, there is no good/correct time to call this method.
	Call #loadEnums again after ENUMs are (re)defined. Once called, I call it again on every new connection.
	Return the collection of enum type names processed."

	| names |
	names := self listEnums collect: [ :each | | name |
		name := each second asSymbol.
		self converter
			mapOid: each first
			type: name
			to: #convertSymbolFrom:length:description:.
		self converter
			mapArrayOid: each third
			type: ('_' , each second) asSymbol
			elementOid: each first.
		name ].
	settings at: #loadEnums put: true.
	^ names
]

{ #category : 'private - logging' }
P3Client >> logBinding: statement inputValues: inputValues [
	(self newLogEvent: P3StatementBoundEvent)
		statement: statement;
		inputValues: inputValues;
		emit.
	properties at: #query_started put: Time millisecondClockValue
]

{ #category : 'private - logging' }
P3Client >> logConnected [
	"The event carries what describes the connection, not what authenticates it: the password and
	the backend secret key, which is enough to cancel any query of this session, stay with me."

	(self newLogEvent: P3ConnectionEstablishedEvent)
		settings: (settings copy removeKey: #password ifAbsent: [ nil ]; yourself);
		properties: (properties copy removeKey: 'backend_secret_key' ifAbsent: [ nil ]; yourself);
		emit
]

{ #category : 'private - logging' }
P3Client >> logDisconnected [
	(self newLogEvent: P3ConnectionClosedEvent)
		emit 
]

{ #category : 'private - logging' }
P3Client >> logError: error [
	(self newLogEvent: P3ErrorOccurredEvent)
		exception: error;
		emit
]

{ #category : 'private - logging' }
P3Client >> logPreparedStatement: statement query: query [
	(self newLogEvent: P3StatementPreparedEvent)
		statement: statement;
		query: query;
		emit
]

{ #category : 'private - logging' }
P3Client >> logQuery: query [
	(self newLogEvent: P3QueryWrittenEvent)
		query: query;
		emit.
	properties at: #query_started ifAbsentPut: Time millisecondClockValue
]

{ #category : 'private - logging' }
P3Client >> logResult: result [
	| duration |
	duration := properties 
		at: #query_started 
		ifPresent: [ :initialMilliseconds | Time millisecondsSince: initialMilliseconds ]
		ifAbsent: [ 0 ].
	(self newLogEvent: P3ResultReadEvent)
		result: result;
		duration: duration;
		emit.
	properties removeKey: #query_started ifAbsent: [  ]
]

{ #category : 'private - logging' }
P3Client >> logRetryConnection: remaining [
	(self newLogEvent: P3RetryConnectionEvent)
		remaining: remaining;
		delay: self retryDelay;
		emit
]

{ #category : 'private messages' }
P3Client >> md5PasswordMessage: salt [
	"concat('md5', md5(concat(md5(concat(password, username)), random-salt))).
	Keep in mind the md5() function returns its result as a hex string.
	The password and the user name are hashed as UTF-8, as the server stores them."
	
	| credential salted |
	self password ifNil: [ P3Error passwordRequired signal ].
	credential := (MD5 hashMessage: (self password , self user) utf8Encoded) hex.
	salted := (MD5 hashMessage: credential asByteArray , salt) hex.
	^ self asCString: 'md5' , salted
]

{ #category : 'private - logging' }
P3Client >> newLogEvent: logEventClass [
	^ logEventClass new
			session: self session;
			yourself
]

{ #category : 'private' }
P3Client >> newMessageBuilder [
	^ P3MessageBuilder newWithEncoder: self converter encoder
]

{ #category : 'private' }
P3Client >> newSocketStream [
	"A new socket stream to the server, not yet speaking the protocol. Reaching the server is bounded by
	#connectTimeout, afterwards waiting for it is bounded by #timeout."

	| stream |
	stream := self isUsingUnixSocket
		ifTrue: [ ZdcSocketStream on: (ZnNetworkingUtils default unixSocketOnFile: self unixSocketFile) ]
		ifFalse: [ self newTcpSocketStream ].
	stream timeout: self timeout.
	^ stream
]

{ #category : 'private' }
P3Client >> newTcpSocketStream [
	| stream address |
	stream := ZdcSocketStream on: Socket newTCP.
	stream timeout: self connectTimeout.
	[ address := NetNameResolver addressForName: self host timeout: self connectTimeout.
	(address isNil or: [ address = SocketAddress zero ])
		ifTrue: [ ^ NameLookupFailure signalFor: self host ].
	stream connectTo: address port: self port ]
		on: Error
		do: [ :error |
			[ stream close ] on: Error do: [ :ignored | ].
			error pass ].
	^ stream
]

{ #category : 'private' }
P3Client >> noteDiscardedError [
	"Remember and log an ErrorResponse read while discarding a response. When I am recovering from a
	failure already being reported it is redundant, but when I am draining a response nobody read it is
	the only trace of it: a COMMIT that failed on a serialization error would otherwise vanish."

	| error |
	error := P3Error new
		info: (self errorNoticeInfo: message readStream);
		yourself.
	discardedError ifNil: [ discardedError := error ].
	self logError: error
]

{ #category : 'private' }
P3Client >> noteReadyForQuery [
	"ReadyForQuery ends one response and carries the transaction status, so one fewer response is
	outstanding and I am positioned at the start of the next one."

	pendingResponses := (pendingResponses - 1) max: 0.
	transactionStatus := message readStream next asCharacter
]

{ #category : 'private' }
P3Client >> noteResponseRequested [
	"A Query or Sync message asks the server for a response ended by exactly one ReadyForQuery. I
	count them instead of remembering that there is one, because a caller that abandons a response
	and then sends another request leaves two outstanding, and draining has to reach the last."

	pendingResponses := pendingResponses + 1
]

{ #category : 'accessing' }
P3Client >> notifications [
	"The NOTIFYs collected while reading responses, oldest first. See #takeNotifications to consume
	them. A connection that LISTENs and never consumes them collects them without bound."

	^ self critical: [ notifications asArray ]
]

{ #category : 'connecting' }
P3Client >> open [
	"Open my connection with the server (do not yet #connect)"
	
	self close.
	connection := self newSocketStream.
	message := P3MessageBuffer new
]

{ #category : 'private' }
P3Client >> parseMessageFor: queryString name: statementName types: paramDataTypes [
	"The Parse message for queryString, as a tag -> payload association. See #writeExtendedRequest:."

	| builder |
	builder := self newMessageBuilder.
	builder
		nextPutString: statementName;
		nextPutString: queryString;
		nextPutInt16: paramDataTypes size.
	paramDataTypes do: [ :each | builder nextPutInt32: each ].
	^ $P -> builder asBytes
]

{ #category : 'accessing' }
P3Client >> password [
	"Return the password of my database connection.
	For no password, nil is used."

	^ settings at: #password ifAbsent: [ nil ]
]

{ #category : 'initialize-release' }
P3Client >> password: string [
	"Set the password to use when connecting.
	Set to nil or don't set to use no password."

	settings at: #password put: string
]

{ #category : 'accessing' }
P3Client >> pendingResponses [
	"How many responses the server still owes me: one per Query or Sync message written, one less per
	ReadyForQuery read. Normally 0 or 1."

	^ pendingResponses
]

{ #category : 'accessing' }
P3Client >> port [
	"Return the port I (want to) connect to.
	The default is 5432."

	^ settings at: #port ifAbsentPut: [ 5432 ]
]

{ #category : 'initialize-release' }
P3Client >> port: integer [
	"Set the port to connect to.
	If not set, defaults to 5432."
	
	settings at: #port put: integer
]

{ #category : 'public' }
P3Client >> prepare: query [
	"Create a P3PreparedStatement with a default name derived from the query string, see
	#defaultStatementNameFor:. Preparing a query that is already prepared in this session answers that
	statement, so both holders share it and closing it closes it for both."

	| name existing |
	name := self defaultStatementNameFor: query.
	existing := properties
		at: 'prepared_statements'
		ifPresent: [ :preparedStatements | preparedStatements at: name ifAbsent: [ nil ] ]
		ifAbsent: [ nil ].
	(existing notNil and: [ existing source = query and: [ existing isStale not and: [ self isConnected ] ] ])
		ifTrue: [ ^ existing ].
	^ self prepare: query named: name
]

{ #category : 'public' }
P3Client >> prepare: query named: queryName [
	"Create and return an instance of P3PreparedStatement by parsing query, 
	which can contain one or more placeholders, once. Later the prepared statement can be executed 
	multiple times by providing an array with a value for each placeholder. 
	When no longer needed, the prepared statement should be closed. See P3PreparedStatement.
	Each prepared statement must have a unique name. Note that in a standard Postgres installation 
	only the first 63 characters of queryName are significant."

	^ self
		runRequest: [
			self writeExtendedRequest: {
				self parseMessageFor: query name: queryName types: #().
				self describeMessageFor: queryName type: $S } ]
		response: [ self readPreparedStatement: query named: queryName ]
]

{ #category : 'private' }
P3Client >> prepareAgain: aPreparedStatement [
	"Make sure aPreparedStatement exists in my current server session. A new connection is a new session
	and the server forgot everything prepared in the old one, so prepare its source again under its name.
	The statement object stays the one the caller holds and takes over what the server describes now.

	This runs before the request is built. A connection lost between the two is not covered: the request then
	fails with the server's 26000, and the next use prepares again."

	self critical: [
		| fresh |
		self ensureResponseRead.
		self ensureConnected.
		aPreparedStatement isStale ifTrue: [
			fresh := self prepare: aPreparedStatement source named: aPreparedStatement name.
			aPreparedStatement adoptPreparationOf: fresh.
			(properties at: 'prepared_statements') at: aPreparedStatement name put: aPreparedStatement ] ]
]

{ #category : 'accessing' }
P3Client >> preparedStatementNamed: name [
	"Return the P3PreparedStatement previously created under name, else signal NotFound"
	
	properties 
		at: 'prepared_statements'
		ifPresent: [ :preparedStatements |
			preparedStatements 
				at: name 
				ifPresent: [ :preparedStatement | ^ preparedStatement ] ].
	NotFound signalFor: name in: self
]

{ #category : 'printing' }
P3Client >> printOn: stream [
	super printOn: stream.
	stream nextPut: $(.
	self printStateOn:  stream.
	stream nextPut: $)
]

{ #category : 'printing' }
P3Client >> printStateOn: stream [
	stream print: self compactUrl.
	self session ifNotNil: [ stream space; print: session ]
]

{ #category : 'private' }
P3Client >> processAsynchronousMessage [
	"Consume the asynchronous message I am positioned on. See #isAsynchronousMessage."

	message tag = $N ifTrue: [ ^ self processNoticeResponse ].
	message tag = $S ifTrue: [ ^ self processParameterStatus: message readStream ].
	^ self processNotificationResponse
]

{ #category : 'private' }
P3Client >> processBackendKeyData: payload [
	session := payload uint32.
	properties at: 'backend_process_id' put: session.
	properties at: 'backend_secret_key' put: payload uint32
]

{ #category : 'private' }
P3Client >> processDataRowUsing: description [
	| count record readStream |
	readStream := message readStream.
	count := readStream uint16.
	record := Array new: count.
	1 to: count do: [ :index | | size |
		size := readStream uint32.
		size = 16rFFFFFFFF
			ifFalse: [ | object |
				object := (description at: index) convert: readStream length: size using: converter.
				record at: index put: object ] ].
	^ record
]

{ #category : 'private' }
P3Client >> processNoticeResponse [
	"Signal the notice as a resumable P3Notification, so a sender that cares can observe it while
	reading continues."

	self signal: P3Notification using: (self errorNoticeInfo: message readStream)
]

{ #category : 'private' }
P3Client >> processNotificationResponse [
	"Collect the NOTIFY I am positioned on. The server delivers it once, so discarding it would
	lose its payload. See #notifications."

	| payload |
	payload := message readStream.
	notifications addLast: (P3ChannelNotification
		processId: payload uint32
		channel: (self converter encodedCStringFrom: payload)
		payload: (self converter encodedCStringFrom: payload))
]

{ #category : 'private' }
P3Client >> processParameterDescription: payload [
	| count |
	count := payload uint16.
	^ Array new: count streamContents: [ :out |
			count timesRepeat: [ 
				out nextPut: (P3ParameterDescription new
					typeOid: payload uint32;
					yourself) ] ]
]

{ #category : 'private' }
P3Client >> processParameterStatus: payload [
	"Record a server parameter. Some of them decide how values are formatted, so the converter has to
	hear about a change instead of reading them once at connect time. The converter exists by now
	because reading the message needed it."

	| key value |
	
	key := self converter asciiCStringFrom: payload.
	value := self converter asciiCStringFrom: payload.
		
	properties at: key put: value.
	self converter noteSessionParameter: key value: value
]

{ #category : 'private' }
P3Client >> processRowDescription: payload [
	| count |
	count := payload uint16.
	^ Array new: count streamContents: [ :out |
			count timesRepeat: [ 
				out nextPut: (P3RowFieldDescription new
					fieldName: (self converter encodedCStringFrom: payload);
					tableOid: payload uint32;
					attributeNumber: payload int16;
					typeOid: payload uint32;
					typeSize: payload int16;
					typeModifier: payload int32;
					format: payload uint16;
					yourself) ] ]
]

{ #category : 'public' }
P3Client >> query: query [
	"Execute an SQL query against PostgreSQL. Return a P3Result object containing result(s), column descriptions and data.
	Result(s) is a string (collection of strings for multiple embedded queries) indicating successful execution.
	Descriptions is a collection of row field description objects, if any.
	Data is a collection of rows with fully converted field values as objects, if any."

	^ self
		runRequest: [
			properties at: #sql_source put: query.
			self writeQueryMessage: query ]
		response: [ self basicRunQueryResult ]
]

{ #category : 'accessing' }
P3Client >> queryEncoding [
	"An alias used by PharoDatabaseAccessor, kept for compatibility"
	
	^ self serverEncoding
]

{ #category : 'private' }
P3Client >> readCloseComplete [
	"Read the response to a Close message ended by Sync."

	self readMessage tag = $3
		ifFalse: [ ^ P3Error closeCompleteExpected signal ].
	self readMessage tag = $Z
		ifFalse: [ ^ P3Error readyForQueryExpected signal ]
]

{ #category : 'private' }
P3Client >> readDataRows: descriptions [
	"Read the DataRow messages starting at the one I am positioned on, and leave me positioned on the
	first message that is not one. Answer them converted through descriptions."

	descriptions ifNil: [ ^ self rejectOutOfStepMessage ].
	^ Array streamContents: [ :out |
		[ message tag = $D ] whileTrue: [
			out nextPut: (self processDataRowUsing: descriptions).
			self readMessage ] ]
]

{ #category : 'protocol' }
P3Client >> readFieldDescriptions [
	"Answer the result fields the server describes, empty when it answers NoData."

	self readMessage tag = $T
		ifTrue: [ ^ self processRowDescription: message readStream ].
	message tag = $n
		ifFalse: [ ^ P3Error noDataExpected signal ].
	^ #()
]

{ #category : 'input/output' }
P3Client >> readMessage [
	"During normal operations, an error is reported followed by a ready for query so that we can continue to use the connection"
	
	^ self readMessageOnError: [ self assert: self readMessage tag = $Z ]
]

{ #category : 'input/output' }
P3Client >> readMessageCloseAfterError [
	"During authentication and startup errors result in the server closing the connection, do the same"
	
	^ self readMessageOnError: [ self close ]
]

{ #category : 'private' }
P3Client >> readMessageOnError: block [
	"Read the next message belonging to the response flow. NoticeResponse, ParameterStatus and
	NotificationResponse can arrive between any two messages, so I consume them here and keep reading
	under the same error policy: my senders only see the messages their own sequence expects.

	An ErrorResponse is normally followed by a ReadyForQuery, which block reads. A FATAL or PANIC one is
	not: the server closes the socket instead, so reading on would only find the end of the stream and
	lose the error. I close here, which also remembers a transaction that was open, and signal it."

	[ message readFrom: connection.
	  message tag = $E 
		ifTrue: [ | info |
			info := self errorNoticeInfo: message readStream.
			(self isFatalError: info)
				ifTrue: [ self closeAfterFailure ]
				ifFalse: [ block cull: info ].
			self signal: P3Error using: info ].
	  message tag = $Z
		ifTrue: [ self noteReadyForQuery ].
	  self isAsynchronousMessage ] whileTrue: [ self processAsynchronousMessage ].
	^ message
]

{ #category : 'protocol' }
P3Client >> readParameterDescriptions [
	"Answer the parameters the server describes, empty when it answers NoData."

	self readMessage tag = $t
		ifTrue: [ ^ self processParameterDescription: message readStream ].
	message tag = $n
		ifFalse: [ ^ P3Error noDataExpected signal ].
	^ #()
]

{ #category : 'private' }
P3Client >> readPreparedStatement: query named: queryName [
	"Read what the server describes for a statement it just parsed and answer a new P3PreparedStatement
	for it. Nothing has been executed."

	| parameterDescriptions fieldDescriptions statement |
	self readMessage tag = $1
		ifFalse: [ ^ P3Error parseCompleteExpected signal ].
	parameterDescriptions := self readParameterDescriptions.
	fieldDescriptions := self readFieldDescriptions.
	self readMessage tag = $Z
		ifFalse: [ ^ P3Error readyForQueryExpected signal ].
	statement := self 
		createPreparedStatementNamed: queryName 
		withParameters: parameterDescriptions
		andFields: fieldDescriptions.
	statement source: query.
	self logPreparedStatement: statement query: query.
	^ statement
]

{ #category : 'private' }
P3Client >> readQueryResultInto: result [
	"Read one result of a Query response, starting at the message I am positioned on: an optional
	RowDescription with the DataRows that follow it, then the CommandComplete that ends the result. An
	EmptyQueryResponse replaces all of that for a query that contained no statement."

	message tag = $I
		ifTrue: [ ^ result addResult: '' ].
	message tag = $T
		ifTrue: [
			result descriptions: (self processRowDescription: message readStream).
			self readMessage.
			result data: (self readDataRows: result descriptions) ].
	message tag = $C
		ifFalse: [ ^ self rejectUnexpectedMessage ].
	result addResult: (self converter asciiCStringFrom: message readStream)
]

{ #category : 'private' }
P3Client >> readResponse: block [
	"Read a response by evaluating block. When that fails before ReadyForQuery was read, discard the
	rest of the response first, so I stay positioned at the start of the next one, and only then
	re-signal. A failure the server reported has already been read up to ReadyForQuery, which is why I
	ask #isResponsePending instead of assuming.

	A network failure is different: draining would wait another full timeout on the same silent socket,
	and the server may still be executing. See #giveUpReading:."

	^ [ [ block value ]
		on: NetworkError
		do: [ :error | self giveUpReading: error. error pass ] ]
		on: Error
		do: [ :error |
			self isResponsePending ifTrue: [ self discardResponseOrClose ].
			error pass ]
]

{ #category : 'private' }
P3Client >> rejectCopyIn [
	"COPY FROM STDIN waits for the caller to send the data. Abandon the copy before reporting it, so the
	response ends with a ReadyForQuery I can read instead of blocking until the timeout: closing here
	would lose the temporary objects the copy was written for. See #abandonCopyIn."

	self abandonCopyIn.
	^ P3Error copyNotSupported signal
]

{ #category : 'private' }
P3Client >> rejectOutOfStepMessage [
	"A message I cannot place in the response I am reading means I no longer know where the next one
	starts, so my connection cannot be positioned: close it rather than read on. An assertion here would
	report the same thing without doing anything about it."

	| tag |
	tag := message tag.
	self closeAfterFailure.
	^ (P3Error unexpectedMessage: tag) signal
]

{ #category : 'private' }
P3Client >> rejectUnexpectedMessage [
	"Refuse the message I am positioned on, which does not belong where the response I am reading has
	arrived. A COPY response needs its data streamed, which I do not support; anything else means the
	message stream is out of step."

	message tag = $G ifTrue: [ ^ self rejectCopyIn ].
	('HW' includes: message tag) ifTrue: [ ^ P3Error copyNotSupported signal ].
	^ self rejectOutOfStepMessage
]

{ #category : 'private' }
P3Client >> reset [
	self clearSession.
	properties removeAll.
	discardedError := nil.
	converter := nil
]

{ #category : 'accessing' }
P3Client >> retryCount [
	"Return how many times a reconnection will be tried on a failed connection, the default being 10 times.
	See also #retryDelay."
	
	^ settings at: #retryCount ifAbsentPut: [ 10 ]
]

{ #category : 'initialize-release' }
P3Client >> retryCount: count [
	"Set how many times a reconnection will be tried on a failed connection, the default being 10 times.
	See also #retryDelay:"
	
	settings at: #retryCount put: count
]

{ #category : 'accessing' }
P3Client >> retryDelay [
	"Return the delay after which a reconnection will be tried on a failed connection, the default being 5 seconds.
	See also #retryCount."
	
	^ settings at: #retryDelay ifAbsentPut: [ 5 ]
]

{ #category : 'initialize-release' }
P3Client >> retryDelay: seconds [
	"Set the delay after which a reconnection will be tried on a failed connection, the default being 5 seconds.
	See also #retryCount:"
	
	settings at: #retryDelay put: seconds
]

{ #category : 'protocol' }
P3Client >> runAuthentication [
	[
	self readMessageCloseAfterError tag = $R
		ifTrue: [ | authenticationCode |
			authenticationCode := (message readStream next: 4) asInteger.
			(self handleAuthentication: authenticationCode)
				ifTrue: [ ^ self ] ]
		ifFalse: [ 
			^ P3Error unexpectedMessageDuringAuthentication signal ] ] repeat
]

{ #category : 'private' }
P3Client >> runCloseStatementNamed: aName [
	"Close a prepared statement server side. Close is sent with Sync, not Flush: after an error the
	server discards every message until a Sync arrives, so with Flush an ErrorResponse here would leave
	me waiting for a ReadyForQuery that never comes and the server dropping everything I send next."

	^ self
		runRequest: [ self writeExtendedRequest: { self closeMessageFor: aName type: $S } ]
		response: [ self readCloseComplete ]
]

{ #category : 'protocol' }
P3Client >> runExtendedQueryResult: descriptions [
	"Read one result of an extended-query response, starting at the message I am positioned on:
	BindComplete, then the DataRows up to the CommandComplete ($C) or PortalSuspended ($s) that ends
	them. An EmptyQueryResponse ($I) replaces all of that for a query that contained no statement."

	| rows result |
	message tag = $2
		ifFalse: [ ^ P3Error bindCompleteExpected signal ].
	self readMessage.
	message tag = $I
		ifTrue: [
			result := P3Result new addResult: ''; yourself.
			result source: (properties at: #sql_source ifAbsent: nil).
			self logResult: result.
			^ result ].
	rows := self readDataRows: descriptions.
	('Cs' includes: message tag)
		ifFalse: [ ^ self rejectUnexpectedMessage ].
	result := P3Result 
		descriptions: descriptions
		data: rows 
		results: (self converter asciiCStringFrom: message readStream).
	result source: (properties at: #sql_source ifAbsent: nil).
	self logResult: result.
	^ result
]

{ #category : 'private' }
P3Client >> runExtendedRequest: messages fieldDescriptions: fieldDescriptions statement: statement inputRows: inputRows [
	"Run an extended-query request: messages, a collection of tag -> payload associations built in
	memory, sent together and ended by Sync. Answer one P3Result per Execute among them.
	The source and the bound values are recorded under the monitor, once the request is sent, so
	another process cannot change them between my write and my read."

	^ self
		runRequest: [
			properties at: #sql_source put: statement source.
			self writeExtendedRequest: messages.
			inputRows do: [ :each | self logBinding: statement inputValues: each ] ]
		response: [ self basicRunExtendedQueryResults: fieldDescriptions ]
]

{ #category : 'private' }
P3Client >> runRequest: writeBlock response: readBlock [
	"Write one request and read its response as a single unit. Every request goes through here.

	The monitor is held for both halves, so another process cannot place its own request between my
	write and my read. A response nobody read is drained before a new one is asked for, and only then
	is the connection checked: a drain that has to close would otherwise leave the request written to
	nothing.

	A network failure before the server received the request is retried on a fresh connection,
	because nothing ran. Once the request is sent, a network failure is not retried, see
	#readResponse:, running it again could execute it twice. The delay between retries is waited
	outside the monitor, so other processes can use me meanwhile."

	| remaining result |
	remaining := self retryCount.
	[ result := self critical: [
			self attemptRequest: writeBlock response: readBlock canRetry: remaining > 0 ].
	result == #retry ] whileTrue: [
		remaining < self retryCount ifTrue: [
			self logRetryConnection: remaining.
			self retryDelay seconds wait ].
		remaining := remaining - 1 ].
	^ result
]

{ #category : 'private - authentication' }
P3Client >> runSASLSCRAMSHA256Authentication [
	| scram  |
	scram := self scramSHA256.
	self writeMessage: (self saslSCRAMSHA256FirstMessage: scram) tag: $p. "SASLInitialResponse"
	self readMessageCloseAfterError tag = $R "AuthenticationSASLContinue"
		ifFalse: [ P3Error unexpectedMessageDuringAuthentication signal ].
	self assert: (message readStream next: 4) asInteger = 11.
	scram serverFirstMessage: message readStream upToEnd asString.
	self writeMessage: scram clientFinalMessage asByteArray tag: $p. "SASLResponse"
	self readMessageCloseAfterError tag = $R "AuthenticationSASLFinal"
		ifFalse: [ P3Error unexpectedMessageDuringAuthentication signal ].
	self assert: (message readStream next: 4) asInteger = 12.
	scram serverFinalMessage: message readStream upToEnd asString
]

{ #category : 'protocol' }
P3Client >> runStartup [
	"Read the messages the server sends after authentication, up to the ReadyForQuery that ends the
	startup. ParameterStatus and NoticeResponse are consumed by #readMessageOnError:, so only
	BackendKeyData is left here. NegotiateProtocolVersion ($v) would be reported as unexpected, which is
	correct while I ask for 3.0 with no _pq_ options and nothing to negotiate."

	session := 999999 atRandom. "Sometimes $K is not sent and we need a nonNil session"
	[
	self readMessageCloseAfterError tag = $Z
		ifTrue: [ ^ self ].
	message tag = $K
		ifTrue: [ self processBackendKeyData: message readStream ]
		ifFalse: [ ^ P3Error unexpectedMessageDuringStartup signal ] ] repeat
]

{ #category : 'private messages' }
P3Client >> saslSCRAMSHA256FirstMessage: scram [
	| saslMessage |
	saslMessage := scram clientFirstMessage.
	^ (self asCString: 'SCRAM-SHA-256')
		, (saslMessage size asByteArrayOfSize: 4) 
		, saslMessage asByteArray

]

{ #category : 'private - authentication' }
P3Client >> scramSHA256 [
	"Answer a new exchange for each login: it holds the nonces and the challenge of one handshake.
	Only the salted password is shared between logins, see P3SCRAM>>#saltedPassword."

	self password ifNil: [ P3Error passwordRequired signal ].
	^ P3SCRAM new
		sha256;
		password: self password;
		yourself
]

{ #category : 'private' }
P3Client >> secureStreamOn: aSocketStream [
	"Ask the server for TLS on aSocketStream, a connection that did not send anything yet, and answer
	the encrypted stream."

	| reply |
	
	aSocketStream nextPutAll: #[ 0 0 0 8 ] , self sslRequestMessage; flush.
	reply := aSocketStream next asCharacter.
	reply = $S
		ifFalse: [ ^ P3Error postgreSQLServerDidNotHonorSSLConnectionRequest signal ].
	^ (ZdcSecureSocketStream on: aSocketStream socket) connect; yourself
]

{ #category : 'private' }
P3Client >> sendRequest: aBlock [
	"Send one complete request by evaluating aBlock, and note only afterwards that the server owes me
	a response: a request that could not be built or written never reached the server, and waiting for
	an answer to it would cost a full timeout and then my connection.

	Bytes that did reach the socket leave a partial message behind, which nothing sent after it can be
	framed against, so a failure here closes the connection instead of writing again."

	[ aBlock value ] on: Error do: [ :error | self closeAfterFailure. error pass ].
	self noteResponseRequested
]

{ #category : 'accessing' }
P3Client >> serverEncoding [
	"Return the name of the encoder/decoder used by the server for this session/connection.
	This is determined automatically from the client_encoding property of the server.
	One way to set the default at the database level is with the SQL command
	ALTER DATABASE <mydb> SET client_encoding TO 'UTF8' "
	
	^ self critical: [
		self ensureConnected.
		self converter encoder identifier ]
]

{ #category : 'accessing' }
P3Client >> serverTimezone [
	"Return the name of the timezone used by the server for this session/connection.
	This is determined automatically from the TimeZone property of the server.
	One way to set the default at the database level is with the SQL command
	ALTER DATABASE <mydb> SET timezone TO 'UTC' "
	
	^ self critical: [
		self ensureConnected.
		self converter timezoneName ]
]

{ #category : 'accessing' }
P3Client >> serverVersion [
	"Return the version string of the PostgreSQL server"
	
	^ self critical: [
		self ensureConnected.
		properties 
			at: 'server_version' 
			ifAbsent: [ (self query: 'SHOW server_version') firstFieldOfFirstRecord ] ]
]

{ #category : 'accessing' }
P3Client >> session [
	"Returns the current session identifier (backend process id) if connected.
	Only reads: this is called by printing, inspecting and logging, which must not change my state."

	^ self isConnected ifTrue: [ session ]
]

{ #category : 'initialize-release' }
P3Client >> setSSL [
	"Set a flag to make me use TLS/SSL when connecting to PostgrSQL.
	The default is to use a plain unencrypted network connection."
	
	settings at: #ssl put: true
]

{ #category : 'error handling' }
P3Client >> signal: exceptionClass using: info [
	| exception |
	(exception := exceptionClass new) 
		info: info.
	self logError: exception.
	exception signal
]

{ #category : 'private' }
P3Client >> sslModeOf: aUrl [
	"Answer whether aUrl asks for TLS. Only disable, the default, and require are supported. Any other
	mode, such as prefer, allow, verify-ca, verify-full or a misspelt one, asks for something that I do
	not do, so it signals instead of connecting without the TLS or the verification that was asked for."

	| mode |
	mode := (aUrl queryAt: #sslmode ifAbsent: [ 'disable' ]) ifNil: [ '' ].
	mode := mode asString.
	mode = 'disable' ifTrue: [ ^ false ].
	mode = 'require' ifTrue: [ ^ true ].
	^ (P3Error unsupportedSslMode: mode) signal
]

{ #category : 'private messages' }
P3Client >> sslRequestMessage [
	^ #[4 210 22 47] "1234 5678"
]

{ #category : 'private messages' }
P3Client >> startupMessage [
	"The client_encoding is requested, whatever the role or the database default is, because I decode
	what the server sends as UTF-8 until it reports another encoding. DateStyle and IntervalStyle are
	requested because the converter reads only the ISO and postgres styles, and extra_float_digits
	because servers before 12 round floats without it. An application that wants others can say so in
	the options."

	^ ByteArray streamContents: [ :out |
			out nextPutAll: #[ 0 3 0 0 ]. "Protocol major.minor 3.0"
			out nextPutAll: (self asCString: 'user').
			out nextPutAll: (self asCString: self user).
			self database ifNotNil: [ 
				out nextPutAll: (self asCString: 'database').
				out nextPutAll: (self asCString: self database) ].
			#( 'client_encoding' 'UTF8' 'DateStyle' 'ISO' 'IntervalStyle' 'postgres' 'extra_float_digits' '3' )
				do: [ :each | out nextPutAll: (self asCString: each) ].
			self applicationName ifNotNil: [ :name |
				out nextPutAll: (self asCString: 'application_name').
				out nextPutAll: (self asCString: name) ].
			self startupOptions ifNotNil: [
				out nextPutAll: (self asCString: 'options').
				out nextPutAll: (self asCString: self startupOptions) ].
			self statementTimeout ifNotNil: [ :seconds |
				out nextPutAll: (self asCString: 'statement_timeout').
				out nextPutAll: (self asCString: (seconds * 1000) rounded asString) ].
			out nextPut: 0 ]
]

{ #category : 'accessing' }
P3Client >> startupOptions [
	^ settings at: #options ifAbsent: [ nil ]
]

{ #category : 'accessing' }
P3Client >> startupOptions: optionsString [
	settings at: #options put: optionsString
]

{ #category : 'printing' }
P3Client >> statePrintString [
	^ String streamContents: [ :out | self printStateOn: out ]
]

{ #category : 'accessing' }
P3Client >> statementTimeout [
	"Return the seconds after which the server stops a statement, or nil when it does not."

	^ settings at: #statementTimeout ifAbsent: [ nil ]
]

{ #category : 'accessing' }
P3Client >> statementTimeout: seconds [
	"Have the server stop any statement that runs longer than seconds, with a P3Error 57014 that leaves my
	connection usable. It is sent with the startup, so it holds for connections opened after this call.
	Nil, the default, sets no limit."

	settings at: #statementTimeout put: seconds
]

{ #category : 'accessing' }
P3Client >> takeNotifications [
	"Answer the NOTIFYs collected so far and forget them, so each one is handled once. Under my monitor,
	because a reader process adds to the same collection."

	^ self critical: [
		| collected |
		collected := notifications asArray.
		notifications removeAll.
		collected ]
]

{ #category : 'accessing' }
P3Client >> timeout [
	"Return the timeout in seconds I (want to) use when waiting for the server, the default being 2 hours.
	A statement that takes longer is cancelled, see #giveUpReading:. Reaching the server is bounded
	by #connectTimeout."
	
	^ settings at: #timeout ifAbsentPut: [ 7200 ]
]

{ #category : 'initialize-release' }
P3Client >> timeout: seconds [

	settings at: #timeout put: seconds
]

{ #category : 'accessing' }
P3Client >> timestampClass [
	"Return the class used to create instances for TIMESTAMP WITH[OUT] TIME ZONE
	by sending it #year:month:day:hour:minute:second:nanoSecond:offset:
	The default is DateAndTime. A good alternative is ZTimestamp."
	
	^ settings at: #timestampClass ifAbsentPut: [ DateAndTime ]
]

{ #category : 'initialize-release' }
P3Client >> timestampClass: timestampClass [
	"Set the class used to create instances for TIMESTAMP WITH[OUT] TIME ZONE
	by sending it #year:month:day:hour:minute:second:nanoSecond:offset:
	The default is DateAndTime. A good alternative is ZTimestamp."
	
	settings at: #timestampClass put: timestampClass
]

{ #category : 'accessing' }
P3Client >> transactionStatus [
	"The status byte of the last ReadyForQuery I read: $I outside a transaction, $T inside one,
	$E inside one that failed and rejects further queries until it ends. Nil before the first
	response has been read."

	^ transactionStatus
]

{ #category : 'private' }
P3Client >> unixSocketFile [
	"Following the PostgreSQL convention a host that is a directory holds the socket file
	.s.PGSQL.<port>. A host that is not a directory names the socket file itself."

	| file |
	file := self host asFileReference.
	^ file isDirectory
		ifTrue: [ file / ('.s.PGSQL.' , self port asString) ]
		ifFalse: [ file ]
]

{ #category : 'private' }
P3Client >> upgradeToSSL [
	connection := self secureStreamOn: connection
]

{ #category : 'accessing' }
P3Client >> url [
	"Return my connection URL"
	
	| url |
	(url := ZnUrl new) scheme: #postgresql.
	self isUsingUnixSocket
		ifTrue: [ 
			url queryAt: #host put: self host.
			self user ifNotNil: [ url queryAt: #user put: self user ].
			self password ifNotNil: [ url queryAt: #password put: self password ] ]
		ifFalse: [
			url 
				host: self host;
				port: self port;
				username: self user;
				password: self password ].
	self database ifNotNil: [ url addPathSegment: self database ].
	self isSSL ifTrue: [ url queryAt: #sslmode put: #require ].
	self startupOptions ifNotNil: [ :options | url queryAt: #options put: options ].
	^ url
]

{ #category : 'accessing' }
P3Client >> url: stringOrUrl [
	"Set my connection settings from stringOrUrl according to the format
	postgresql://username:password@localhost:5432/databasename?sslmode=require
	with the minimum being psql://user@localhost , for a unix socket the format is
	postgresql:///databasename?host=/path/to/psql.socket&user=username&password=password
	The sslmode is either disable, the default, or require. Any other value signals a P3Error,
	see #sslModeOf:."
	
	| url useSSL |
	url := stringOrUrl asUrl.
	self assert: (#(psql postgres postgresql) includes: url scheme).
	useSSL := self sslModeOf: url.
	url host
		ifNil: [
			url queryAt: #host ifPresent: [ :host | self host: host ].
			url queryAt: #user ifPresent: [ :user | self user: user ].
			url queryAt: #password ifPresent: [ :password | self password: password ] ]
		ifNotNil: [
			self
				host: url host;
				port: (url portIfAbsent: [ 5432 ]);
				user: url username;
				password: url password ].
	self database: url firstPathSegment.
	useSSL ifTrue: [ self setSSL ].
	url queryAt: #options ifPresent: [ :options | self startupOptions: options ]
]

{ #category : 'accessing' }
P3Client >> user [
	"Return the user of my database connection.
	For the default, nil is used."

	^ settings at: #user ifAbsent: [ nil ]
]

{ #category : 'initialize-release' }
P3Client >> user: string [
	"Set the user to use when connecting.
	Set to nil or don't set to use the default."
	
	settings at: #user put: string
]

{ #category : 'accessing' }
P3Client >> verbose: flag [
	"Enable logging to the Transcript when flag is true.
	Disable logging to the Transcript when flag is false.
	Note that P3 uses object logging, with which you can do much more than output plain strings."
	
	flag
		ifTrue: [ P3LogEvent logToTranscript ] 
		ifFalse: [ P3LogEvent stopLoggingToTranscript ]
]

{ #category : 'private' }
P3Client >> writeExtendedRequest: messages [
	"Write an extended-query request: messages, a collection of tag -> payload associations, followed by
	the Sync that ends it and asks the server for exactly one response.

	The payloads are already built, which is the point: a batch that fails while its Bind messages are
	being built must leave nothing in the socket, or the rows written so far are executed by whatever
	request flushes next while the caller is told the batch failed."

	self sendRequest: [
		messages do: [ :each | self writeMessageNoFlush: each value tag: each key ].
		self writeMessage: #[] tag: $S ].
	extendedRequest := true
]

{ #category : 'input/output' }
P3Client >> writeMessage: payload [
	| size |
	size := payload size + 4.
	4 to: 1 by: -1 do: [ :index | connection nextPut: (size byteAt: index) ].
	payload notEmpty 
		ifTrue: [ connection nextPutAll: payload ].
	connection flush
]

{ #category : 'input/output' }
P3Client >> writeMessage: payload tag: tag [
	connection nextPut: tag asInteger.
	self writeMessage: payload
]

{ #category : 'input/output' }
P3Client >> writeMessageNoFlush: payload [
	| size |
	size := payload size + 4.
	4 to: 1 by: -1 do: [ :index | connection nextPut: (size byteAt: index) ].
	connection nextPutAll: payload.

]

{ #category : 'input/output' }
P3Client >> writeMessageNoFlush: payload tag: tag [
	connection nextPut: tag asInteger.
	self writeMessageNoFlush: payload
]

{ #category : 'private' }
P3Client >> writeQueryMessage: queryString [
	"Write a Query message, the whole of a simple-query request. The message is built in memory first,
	so a failure while encoding queryString leaves the socket untouched. See #sendRequest:."

	| payload |
	payload := (self newMessageBuilder
		nextPutString: queryString;
		yourself) asBytes.
	self sendRequest: [ self writeMessage: payload tag: $Q ].
	extendedRequest := false.
	self logQuery: queryString
]

{ #category : 'input/output' }
P3Client >> writeSyncMessage [
	"Sync on its own, ending an extended-query request and asking the server for one response.
	See #writeExtendedRequest: for the usual case, where it follows the messages it ends."

	self sendRequest: [ self writeMessage: #[] tag: $S ]
]
