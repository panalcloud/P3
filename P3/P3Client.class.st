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


Asynchronous notifications (LISTEN/NOTIFY)

#listen: subscribes my session to a channel and #notify:payload: sends on one. I read the NOTIFYs the server sends at any point of any response, or while idle, and queue them as P3ChannelNotification, bounded by #notificationLimit. #takeNotifications takes them without blocking, #waitForNotification: waits for the next one without sending anything, and #notificationHandler: receives them after each request instead. A lost connection is replaced with the same subscriptions, see #restoreListening:. A wait in progress when the connection is lost fails with a P3Error.

As seen through me, PostgreSQL delivers a NOTIFY sent inside a transaction at commit and not at all on rollback, delivers identical channel and payload pairs of one transaction once, delivers transactions in commit order, and delivers a session's own notifications to it.


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
		'notifications',
		'pendingResponses',
		'transactionStatus',
		'discardedError',
		'partialWrite',
		'extendedRequest',
		'transactionLost',
		'connectionGeneration',
		'connectionLost',
		'listeningChannels',
		'droppedNotificationCount',
		'notificationHandler'
	],
	#classInstVars : [
		'unknownTypesAsTextByDefault'
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

{ #category : 'accessing' }
P3Client class >> unknownTypesAsTextByDefault [
	"Whether new clients answer a column of a type without a converter as its text, see P3Client>>#enableUnknownTypesAsText:. False unless set."

	^ unknownTypesAsTextByDefault ifNil: [ false ]
]

{ #category : 'accessing' }
P3Client class >> unknownTypesAsTextByDefault: aBoolean [
	"Set the default of #enableUnknownTypesAsText: for clients that do not set it themselves."

	unknownTypesAsTextByDefault := aBoolean
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
P3Client >> authenticationMethodNameOf: type [
	"The require_auth name of the authentication request type, see #requireAuth:. Nil for an
	AuthenticationOk at the end of an exchange, and for the types I do not support anyway."

	type = #Ok ifTrue: [
		^ (properties includesKey: #'authentication_type') ifTrue: [ nil ] ifFalse: [ 'none' ] ].
	^ { #CleartextPassword -> 'password'. #MD5Password -> 'md5'. #SASL -> 'scram-sha-256' } asDictionary
		at: type
		ifAbsent: [ nil ]
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
	with a P3Error 57014 and leaves my connection usable. I signal when the server cannot be reached.

	The request names my server session, not a statement. Sent when the statement it was meant for has
	just finished, it stops whatever the session runs when it arrives, which can be the next statement.
	So nothing is sent while I owe no response, and a caller should only cancel what it knows is running."

	| stream request |
	(properties includesKey: 'backend_secret_key') ifFalse: [ ^ false ].
	self isResponsePending ifFalse: [ ^ false ].
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
P3Client >> checkChannelName: channelName [
	"Refuse a name the server would refuse or truncate, see #listen:."

	| size |
	channelName isEmptyOrNil ifTrue: [
		^ (P3Error invalidChannelName: channelName reason: 'it is empty') signal ].
	size := self converter encoder encodedByteCountForString: channelName.
	size > 63 ifTrue: [
		^ (P3Error invalidChannelName: channelName reason: ('it takes {1} bytes, at most 63 are kept' format: { size })) signal ]
]

{ #category : 'private' }
P3Client >> checkOutsideTransaction [
	"Refuse LISTEN and UNLISTEN inside a transaction, see #listen:."

	(transactionStatus ifNil: [ $I ]) = $I
		ifFalse: [ P3Error listenInsideTransaction signal ]
]

{ #category : 'private' }
P3Client >> clearSSL [
	settings removeKey: #ssl ifAbsent: [ ]
]

{ #category : 'private' }
P3Client >> clearSession [
	session := nil.
	pendingResponses := 0.
	partialWrite := false.
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
	so the next use says so instead of reconnecting silently. An explicit #close or #connect clears it."

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
	"Connect me to a PostgreSQL database on a new connection. 
	Run the authentication and startup protocols. Configure the session.
	Up to the end of the startup, waiting for the server is bounded by #connectTimeout, then by #timeout.
	See #restoreListening: for what happens to the channels I listened on."

	self critical: [ | replacing |
		replacing := connectionLost.
		self
			open;
			connectInternal;
			clearSSL;
			startReadTimeout;
			logConnected;
			restoreListening: replacing ]
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
	"Connect me to a PostgreSQL database over a new encrypted SSL connection. 
	Run the authentication and startup protocols. Configure the session.
	Up to the end of the startup, waiting for the server is bounded by #connectTimeout, then by #timeout.
	See #restoreListening: for what happens to the channels I listened on."

	self critical: [ | replacing |
		replacing := connectionLost.
		self
			open;
			upgradeToSSL;
			connectInternal;
			setSSL;
			startReadTimeout;
			logConnected;
			restoreListening: replacing ]
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
	"The server keeps at most 63 bytes of a statement name and refuses a name that is in use. A query that
	fits is its own name. A longer one is cut to whole characters and ends in a digest of the entire query,
	so two queries that share their first bytes still get different names. The query is encoded once; the
	cut backs off over UTF-8 continuation bytes, the encoding the startup asks for."

	| bytes digest cut |
	bytes := self converter encoder encodeString: query.
	bytes size <= 63
		ifTrue: [ ^ query ].
	digest := (MD5 hashMessage: bytes) hex.
	cut := 63 - 1 - digest size.
	[ cut > 0 and: [ ((bytes at: cut + 1) bitAnd: 16rC0) = 16r80 ] ]
		whileTrue: [ cut := cut - 1 ].
	^ (self converter encoder decodeBytes: (bytes first: cut)) , '_' , digest
]

{ #category : 'private' }
P3Client >> deliverNotifications [
	"Hand the queued notifications to my #notificationHandler:, in order, once the response that carried
	them is completely read. Only from a request that is not nested in another use of my monitor, so the
	handler never runs in the middle of an operation and can use me itself. A handler failure is logged
	as a P3ErrorOccurredEvent and does not stop the others."

	notificationHandler ifNil: [ ^ self ].
	(access notNil and: [ access isOwnerProcess ]) ifTrue: [ ^ self ].
	self takeNotifications do: [ :each |
		[ notificationHandler value: each ]
			on: Error
			do: [ :error | self logError: error ] ]
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

{ #category : 'protocol' }
P3Client >> discardUnsolicitedMessages [
	"Read what the server sent while no response was owed. Notices, parameter status and notifications
	can come at any time and are processed. An ErrorResponse means the server ended the session, as on a
	restart, an idle timeout or pg_terminate_backend, before it read anything more from me: keep it as
	#discardedError and close as a failure, so the next request opens a new session or reports a lost
	transaction. Anything else means the stream is out of step, so close too. This does not block."

	[ [ connection notNil and: [ connection isDataAvailable ] ] whileTrue: [
		message readFrom: connection.
		self isAsynchronousMessage
			ifTrue: [ self processAsynchronousMessage ]
			ifFalse: [
				message tag = $E ifTrue: [ self noteDiscardedError ].
				^ self closeAfterFailure ] ] ]
		on: Error
		do: [ :error | self closeAfterFailure ]
]

{ #category : 'accessing' }
P3Client >> discardedError [
	"The first ErrorResponse I read while discarding a response, if any. Nobody was waiting for it, so
	it is kept here for inspection instead of being signalled. Cleared by #reset."

	^ discardedError
]

{ #category : 'notifications' }
P3Client >> droppedNotificationCount [
	"How many notifications my queue dropped because it was full, see #notificationLimit. It only grows: a
	consumer that sees it change has missed notifications and has to resynchronise."

	^ droppedNotificationCount
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
	"Open my connection when it is not open. A connection that is still there but no longer works is
	closed as a failure first, so a transaction open on it is remembered as lost, see #closeAfterFailure.
	Refuse to reconnect after a connection was lost inside a transaction. The error the server sent
	when it ended the session, if any, is the detail of that refusal.

	A connection that was lost outside a transaction is replaced, unless autoReconnect is off: then
	I signal and wait for an explicit #connect. A replacement is a new server session, so I signal
	P3ConnectionReplaced after it is open. A first connect, or one after an explicit #close, is neither."

	| replacing |
	self isConnected ifTrue: [ ^ self ].
	self closeAfterFailure.
	transactionLost ifTrue: [ | error |
		error := P3Error connectionLostInTransaction.
		discardedError ifNotNil: [ error info at: $D put: discardedError messageText ].
		^ error signal ].
	replacing := connectionGeneration > 0 and: [ connectionLost ].
	(replacing and: [ self autoReconnect not ])
		ifTrue: [ ^ P3Error connectionLost signal ].
	self isSSL
		ifTrue: [ self connectSSL ]
		ifFalse: [ self connect ].
	replacing ifTrue: [ P3ConnectionReplaced signal ]
]

{ #category : 'protocol' }
P3Client >> ensureResponseRead [
	"Before asking for a new response, make sure the previous one was read. A response left unread
	would be answered to the next request, so discard it rather than let it be mistaken for mine.
	A request whose writing was interrupted left bytes that are not a message: nothing written after
	them can be read by the server, so close. Then read what the server sent on its own, see
	#discardUnsolicitedMessages."

	partialWrite ifTrue: [ ^ self closeAfterFailure ].
	self isResponsePending ifTrue: [ self discardResponseOrClose ].
	self discardUnsolicitedMessages
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

	A timeout that stopped between two messages leaves the connection in step, and the server may still be
	running the statement: ask it to stop with #cancel, then read what it sends back, so the connection stays
	usable. When that is the error of a cancelled statement, the timeout is passed on: the statement did not
	run. When the statement had finished before the cancel arrived, its response says so, and reporting a
	timeout would tell the caller that it did not run: I signal that it completed, or the error it failed with.
	Every other failure, and a timeout inside a message, cannot be read on, so I close."

	| previous outcome |
	(aNetworkError isKindOf: ConnectionTimedOut)
		ifFalse: [ ^ self closeAfterFailure ].
	message isPartial ifTrue: [ ^ self closeAfterFailure ].
	([ self cancel ] on: Error do: [ :error | false ])
		ifFalse: [ ^ self closeAfterFailure ].
	previous := discardedError.
	discardedError := nil.
	self discardResponseOrClose.
	outcome := discardedError.
	discardedError := outcome ifNil: [ previous ].
	self isConnected ifFalse: [ ^ self ].
	outcome ifNil: [ ^ P3Error statementCompletedAfterTimeout signal ].
	outcome code = '57014' ifTrue: [ ^ self ].
	^ (P3Error new info: outcome info; yourself) signal
]

{ #category : 'private - authentication' }
P3Client >> handleAuthentication: code [
	"Answer the authentication request code of the server, after checking that I accept its method. An
	AuthenticationOk that ends an exchange needs no check; one that comes first means no authentication."

	| type method |
	type := self authenticationTypes 
		at: code 
		ifAbsent: [ (P3Error unsupportedAuthenticationType: code) signal ].
	method := self authenticationMethodNameOf: type.
	(method notNil and: [ (self isAuthenticationAllowed: method) not ])
		ifTrue: [
			self close.
			^ (P3Error authenticationNotAllowed: method) signal ].
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

{ #category : 'notifications' }
P3Client >> hasNotifications [
	"Are notifications queued that were not taken yet? This does not read from the connection."

	^ self critical: [ notifications notEmpty ]
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

{ #category : 'initialize-release' }
P3Client >> initialize [
	super initialize.
	
	settings := IdentityDictionary new.
	properties := Dictionary new.
	notifications := OrderedCollection new.
	listeningChannels := Set new.
	droppedNotificationCount := 0.
	pendingResponses := 0.
	partialWrite := false.
	extendedRequest := false.
	transactionLost := false.
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
P3Client >> isAuthenticationAllowed: methodName [
	"Do I accept the authentication method methodName, see #requireAuth:?"

	^ self requireAuth
		ifNil: [ methodName ~= 'password' or: [ self isEncrypted ] ]
		ifNotNil: [ :names | names includes: methodName ]
]

{ #category : 'testing' }
P3Client >> isConnected [
	"Return true when my connection is in working order (from my end)"

	^ connection notNil
			and: [ connection isConnected 
				and: [ session notNil ] ]
]

{ #category : 'testing' }
P3Client >> isEncrypted [
	"Is my connection, if any, using TLS?"

	^ connection isKindOf: ZdcSecureSocketStream
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
	^ settings at: #unknownTypesAsText ifAbsent: [ self class unknownTypesAsTextByDefault ]
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

{ #category : 'convenience' }
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

{ #category : 'notifications' }
P3Client >> listen: channelName [
	"Subscribe my session to channelName, so NOTIFYs sent on it reach me, see #waitForNotification: and
	#takeNotifications. The name is sent as a quoted identifier: case, spaces and quotes are part of it.
	It must not be empty nor longer than 63 bytes in the connection encoding, which the server would
	truncate here while pg_notify refuses it.

	Refused inside a transaction: the registration only takes effect at commit, so a rollback would undo
	it while #listeningChannels still lists it. A replacement connection listens again, see
	#restoreListening:."

	self checkChannelName: channelName.
	self critical: [
		self checkOutsideTransaction.
		self execute: 'LISTEN ' , (self quotedIdentifier: channelName).
		listeningChannels add: channelName.
		self logListen: #listen channel: channelName ]
]

{ #category : 'notifications' }
P3Client >> listeningChannels [
	"The channels my session subscribed to through #listen:, as a copy. A LISTEN sent as plain SQL is not
	tracked here, so it is neither restored on a new connection nor listed."

	^ self critical: [ listeningChannels copy ]
]

{ #category : 'configuration' }
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
	P3LogEvent hasSubscribers ifFalse: [ ^ self ].
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
P3Client >> logListen: actionSymbol channel: channelNameOrNil [
	(self newLogEvent: P3ListenEvent)
		action: actionSymbol channel: channelNameOrNil;
		emit
]

{ #category : 'private - logging' }
P3Client >> logListenRestored: channels [
	(self newLogEvent: P3ListenRestoredEvent)
		channels: channels;
		emit
]

{ #category : 'private - logging' }
P3Client >> logNotification: aChannelNotification [
	P3LogEvent hasSubscribers ifFalse: [ ^ self ].
	(self newLogEvent: P3NotificationReceivedEvent)
		notification: aChannelNotification;
		emit
]

{ #category : 'private - logging' }
P3Client >> logNotificationDropped [
	P3LogEvent hasSubscribers ifFalse: [ ^ self ].
	(self newLogEvent: P3NotificationsDroppedEvent)
		droppedCount: droppedNotificationCount limit: self notificationLimit;
		emit
]

{ #category : 'private - logging' }
P3Client >> logPreparedStatement: statement query: query [
	P3LogEvent hasSubscribers ifFalse: [ ^ self ].
	(self newLogEvent: P3StatementPreparedEvent)
		statement: statement;
		query: query;
		emit
]

{ #category : 'private - logging' }
P3Client >> logQuery: query [
	P3LogEvent hasSubscribers ifFalse: [ ^ self ].
	(self newLogEvent: P3QueryWrittenEvent)
		query: query;
		emit.
	properties at: #query_started ifAbsentPut: Time millisecondClockValue
]

{ #category : 'private - logging' }
P3Client >> logResult: result [
	"The start of the request is removed in any case, so that a later result is not timed from it"

	| duration |
	P3LogEvent hasSubscribers ifFalse: [ ^ properties removeKey: #query_started ifAbsent: [ ] ].
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
	"A new socket stream to the server, not yet speaking the protocol, with TCP keepalive on. Reaching the
	server and its handshake are bounded by #connectTimeout, see #connect for when #timeout takes over."

	| stream |
	stream := self isUsingUnixSocket
		ifTrue: [ ZdcSocketStream on: (ZnNetworkingUtils default unixSocketOnFile: self unixSocketFile) ]
		ifFalse: [
			self newTcpSocketStream in: [ :tcp |
				tcp socket setOption: 'SO_KEEPALIVE' value: true.
				tcp ] ].
	stream timeout: self connectTimeout.
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
P3Client >> nextNotificationWaitingAtMost: milliseconds first: isFirst [
	"One slice of #waitForNotification:, under my monitor. Answer the oldest queued notification, reading
	what the server sent and then waiting at most milliseconds for more when none is queued. Nil when
	still none."

	notifications ifNotEmpty: [ ^ notifications removeFirst ].
	self readNotificationsWhileWaiting: isFirst.
	(notifications isEmpty and: [ milliseconds > 0 ]) ifTrue: [
		self waitForDataAtMost: milliseconds.
		self readNotificationsWhileWaiting: false ].
	^ self takeNextNotification
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

{ #category : 'notifications' }
P3Client >> notificationHandler [
	"See #notificationHandler:."

	^ notificationHandler
]

{ #category : 'notifications' }
P3Client >> notificationHandler: aBlockOrNil [
	"Hand each notification to aBlockOrNil, a one argument block, instead of keeping it queued. It runs in
	the process that made the request whose response carried the notification, after that response
	is read completely, and may use me. Its errors are logged as P3ErrorOccurredEvent and not passed on.

	Each notification is answered once: #waitForNotification: and #takeNotifications take it first when
	they run before the request ends. Nil, the default, keeps notifications queued."

	notificationHandler := aBlockOrNil
]

{ #category : 'notifications' }
P3Client >> notificationLimit [
	"How many notifications my queue keeps, default 10000. Beyond that the oldest is dropped and counted,
	see #droppedNotificationCount."

	^ settings at: #notificationLimit ifAbsent: [ 10000 ]
]

{ #category : 'notifications' }
P3Client >> notificationLimit: anInteger [
	"See #notificationLimit. A queue already longer is trimmed when the next notification arrives."

	(anInteger isInteger and: [ anInteger > 0 ])
		ifFalse: [ ^ self error: 'The notification limit must be a positive integer' ].
	settings at: #notificationLimit put: anInteger
]

{ #category : 'accessing' }
P3Client >> notifications [
	"The NOTIFYs queued while reading, oldest first, without taking them. See #takeNotifications and
	#waitForNotification: to consume them. The queue is bounded by #notificationLimit."

	^ self critical: [ notifications asArray ]
]

{ #category : 'notifications' }
P3Client >> notify: channelName payload: aString [
	"Send a NOTIFY on channelName with aString as payload, through pg_notify with both as parameters, so
	neither is ever part of the SQL text. Inside a transaction it is delivered at commit, and not at all on
	rollback. The server refuses an empty or too long channel name and a payload of 8000 bytes or more."

	(self prepare: 'SELECT pg_notify($1, $2)') execute: { channelName. aString }
]

{ #category : 'initialize-release' }
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
	#defaultStatementNameFor:. Preparing a query that is already prepared answers that statement, so both
	holders share it and closing it closes it for both. When it was prepared in a session that is gone, it
	is prepared again first."

	| name existing |
	name := self defaultStatementNameFor: query.
	existing := properties
		at: 'prepared_statements'
		ifPresent: [ :preparedStatements | preparedStatements at: name ifAbsent: [ nil ] ]
		ifAbsent: [ nil ].
	(existing notNil and: [ existing source = query ])
		ifFalse: [ ^ self prepare: query named: name ].
	self critical: [
		self ensureResponseRead; ensureConnected.
		self prepareStaleStatement: existing ].
	^ existing
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
P3Client >> prepareStaleStatement: aPreparedStatement [
	"Make sure aPreparedStatement exists in my current server session. A new connection is a new session
	and the server forgot everything prepared in the old one, so prepare its source again under its name.
	The statement object stays the one the caller holds and takes over what the server describes now, and
	it is the one registered under its name. When the name was already prepared again in this session for
	the same source, that preparation is taken over instead of preparing the name twice."

	| registry existing |
	aPreparedStatement isStale ifFalse: [ ^ self ].
	registry := properties at: 'prepared_statements' ifAbsentPut: [ Dictionary new ].
	existing := registry at: aPreparedStatement name ifAbsent: [ nil ].
	(existing notNil and: [ existing ~~ aPreparedStatement and: [ existing isStale not
		and: [ existing source = aPreparedStatement source ] ] ])
		ifFalse: [ existing := self prepare: aPreparedStatement source named: aPreparedStatement name ].
	aPreparedStatement adoptPreparationOf: existing.
	registry at: aPreparedStatement name put: aPreparedStatement
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
P3Client >> processDataRowUsing: descriptions converters: converters [
	"Read the DataRow I am positioned on. A NULL value, length -1, is not converted."

	| count record readStream |
	readStream := message readStream.
	count := readStream uint16.
	record := Array new: count.
	1 to: count do: [ :index | | size |
		size := readStream uint32.
		size = 16rFFFFFFFF
			ifFalse: [
				record
					at: index
					put: (converter
						convert: readStream
						length: size
						using: (converters at: index)
						description: (descriptions at: index)) ] ].
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
	"Queue the NOTIFY I am positioned on. The server delivers it once, so discarding it would lose its
	payload. The queue is bounded by #notificationLimit: the oldest notifications are dropped first and
	counted in #droppedNotificationCount. See #takeNotifications."

	| payload notification |
	payload := message readStream.
	notification := P3ChannelNotification
		processId: payload uint32
		channel: (self converter encodedCStringFrom: payload)
		payload: (self converter encodedCStringFrom: payload).
	notifications addLast: notification.
	self logNotification: notification.
	[ notifications size > self notificationLimit ] whileTrue: [
		notifications removeFirst.
		droppedNotificationCount := droppedNotificationCount + 1.
		self logNotificationDropped ]
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
	"Record a server parameter, and tell the converter: the session time zone decides how values without a zone are read.
	The value is text in the connection encoding, like a role name in session_authorization."
	
	| key value |
	
	key := self converter asciiCStringFrom: payload.
	value := self converter encodedCStringFrom: payload.
		
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
P3Client >> quotedIdentifier: aString [
	"aString as an SQL quoted identifier: between double quotes, with each double quote doubled."

	^ String streamContents: [ :out |
		out nextPut: $".
		aString do: [ :each |
			each = $" ifTrue: [ out nextPut: $" ].
			out nextPut: each ].
		out nextPut: $" ]
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
	first message that is not one. Answer them converted through descriptions. The converter of each
	column is chosen once for all the rows, see P3Converter>>#converterFor:."

	| converters |
	descriptions ifNil: [ ^ self rejectOutOfStepMessage ].
	converters := descriptions collect: [ :each | converter converterFor: each ].
	^ Array streamContents: [ :out |
		[ message tag = $D ] whileTrue: [
			out nextPut: (self processDataRowUsing: descriptions converters: converters).
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

{ #category : 'input/output' }
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

{ #category : 'private' }
P3Client >> readNotificationsWhileWaiting: isFirst [
	"Read what the server sent, under my monitor, for #waitForNotification:. Its first read connects as a
	request does. A later one finding the connection gone signals instead: the session ended during the
	wait, and a silent replacement would hide the notifications lost with it."

	| previousError |
	previousError := discardedError.
	self ensureResponseRead.
	isFirst ifTrue: [ ^ self ensureConnected ].
	self isConnected ifTrue: [ ^ self ].
	self closeAfterFailure.
	^ (P3Error connectionLostWhileWaiting: (discardedError == previousError
		ifFalse: [ discardedError ifNotNil: [ :error | error messageText ] ])) signal
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
	starts, so my connection cannot be positioned: close it rather than read on."

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

{ #category : 'accessing' }
P3Client >> requireAuth [
	"The authentication methods I accept, or nil for the default, see #requireAuth:."

	^ settings at: #requireAuth ifAbsent: [ nil ]
]

{ #category : 'initialize-release' }
P3Client >> requireAuth: methodNames [
	"Accept only these authentication methods, named as in libpq's require_auth: password (a cleartext
	password), md5, scram-sha-256 and none (the server asks for nothing). A server that asks for another
	method fails the connect before anything is sent. Nil, the default, accepts any method I support except
	a cleartext password on a connection without TLS."

	methodNames ifNotNil: [
		methodNames do: [ :each |
			(#( 'password' 'md5' 'scram-sha-256' 'none' ) includes: each)
				ifFalse: [ ^ (P3Error authenticationNotAllowed: each) signal ] ] ].
	settings at: #requireAuth put: methodNames
]

{ #category : 'private' }
P3Client >> reset [
	self clearSession.
	properties removeAll.
	discardedError := nil.
	converter := nil
]

{ #category : 'private' }
P3Client >> restoreListening: replacing [
	"A new session has no LISTEN registrations. When it replaces one that was lost, issue LISTEN again for
	#listeningChannels, in one request, before anything else uses it, and announce P3ListenRestoredEvent:
	notifications sent meanwhile are lost. After a first connect or an explicit #close, forget them."

	| channels |
	replacing ifFalse: [ ^ listeningChannels removeAll ].
	listeningChannels ifEmpty: [ ^ self ].
	channels := listeningChannels asArray.
	self execute: (String streamContents: [ :out |
		channels
			do: [ :each | out nextPutAll: 'LISTEN '; nextPutAll: (self quotedIdentifier: each) ]
			separatedBy: [ out nextPutAll: '; ' ] ]).
	self logListenRestored: channels
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
P3Client >> runRequest: writeBlock response: readBlock [
	"Write one request and read its response as a single unit. Every request goes through here.

	The monitor is held for both halves, so another process cannot place its own request between my
	write and my read. A response nobody read is drained before a new one is asked for, and only then
	is the connection checked: a drain that has to close would otherwise leave the request written to
	nothing.

	A network failure before the server received the request is retried on a fresh connection,
	because nothing ran. Once the request is sent, a network failure is not retried, see
	#readResponse:, running it again could execute it twice. The delay between retries is waited
	outside the monitor, so other processes can use me meanwhile.

	Once the response is read, queued notifications go to the #notificationHandler:, if any."

	| remaining result |
	remaining := self retryCount.
	[ result := self critical: [
			self attemptRequest: writeBlock response: readBlock canRetry: remaining > 0 ].
	result == #retry ] whileTrue: [
		remaining < self retryCount ifTrue: [
			self logRetryConnection: remaining.
			self retryDelay seconds wait ].
		remaining := remaining - 1 ].
	self deliverNotifications.
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
	session := 999999 atRandom. "Sometimes $K is not sent and we need a nonNil session"
	[
	self readMessageCloseAfterError tag = $Z
		ifTrue: [ ^ self ].
	message tag = $K
		ifTrue: [ self processBackendKeyData: message readStream ]
		ifFalse: [ ^ P3Error unexpectedMessageDuringStartup signal ] ] repeat
]

{ #category : 'private' }
P3Client >> runStatement: aPreparedStatement inputRows: inputRows [
	"Execute aPreparedStatement once per row of inputRows in one extended-query request, and answer one
	P3Result per row. Each attempt first makes sure the statement exists in the current session, so a retry
	on a new connection prepares it there before executing it. The Bind and Execute messages are then built
	in memory and sent together, ended by Sync. The source and the bound values are recorded under the
	monitor, once the request is sent, so another process cannot change them between my write and my read."

	^ self
		runRequest: [ | messages |
			self prepareStaleStatement: aPreparedStatement.
			messages := aPreparedStatement requestMessagesFor: inputRows.
			properties at: #sql_source put: aPreparedStatement source.
			self writeExtendedRequest: messages.
			inputRows do: [ :each | self logBinding: aPreparedStatement inputValues: each ] ]
		response: [ self basicRunExtendedQueryResults: aPreparedStatement fieldDescriptions ]
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
	"Write one complete request by evaluating aBlock, the server owes me one response for it.

	The response is noted as owed before the first byte is written, and the write is marked partial until
	aBlock returns. A process terminated in between runs no handler, so the next request finds either a
	response to discard or a broken message on the socket, which only closing removes. A failure while
	writing closes for the same reason, see #ensureResponseRead."

	self noteResponseRequested.
	partialWrite := true.
	[ aBlock value ] on: Error do: [ :error | self closeAfterFailure. error pass ].
	partialWrite := false
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

{ #category : 'private' }
P3Client >> startReadTimeout [
	"The session is established: from now on waiting for the server is bounded by #timeout."

	connection timeout: self timeout
]

{ #category : 'private messages' }
P3Client >> startupMessage [
	"The client_encoding is requested, whatever the role or the database default is, because I decode
	what the server sends as UTF-8 until it reports another encoding. DateStyle and IntervalStyle are
	requested because the converter reads only the ISO and postgres styles, and extra_float_digits so that
	floats are written with all their digits. An application that wants others can say so in the options."

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

{ #category : 'private' }
P3Client >> takeNextNotification [
	"Remove and answer the oldest queued notification, nil when none. Under my monitor."

	^ notifications isEmpty
		ifTrue: [ nil ]
		ifFalse: [ notifications removeFirst ]
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
	"Return the timeout in seconds I (want to) use when waiting for the server once connected, the default
	being 10 seconds. A statement that takes longer is cancelled and the connection kept, see #giveUpReading:.
	Reaching the server is bounded by #connectTimeout. For long running work, raise this and let
	#statementTimeout: bound statements on the server."
	
	^ settings at: #timeout ifAbsentPut: [ 10 ]
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

{ #category : 'notifications' }
P3Client >> unlisten: channelName [
	"Unsubscribe my session from channelName. Notifications already received stay queued.
	See #listen: for the name and the transaction rules."

	self checkChannelName: channelName.
	self critical: [
		self checkOutsideTransaction.
		self execute: 'UNLISTEN ' , (self quotedIdentifier: channelName).
		listeningChannels remove: channelName ifAbsent: [ ].
		self logListen: #unlisten channel: channelName ]
]

{ #category : 'notifications' }
P3Client >> unlistenAll [
	"Unsubscribe my session from every channel, including ones subscribed with plain SQL.
	Notifications already received stay queued. Refused inside a transaction, see #listen:."

	self critical: [
		self checkOutsideTransaction.
		self execute: 'UNLISTEN *'.
		listeningChannels removeAll.
		self logListen: #unlistenAll channel: nil ]
]

{ #category : 'protocol' }
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

{ #category : 'initialize-release' }
P3Client >> url: stringOrUrl [
	"Set my connection settings from stringOrUrl according to the format
	postgresql://username:password@localhost:5432/databasename?sslmode=require
	with the minimum being psql://user@localhost , for a unix socket the format is
	postgresql:///databasename?host=/path/to/psql.socket&user=username&password=password
	The sslmode is either disable, the default, or require. Any other value signals a P3Error,
	see #sslModeOf:. require_auth is a comma separated list, see #requireAuth:."
	
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
	url queryAt: #options ifPresent: [ :options | self startupOptions: options ].
	url queryAt: #require_auth ifPresent: [ :methods | self requireAuth: ($, split: methods) asArray ]
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
P3Client >> waitForDataAtMost: milliseconds [
	"Block until the socket has data, is closed, or milliseconds passed, without reading. Under my monitor,
	see #waitForNotification:. Bytes already buffered by the stream do not count:
	#readNotificationsWhileWaiting: read those before."

	connection ifNotNil: [ :stream |
		stream socket ifNotNil: [ :socket |
			socket
				waitForDataFor: milliseconds / 1000
				ifClosed: [ ]
				ifTimedOut: [ ] ] ]
]

{ #category : 'notifications' }
P3Client >> waitForNotification: seconds [
	"Answer the oldest queued notification and remove it from the queue. When none is queued, wait at
	most seconds for one, reading from the connection without sending anything, and answer nil on timeout.

	The wait holds my monitor for slices of at most 100 milliseconds and releases it in between, so other
	processes can use me meanwhile, waiting at most one slice, and a notification their requests read is
	answered too. The socket is only waited on under the monitor: the socket has one read semaphore, and a
	waiter outside the monitor would take the wakeup of a process reading a response. The waiting process
	can be terminated.

	A connection lost before the wait is replaced as for any request, see #ensureConnected, and listens
	again, see #restoreListening:. A connection lost during the wait, for example by pg_terminate_backend
	or a server shutdown, ends it with a P3Error (P3072)."

	| deadline isFirst |
	deadline := Time millisecondClockValue + (seconds * 1000) rounded.
	isFirst := true.
	[ (self critical: [
			self
				nextNotificationWaitingAtMost: ((deadline - Time millisecondClockValue) min: 100)
				first: isFirst ]) ifNotNil: [ :notification | ^ notification ].
	isFirst := false.
	Time millisecondClockValue < deadline ] whileTrue.
	^ nil
]

{ #category : 'notifications' }
P3Client >> waitForNotifications: seconds [
	"Answer every queued notification and empty the queue. When none is queued, wait at most seconds for
	the first one as #waitForNotification: does, and answer it with those that came along. Empty on timeout."

	^ (self waitForNotification: seconds)
		ifNil: [ #() ]
		ifNotNil: [ :first | { first } , self takeNotifications ]
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

{ #category : 'input/output' }
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
