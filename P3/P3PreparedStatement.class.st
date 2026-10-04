"
I am P3PreparedStatement. Use me if you need to execute a query multiple times.

Create an instance of me via P3Client>>#prepare: The argument to this method is a query string that can contain one or more placeholders. When executing the statement an array should be provided with a value for each placeholder.

Examples:

Prepare an insert statement and execute it two times with different parameters:

	statement := client prepare: 'INSERT INTO table1 (id, name, enabled) VALUES ($1,$2,$3)'.
	result := statement execute: #( 123 'Hello World' true ).
	result := statement execute: #( 45 'Greetings' false ).

It's also possible to execute the two inserts in a single network roundtrip:

	statement := client prepare: 'INSERT INTO table1 (id, name, enabled) VALUES ($1,$2,$3)'.
	results := statement executeBatch: #( 
		( 123 'Hello World' true )
		( 45 'Greetings' false ) ).

Select query:

	statement := client prepare: 'SELECT name, enabled FROM table1 WHERE id = $1'.
	result := statement query: #( 123 ).

When I'm no longer needed I should be closed so that the PostgreSQL server side resources for this prepared statement are freed.

See also https://en.wikipedia.org/wiki/Prepared_statement

A prepared statement can be more efficient, especially if it is used multiple times. Prepared statements are also resilient against SQL injection attacks. On the server, prepared statements are bound to the current session.

My API and the syntax that I use ($n) is mostly polymorphic with P3FormattedStatement. The difference is that I do much more than textual processing: my SQL template is actually parsed on the server, checking the syntax and partially planning the execution, during the actual execution phase, just the concrete argument values are transferred, taking advantage of some of the work that has already been done on the server.
 

"
Class {
	#name : 'P3PreparedStatement',
	#superclass : 'Object',
	#instVars : [
		'client',
		'name',
		'paramDescriptions',
		'fieldDescriptions',
		'source',
		'generation'
	],
	#category : 'P3-Core',
	#package : 'P3',
	#tag : 'Core'
}

{ #category : 'instance creation' }
P3PreparedStatement class >> newWith: aClient name: aString parameters: paramDescriptions fields: rowDescriptions [

	^ self new initializeWith: aClient name: aString parameters: paramDescriptions fields: rowDescriptions
]

{ #category : 'private' }
P3PreparedStatement >> adoptPreparationOf: aFreshStatement [
	"Take over what the server described when it prepared my source again."

	paramDescriptions := aFreshStatement paramDescriptions.
	fieldDescriptions := aFreshStatement fieldDescriptions.
	generation := aFreshStatement generation
]

{ #category : 'private' }
P3PreparedStatement >> bindMessageFor: inputValues [
	"The Bind message for one row of parameters, as a tag -> payload association. Building it can fail
	on any value, which is why it is built in memory and not written to the socket. See
	P3Client>>#writeExtendedRequest:. It changes nothing outside of itself."

	| msgBuilder |

	msgBuilder := client newMessageBuilder.
	msgBuilder
		nextPutString: '';
		nextPutString: name;
		nextPutInt16: 0;
		nextPutInt16: inputValues size.

	inputValues
		with: paramDescriptions
		do: [ :eachValue :paramDescription | 
			eachValue
				ifNil: [ msgBuilder nextPutNullParameter ]
				ifNotNil: [ msgBuilder nextPutParameterAsText: eachValue description: paramDescription ] ].

	msgBuilder nextPutInt16: 0. "All result columns use the text format"

	^ $B -> msgBuilder asBytes
]

{ #category : 'public' }
P3PreparedStatement >> close [
	"Close this query and release server side resources.
	When my server session is gone, so am I on the server: nothing is sent, and no connection is opened for it."

	client ifNil: [ ^ self ].

	(client isConnected and: [ self isStale not ])
		ifTrue: [ client runCloseStatementNamed: name ].

	"This prepared statement can no longer be used."
	client forgetPreparedStatementNamed: name.
	client := nil
]

{ #category : 'accessing' }
P3PreparedStatement >> converter [ 
	^ client converter
]

{ #category : 'public' }
P3PreparedStatement >> execute: inputRow [
	"Execute this SQL query with inputRow as the ordered collection of parameters.
	Assume no rows will be returned."

	^ (self runInputRows: { inputRow }) first result
]

{ #category : 'public' }
P3PreparedStatement >> executeBatch: inputRows [
	"Execute this SQL query multiple (inputRow size) times in a single network roundtrip.
	Assume no rows will be returned."

	inputRows isEmpty
		ifTrue: [ ^ #() ].

	^ (self runInputRows: inputRows) collect: [ :each | each result ]
]

{ #category : 'private' }
P3PreparedStatement >> executeMessage [
	"The Execute message for my portal with no row limit, as a tag -> payload association."

	^ $E -> (client newMessageBuilder
		nextPutString: '';
		nextPutInt32: 0;
		yourself) asBytes
]

{ #category : 'accessing' }
P3PreparedStatement >> fieldCount [
	^ fieldDescriptions size
]

{ #category : 'accessing' }
P3PreparedStatement >> fieldDescriptions [
	^ fieldDescriptions
]

{ #category : 'accessing' }
P3PreparedStatement >> generation [
	"The connection generation of my client in which I was prepared on the server."

	^ generation
]

{ #category : 'initialization' }
P3PreparedStatement >> initializeWith: aClient name: aString parameters: aParamDescriptions fields: aRowFieldDescriptions [

	client := aClient.
	name := aString.
	paramDescriptions := aParamDescriptions.
	fieldDescriptions := aRowFieldDescriptions.
	generation := aClient connectionGeneration
]

{ #category : 'private' }
P3PreparedStatement >> isStale [
	"Was I prepared in a server session that is gone? The server forgot me with it."

	^ client notNil and: [ generation ~= client connectionGeneration ]
]

{ #category : 'accessing' }
P3PreparedStatement >> name [
	^ name
]

{ #category : 'accessing' }
P3PreparedStatement >> paramCount [
	^ paramDescriptions size
]

{ #category : 'accessing' }
P3PreparedStatement >> paramDescriptions [
	^ paramDescriptions
]

{ #category : 'printing' }
P3PreparedStatement >> printOn: stream [
	super printOn: stream.
	stream nextPut: $(; << name; nextPut: $)
]

{ #category : 'public' }
P3PreparedStatement >> query: inputRow [
	"Execute this SQL query with inputRow as the ordered collection of parameters.
	Answer a P3Result object with the field descriptions and rows."

	^ (self runInputRows: { inputRow }) first
]

{ #category : 'public' }
P3PreparedStatement >> queryAll: inputRows [
	"Execute this SQL query multiple times.
	Answer a collection of P3Result objects with the field descriptions and rows."

	inputRows isEmpty
		ifTrue: [ ^ #() ].

	^ self runInputRows: inputRows
]

{ #category : 'private' }
P3PreparedStatement >> runInputRows: inputRows [
	"Execute me once per row of inputRows in a single request, and answer one P3Result per row.
	The whole request is built before anything is written, so a row that cannot be bound leaves the
	connection as it was instead of executing the rows before it. If my server session was replaced,
	I am prepared again first. Nothing shared is touched until the client runs the request under its
	monitor."

	| messages |
	client ifNil: [ ^ (P3Error statementClosed: name) signal ].
	client prepareAgain: self.
	messages := Array streamContents: [ :out |
		inputRows do: [ :each |
			out
				nextPut: (self bindMessageFor: each);
				nextPut: self executeMessage ] ].
	^ client
		runExtendedRequest: messages
		fieldDescriptions: fieldDescriptions
		statement: self
		inputRows: inputRows
]

{ #category : 'accessing' }
P3PreparedStatement >> source [
	"Return my SQL source"
	
	^ source
]

{ #category : 'accessing' }
P3PreparedStatement >> source: anSQLTemplateString [
	source := anSQLTemplateString
]
