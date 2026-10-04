"
I am an abstract test case for reading a P3Client response.

My subclasses break a response in a specific way and then check that the connection is still positioned at the start of the next response. #assertConnectionAnswersItsOwnQueries is the shared check: it sends two queries, because an unread response shifts answers by one, so the first query after the break answers nothing and the second answers the first.

I hold one client, connected in #setUp and closed in #tearDown. Subclasses that need a second connection add their own instance variable and use #newConnectedClient.

Configure the connection through P3ClientTest class >> #url:, like the other tests in this package.
"
Class {
	#name : 'P3ResponseTestCase',
	#superclass : 'TestCase',
	#instVars : [
		'client'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'testing' }
P3ResponseTestCase class >> isAbstract [
	^ self = P3ResponseTestCase
]

{ #category : 'asserting' }
P3ResponseTestCase >> assertConnectionAnswersItsOwnQueries [
	"Send two queries, because an unread response shifts answers by one: the first query after the
	break answers nothing and the second answers the first one's question."

	self assert: (client query: 'SELECT 111') data equals: #( #( 111 ) ).
	self assert: (client query: 'SELECT 222') data equals: #( #( 222 ) )
]

{ #category : 'accessing' }
P3ResponseTestCase >> clients [
	"The clients #closeClients has to close."

	^ { client }
]

{ #category : 'running' }
P3ResponseTestCase >> closeClients [
	"Close every client I opened. A client whose response was left unread can fail while closing,
	which is what my subclasses test for, not a failure of their own. Subclasses that open more
	clients override #clients."

	self clients do: [ :each |
		each ifNotNil: [ [ each close ] on: Error do: [ :error | ] ] ]
]

{ #category : 'private' }
P3ResponseTestCase >> newConnectedClient [
	^ P3Client new
		url: P3ClientTest url;
		timeout: 10;
		connect;
		yourself
]

{ #category : 'running' }
P3ResponseTestCase >> setUp [
	super setUp.
	client := self newConnectedClient
]

{ #category : 'running' }
P3ResponseTestCase >> tearDown [
	self closeClients.
	super tearDown
]
