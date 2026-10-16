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
P3ListenNotifyTest >> millisecondsToRun: aBlock [
	| start |
	start := Time millisecondClockValue.
	aBlock value.
	^ Time millisecondsSince: start
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

{ #category : 'private' }
P3ListenNotifyTest >> terminateClientBackend [
	"End my client's server session from the notifier, and wait until it is gone."

	notifier query: 'SELECT pg_terminate_backend(' , client backendProcessId printString , ', 5000)'
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

{ #category : 'tests - logging' }
P3ListenNotifyTest >> testDroppedNotificationsAreLogged [
	| events |
	client notificationLimit: 2.
	client listen: self channelName.
	1 to: 5 do: [ :each | self send: each printString ].
	events := self logEventsOf: P3NotificationsDroppedEvent during: [ client query: 'SELECT 1' ].
	self assert: events size equals: 3.
	self assert: events last droppedCount equals: 3.
	self assert: events last limit equals: 2
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

{ #category : 'tests - reconnect' }
P3ListenNotifyTest >> testExplicitCloseForgetsTheChannels [
	"An explicit close ends the session on purpose: a later connection starts without subscriptions."

	client listen: self channelName.
	client close.
	client connect.
	self assert: client listeningChannels isEmpty.
	self assert: self serverListeningChannels isEmpty
]

{ #category : 'tests - handler' }
P3ListenNotifyTest >> testFailingHandlerIsLoggedAndLeavesTheConnectionUsable [
	| events result seen |
	seen := OrderedCollection new.
	client notificationHandler: [ :notification |
		seen add: notification payload.
		notification payload = 'bad' ifTrue: [ self error: 'handler failure' ] ].
	client listen: self channelName.
	self send: 'bad'; send: 'good'.
	events := self logEventsOf: P3ErrorOccurredEvent during: [ result := client query: 'SELECT 7' ].
	self assert: result data equals: #( #( 7 ) ).
	self assert: seen asArray equals: #( 'bad' 'good' ).
	self assert: events size equals: 1.
	self assert: events first exception messageText equals: 'handler failure'.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - handler' }
P3ListenNotifyTest >> testHandlerCanUseTheClient [
	"The response that carried the notification is read completely before the handler runs."

	| answers |
	answers := OrderedCollection new.
	client notificationHandler: [ :notification |
		answers add: (client query: 'SELECT ' , notification payload) firstFieldOfFirstRecord ].
	client listen: self channelName.
	self send: '11'; send: '22'.
	self assert: (client query: 'SELECT 7') data equals: #( #( 7 ) ).
	self assert: answers asArray equals: #( 11 22 ).
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - handler' }
P3ListenNotifyTest >> testHandlerReceivesNotificationsInOrder [
	| seen process |
	seen := OrderedCollection new.
	client notificationHandler: [ :notification |
		process := Processor activeProcess.
		seen add: notification payload ].
	client listen: self channelName.
	self send: 'one'; send: 'two'; send: 'three'.
	self assert: (client query: 'SELECT 7') data equals: #( #( 7 ) ).
	self assert: seen asArray equals: #( 'one' 'two' 'three' ).
	self assert: process equals: Processor activeProcess.
	self deny: client hasNotifications
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

{ #category : 'tests - logging' }
P3ListenNotifyTest >> testLogEventsPrintOnOneLine [
	| events |
	client listen: self channelName.
	self send: 'printed'.
	events := self logEventsOf: P3LogEvent during: [ client query: 'SELECT 1'. client unlisten: self channelName ].
	events do: [ :each | self deny: (each printString includesAny: String crlf) ].
	self assert: (events contains: [ :each | (each printString includesSubstring: 'printed') ]).
	self assert: (events contains: [ :each | (each printString includesSubstring: 'Unlisten') ])
]

{ #category : 'tests - logging' }
P3ListenNotifyTest >> testNotificationReceivedIsLogged [
	| events |
	client listen: self channelName.
	self send: 'logged'.
	events := self logEventsOf: P3NotificationReceivedEvent during: [ client query: 'SELECT 1' ].
	self assert: events size equals: 1.
	self assert: events first notification payload equals: 'logged'.
	self assert: events first notification channel equals: self channelName.
	self assert: events first session equals: client session
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

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testQueriesFromOtherProcessesRunWhileWaiting [
	"A wait in progress delays another process's queries by at most one slice of 100 milliseconds."

	| waiter elapsed |
	client listen: self channelName.
	waiter := [ client waitForNotification: 10 ] forkAt: Processor userBackgroundPriority + 1.
	[ (Delay forMilliseconds: 100) wait.
	elapsed := self millisecondsToRun: [ 1 to: 5 do: [ :each | client query: 'SELECT 1' ] ].
	self assert: elapsed < 1000 ] ensure: [ waiter terminate ]
]

{ #category : 'tests - queue' }
P3ListenNotifyTest >> testQueueDropsTheOldestBeyondItsLimit [
	| notifications |
	client notificationLimit: 3.
	client listen: self channelName.
	1 to: 5 do: [ :each | self send: each printString ].
	notifications := self received.
	self assert: (notifications collect: [ :each | each payload ]) equals: #( '3' '4' '5' ).
	self assert: client droppedNotificationCount equals: 2
]

{ #category : 'tests - queue' }
P3ListenNotifyTest >> testQueueLimitDefault [
	self assert: client notificationLimit equals: 10000.
	self assert: client droppedNotificationCount equals: 0
]

{ #category : 'tests - queue' }
P3ListenNotifyTest >> testQueueLimitMustBePositive [
	self should: [ client notificationLimit: 0 ] raise: Error.
	self should: [ client notificationLimit: nil ] raise: Error.
	self assert: client notificationLimit equals: 10000
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

{ #category : 'tests - reconnect' }
P3ListenNotifyTest >> testReplacementConnectionListensAgain [
	| oldPid events notifications |
	client listen: 'p3_a'; listen: 'p3_b'.
	oldPid := client backendProcessId.
	self terminateClientBackend.
	events := self logEventsOf: P3ListenRestoredEvent during: [ client query: 'SELECT 1' ].
	self deny: client backendProcessId equals: oldPid.
	self assert: self serverListeningChannels equals: #( 'p3_a' 'p3_b' ) asSet.
	self assert: client listeningChannels equals: #( 'p3_a' 'p3_b' ) asSet.
	self assert: events size equals: 1.
	self assert: events first channels asSet equals: #( 'p3_a' 'p3_b' ) asSet.
	self send: 'again' on: 'p3_b'.
	notifications := self received.
	self assert: notifications size equals: 1.
	self assert: notifications first payload equals: 'again'
]

{ #category : 'tests - reconnect' }
P3ListenNotifyTest >> testReplacementIsSignalledAfterListeningAgain [
	"A handler of P3ConnectionReplaced, the place to resynchronise, finds the channels registered already."

	| channelsSeen |
	client listen: self channelName.
	self terminateClientBackend.
	[ client query: 'SELECT 1' ]
		on: P3ConnectionReplaced
		do: [ :notification |
			channelsSeen := self serverListeningChannels.
			notification resume ].
	self assert: channelsSeen equals: { self channelName } asSet
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

{ #category : 'tests - reconnect' }
P3ListenNotifyTest >> testWaitAfterALostConnectionListensAgain [
	"The loss happened between two waits: the next wait replaces the connection and receives on it."

	| answer |
	client listen: self channelName.
	self terminateClientBackend.
	self after: 500 do: [ self send: 'after reconnect' ].
	answer := client waitForNotification: 5.
	self assert: answer payload equals: 'after reconnect'
]

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testWaitAnswersANotificationSentLater [
	| answer elapsed |
	client listen: self channelName.
	self after: 500 do: [ self send: 'late' ].
	elapsed := self millisecondsToRun: [ answer := client waitForNotification: 5 ].
	self assert: answer payload equals: 'late'.
	self assert: (elapsed between: 400 and: 1200).
	self deny: client hasNotifications.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testWaitAnswersTheQueuedNotificationsFirst [
	| elapsed first second |
	client listen: self channelName.
	self send: 'one'; send: 'two'.
	client query: 'SELECT 1'.
	elapsed := self millisecondsToRun: [
		first := client waitForNotification: 5.
		second := client waitForNotification: 5 ].
	self assert: first payload equals: 'one'.
	self assert: second payload equals: 'two'.
	self assert: elapsed < 500
]

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testWaitEndsWhenTheBackendIsTerminated [
	| pid elapsed error |
	client listen: self channelName.
	pid := client backendProcessId.
	self after: 300 do: [ notifier query: 'SELECT pg_terminate_backend(' , pid printString , ')' ].
	elapsed := self millisecondsToRun: [
		error := [ client waitForNotification: 10. nil ] on: P3Error do: [ :e | e ] ].
	self assert: error notNil.
	self assert: error code equals: 'P3072'.
	self assert: elapsed < 1300.
	self deny: client isConnected
]

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testWaitForNotificationsAnswersAllPending [
	| answer |
	client listen: self channelName.
	self assert: (client waitForNotifications: 0.2) isEmpty.
	self send: 'one'; send: 'two'; send: 'three'.
	answer := client waitForNotifications: 5.
	self assert: (answer collect: [ :each | each payload ]) asArray equals: #( 'one' 'two' 'three' ).
	self deny: client hasNotifications
]

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testWaitReadsNotificationsThatArrivedWhileIdle [
	"Nobody queried after the NOTIFY: the wait itself has to read it from the connection."

	| answer |
	client listen: self channelName.
	self send: 'idle'.
	answer := client waitForNotification: 5.
	self assert: answer payload equals: 'idle'
]

{ #category : 'tests - handler' }
P3ListenNotifyTest >> testWaitTakesNotificationsBeforeTheHandler [
	"Each notification is answered once: a wait takes it, the handler only gets what is left after a request."

	| seen answer |
	seen := OrderedCollection new.
	client notificationHandler: [ :notification | seen add: notification payload ].
	client listen: self channelName.
	self send: 'waited'.
	answer := client waitForNotification: 5.
	self assert: answer payload equals: 'waited'.
	client query: 'SELECT 1'.
	self assert: seen isEmpty
]

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testWaitTimesOutWithoutTraffic [
	| answer elapsed |
	client listen: self channelName.
	elapsed := self millisecondsToRun: [ answer := client waitForNotification: 2 ].
	self assert: answer isNil.
	self assert: (elapsed between: 1900 and: 2700).
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests - reconnect' }
P3ListenNotifyTest >> testWaitWithoutAutoReconnectSignals [
	client autoReconnect: false.
	client listen: self channelName.
	self terminateClientBackend.
	self should: [ client waitForNotification: 2 ] raise: P3Error.
	client connect.
	self assert: client listeningChannels equals: { self channelName } asSet.
	self assert: self serverListeningChannels equals: { self channelName } asSet
]

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testWaiterSeesANotificationReadByAnotherProcess [
	"Another process sharing the client may read the notification with its own query: the waiter must
	still get it, and that query must not be held up by the waiter, beyond one slice of its wait."

	| answer done elapsed |
	client listen: self channelName.
	done := Semaphore new.
	[ answer := client waitForNotification: 5. done signal ] forkAt: Processor userBackgroundPriority + 1.
	(Delay forMilliseconds: 100) wait.
	self send: 'shared'.
	elapsed := self millisecondsToRun: [ client query: 'SELECT 1' ].
	self assert: elapsed < 500.
	self assert: (done waitTimeoutMilliseconds: 1500) not.
	self assert: answer payload equals: 'shared'
]

{ #category : 'tests - wait' }
P3ListenNotifyTest >> testWaitingProcessCanBeTerminated [
	"Terminating the waiter leaves the client usable by others at once."

	| waiter elapsed |
	client listen: self channelName.
	waiter := [ client waitForNotification: 30 ] forkAt: Processor userBackgroundPriority + 1.
	(Delay forMilliseconds: 300) wait.
	waiter terminate.
	elapsed := self millisecondsToRun: [ self assertConnectionAnswersItsOwnQueries ].
	self assert: elapsed < 1000
]
