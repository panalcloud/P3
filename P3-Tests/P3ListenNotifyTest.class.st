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
P3ListenNotifyTest >> logEventsOf: eventClass during: aBlock [
	"Answer the events of eventClass announced while aBlock runs."

	| events |
	events := OrderedCollection new.
	P3LogEvent announcer when: eventClass do: [ :event | events add: event ] for: self.
	[ aBlock value ] ensure: [ P3LogEvent announcer unsubscribe: self ].
	^ events
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

{ #category : 'private' }
P3ListenNotifyTest >> serverListeningChannels [
	"The channels the server registered for my client, asked from the server itself."

	^ ((client query: 'SELECT pg_listening_channels()') data collect: [ :row | row first ]) asSet
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

{ #category : 'tests - api' }
P3ListenNotifyTest >> testChannelNameIsLimitedTo63Bytes [
	"The server truncates a longer LISTEN name but refuses it in pg_notify, so the listen would never match.
	The limit counts bytes in the connection encoding: é takes two."

	| longest |
	longest := String new: 31 withAll: $é.
	longest := longest , 'a'.
	client listen: longest.
	self assert: self serverListeningChannels equals: { longest } asSet.
	self should: [ client listen: longest , 'b' ] raise: P3Error.
	self should: [ client listen: (String new: 64 withAll: $a) ] raise: P3Error.
	self assert: client listeningChannels equals: { longest } asSet
]

{ #category : 'tests - api' }
P3ListenNotifyTest >> testChannelNameIsQuoted [
	"Mixed case, spaces and quotes are part of the name, not SQL."

	| channel notifications |
	channel := 'Mixed Case "quoted" it''s'.
	client listen: channel.
	self assert: self serverListeningChannels equals: { channel } asSet.
	self send: 'x' on: channel.
	notifications := self received.
	self assert: notifications size equals: 1.
	self assert: notifications first channel equals: channel
]

{ #category : 'tests - api' }
P3ListenNotifyTest >> testChannelNameMustNotBeEmpty [
	self should: [ client listen: '' ] raise: P3Error.
	self should: [ client unlisten: '' ] raise: P3Error.
	self assert: client listeningChannels isEmpty
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

{ #category : 'tests - api' }
P3ListenNotifyTest >> testHasNotifications [
	client listen: self channelName.
	self deny: client hasNotifications.
	self send: 'x'.
	client query: 'SELECT 1'.
	self assert: client hasNotifications.
	client takeNotifications.
	self deny: client hasNotifications
]

{ #category : 'tests - api' }
P3ListenNotifyTest >> testListen [
	| notifications |
	client listen: self channelName.
	self send: 'one'.
	notifications := self received.
	self assert: notifications size equals: 1.
	self assert: notifications first channel equals: self channelName.
	self assert: notifications first payload equals: 'one'
]

{ #category : 'tests - logging' }
P3ListenNotifyTest >> testListenAndUnlistenAreLogged [
	| events |
	events := self logEventsOf: P3ListenEvent during: [
		client listen: 'p3_a'; unlisten: 'p3_a'; unlistenAll ].
	self assert: (events collect: [ :each | each action ]) asArray equals: #( #listen #unlisten #unlistenAll ).
	self assert: (events collect: [ :each | each channel ]) asArray equals: #( 'p3_a' 'p3_a' nil )
]

{ #category : 'tests - api' }
P3ListenNotifyTest >> testListenIsRefusedInsideATransaction [
	"A rollback would undo the registration while the client still believed in it."

	client execute: 'BEGIN'.
	[ self should: [ client listen: self channelName ] raise: P3Error.
	self should: [ client unlisten: self channelName ] raise: P3Error.
	self should: [ client unlistenAll ] raise: P3Error ]
		ensure: [ client execute: 'ROLLBACK' ].
	self assert: client listeningChannels isEmpty.
	self assert: self serverListeningChannels isEmpty
]

{ #category : 'tests - api' }
P3ListenNotifyTest >> testListeningChannelsMatchTheServer [
	client listen: 'p3_a'; listen: 'p3_b'; listen: 'p3_a'.
	self assert: client listeningChannels equals: #( 'p3_a' 'p3_b' ) asSet.
	self assert: self serverListeningChannels equals: client listeningChannels.
	client unlisten: 'p3_a'.
	self assert: client listeningChannels equals: #( 'p3_b' ) asSet.
	self assert: self serverListeningChannels equals: client listeningChannels
]

{ #category : 'tests - api' }
P3ListenNotifyTest >> testNotifyChannelIsAParameter [
	| channel notifications |
	channel := 'x''); drop table p3_listen_notify_victim; --'.
	client listen: channel.
	notifier notify: channel payload: 'p'.
	notifications := self received.
	self assert: notifications size equals: 1.
	self assert: notifications first channel equals: channel
]

{ #category : 'tests - api' }
P3ListenNotifyTest >> testNotifyPassesThePayloadAsAParameter [
	| payload notifications |
	payload := '''); drop table p3_listen_notify_victim; --'.
	notifier execute: 'DROP TABLE IF EXISTS p3_listen_notify_victim'.
	notifier execute: 'CREATE TABLE p3_listen_notify_victim (id INTEGER)'.
	[ client listen: self channelName.
	notifier notify: self channelName payload: payload.
	notifications := self received.
	self assert: notifications size equals: 1.
	self assert: notifications first payload equals: payload.
	self assert: (notifier query: 'SELECT count(*) FROM p3_listen_notify_victim') firstFieldOfFirstRecord equals: 0 ]
		ensure: [ notifier execute: 'DROP TABLE IF EXISTS p3_listen_notify_victim' ]
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

{ #category : 'tests - api' }
P3ListenNotifyTest >> testUnlistenAll [
	"Also drops a registration made with plain SQL, which the client does not track."

	client listen: 'p3_a'; listen: 'p3_b'.
	client execute: 'LISTEN p3_raw'.
	client unlistenAll.
	self assert: client listeningChannels isEmpty.
	self assert: self serverListeningChannels isEmpty.
	self send: 'x' on: 'p3_a'.
	self send: 'x' on: 'p3_raw'.
	self assert: self received isEmpty
]

{ #category : 'tests - api' }
P3ListenNotifyTest >> testUnlistenStopsDelivery [
	client listen: self channelName.
	client unlisten: self channelName.
	self send: 'after'.
	self assert: self received isEmpty.
	self assert: client listeningChannels isEmpty
]
