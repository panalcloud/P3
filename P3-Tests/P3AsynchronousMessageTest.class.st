"
I test how P3Client reads NotificationResponse ($A) and ParameterStatus ($S) messages that arrive where the response reading loops do not expect them.

P3Client>>runQueryResult accepts at most one $S between CommandComplete and ReadyForQuery and does not know $A at all. Any other message there falls through to the data reading branch, which then reads ReadyForQuery as if it were a DataRow and fails its assertion. The connection is left with the response unread, so later queries answer earlier ones.

I produce both cases from SQL, without touching the converter:
- LISTEN on my client plus NOTIFY from a second connection makes the server send $A just before ReadyForQuery.
- SET on several reported parameters followed by RESET ALL makes it send one $S per parameter.

Configure the connection through P3ClientTest class >> #url:, like the other tests in this package.
"
Class {
	#name : 'P3AsynchronousMessageTest',
	#superclass : 'P3ResponseTestCase',
	#instVars : [
		'notifier'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3AsynchronousMessageTest >> channelName [
	^ 'p3_asynchronous_message_test'
]

{ #category : 'accessing' }
P3AsynchronousMessageTest >> clients [
	^ super clients , { notifier }
]

{ #category : 'private' }
P3AsynchronousMessageTest >> listenOnClient [
	"Make the server send NotificationResponse to my client when notifier notifies."

	client execute: 'LISTEN ' , self channelName
]

{ #category : 'private' }
P3AsynchronousMessageTest >> notifyFromOtherConnection [
	"Notify from a second connection, so the notification is queued for my client and delivered
	with the answer to its next query."

	notifier execute: 'NOTIFY ' , self channelName , ', ''payload'''
]

{ #category : 'private' }
P3AsynchronousMessageTest >> reportSeveralParameters [
	"Change several parameters the server reports, then reset them in one statement, so its
	response carries one ParameterStatus per parameter."

	#( 'SET TIME ZONE ''UTC'''
	   'SET DateStyle TO ''Postgres, DMY'''
	   'SET IntervalStyle TO ''iso_8601'''
	   'SET search_path TO pg_catalog' )
		do: [ :each | client execute: each ].
	client execute: 'RESET ALL'
]

{ #category : 'running' }
P3AsynchronousMessageTest >> setUp [
	super setUp.
	notifier := self newConnectedClient
]

{ #category : 'tests' }
P3AsynchronousMessageTest >> testConnectionAnswersItsOwnQueriesAfterANotification [
	self listenOnClient.
	self notifyFromOtherConnection.
	[ client query: 'SELECT 1' ] on: Error do: [ :error | ].
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests' }
P3AsynchronousMessageTest >> testConnectionAnswersItsOwnQueriesAfterSeveralParameterStatus [
	[ self reportSeveralParameters ] on: Error do: [ :error | ].
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests' }
P3AsynchronousMessageTest >> testNotificationIsKept [
	"A notification carries a payload that arrives only once, so reading it must keep it rather
	than discard it."

	| notification |
	self listenOnClient.
	self notifyFromOtherConnection.
	client query: 'SELECT 111'.
	self assert: client notifications size equals: 1.
	notification := client notifications first.
	self assert: notification channel equals: self channelName.
	self assert: notification payload equals: 'payload'
]

{ #category : 'tests' }
P3AsynchronousMessageTest >> testQueryDeliveringANotification [
	"The query the notification arrives with must still answer its own question."

	self listenOnClient.
	self notifyFromOtherConnection.
	self assert: (client query: 'SELECT 111') data equals: #( #( 111 ) )
]

{ #category : 'tests' }
P3AsynchronousMessageTest >> testStartupParametersAreRecorded [
	"The server sends its parameters as ParameterStatus messages while connecting. Those are
	consumed by #readMessageOnError: like any other asynchronous message, so they must still reach
	the properties my client answers from."

	self deny: client serverVersion isEmptyOrNil.
	self deny: client serverEncoding isEmptyOrNil.
	self deny: client serverTimezone isEmptyOrNil
]

{ #category : 'tests' }
P3AsynchronousMessageTest >> testStatementReportingSeveralParameters [
	"RESET ALL answers one ParameterStatus per reported parameter it changed. Reading them must
	leave the connection at the start of the next response."

	self reportSeveralParameters.
	self assert: (client query: 'SELECT 111') data equals: #( #( 111 ) )
]
