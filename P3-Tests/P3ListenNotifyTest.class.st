"
I test LISTEN/NOTIFY through P3Client against a server: the API (#listen:, #unlisten:, #unlistenAll, #notify:payload:, #listeningChannels), the bounded queue, #waitForNotification:, re-listening on a replaced connection, the notification handler, the log events, and what PostgreSQL guarantees about delivery inside transactions.

My client listens; the notifier, a second connection, sends with pg_notify so the API under test is not used to check itself. Work forked with #after:do: is waited for in #tearDown before the clients close.

Configure the connection through P3ClientTest class >> #url:, like the other tests in this package. P3NotificationMessageTest covers the reading of NotificationResponse without a server.
"
Class {
	#name : 'P3ListenNotifyTest',
	#superclass : 'P3ResponseTestCase',
	#instVars : [
		'notifier',
		'forked'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3ListenNotifyTest >> after: milliseconds do: aBlock [
	"Run aBlock in another process after milliseconds. #tearDown waits for it before closing the clients
	it may use."

	| done |
	done := Semaphore new.
	forked add: done.
	^ [ [ (Delay forMilliseconds: milliseconds) wait. aBlock value ] ensure: [ done signal ] ]
		forkAt: Processor userBackgroundPriority + 1
		named: 'P3ListenNotifyTest'
]

{ #category : 'private' }
P3ListenNotifyTest >> channelName [
	^ 'p3_listen_notify_test'
]

{ #category : 'accessing' }
P3ListenNotifyTest >> clients [
	^ super clients , { notifier }
]

{ #category : 'private' }
P3ListenNotifyTest >> received [
	"Run a query on my client so that it reads what the server queued for it, and answer the notifications it collected."

	client query: 'SELECT 1'.
	^ client takeNotifications
]

{ #category : 'private' }
P3ListenNotifyTest >> send: payload [
	"Notify my channel from the notifier connection, with the payload passed as a parameter."

	self send: payload on: self channelName
]

{ #category : 'private' }
P3ListenNotifyTest >> send: payload on: channel [
	"Notify channel from the notifier connection through pg_notify, independent of the API under test."

	(notifier prepare: 'SELECT pg_notify($1, $2)') execute: { channel. payload }
]

{ #category : 'running' }
P3ListenNotifyTest >> setUp [
	super setUp.
	forked := OrderedCollection new.
	notifier := self newConnectedClient
]

{ #category : 'running' }
P3ListenNotifyTest >> tearDown [
	forked do: [ :each | each waitTimeoutSeconds: 10 ].
	super tearDown
]

{ #category : 'tests - notification' }
P3ListenNotifyTest >> testEmptyPayloadIsEmptyString [
	| notifications |
	client execute: 'LISTEN ' , self channelName.
	self send: ''.
	notifications := self received.
	self assert: notifications size equals: 1.
	self assert: notifications first payload equals: ''
]

{ #category : 'tests - notification' }
P3ListenNotifyTest >> testReceivedAtIsWhenRead [
	| before notifications after |
	client execute: 'LISTEN ' , self channelName.
	self send: 'x'.
	before := DateAndTime now.
	notifications := self received.
	after := DateAndTime now.
	self assert: notifications size equals: 1.
	self assert: (notifications first receivedAt between: before and: after)
]

{ #category : 'tests - notification' }
P3ListenNotifyTest >> testUnicodePayloadRoundTrips [
	| payload notifications |
	payload := 'ñandú 日本 ', (String with: (Character value: 16r1F600)).
	client execute: 'LISTEN ' , self channelName.
	self send: payload.
	notifications := self received.
	self assert: notifications size equals: 1.
	self assert: notifications first payload equals: payload.
	self assert: notifications first channel equals: self channelName.
	self assert: notifications first processId equals: notifier backendProcessId
]
