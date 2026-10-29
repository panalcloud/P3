"
I test, with no server, how P3Client reads NotificationResponse ($A) messages placed between the messages of a response: a recorded byte stream (P3ScriptedStream) stands in for the socket. The response must answer its own result, and every notification must be queued in order.

P3ListenNotifyTest tests the same against a server.
"
Class {
	#name : 'P3NotificationMessageTest',
	#superclass : 'TestCase',
	#instVars : [
		'client'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3NotificationMessageTest >> message: aCharacter payload: aByteArray [
	^ P3ScriptedStream message: aCharacter payload: aByteArray
]

{ #category : 'private' }
P3NotificationMessageTest >> notification: payloadString [
	"A NotificationResponse from backend 4242 on channel 'ch'."

	^ self message: $A payload: (ByteArray streamContents: [ :out |
		out nextPutAll: (4242 asByteArrayOfSize: 4).
		out nextPutAll: 'ch' utf8Encoded; nextPut: 0.
		out nextPutAll: payloadString utf8Encoded; nextPut: 0 ])
]

{ #category : 'private' }
P3NotificationMessageTest >> selectOneWith: notificationPayloads [
	"The response to SELECT 1 AS n, with one NotificationResponse before each of its messages, in order."

	| messages |
	messages := {
		self message: $T payload: (ByteArray streamContents: [ :out |
			out nextPutAll: (1 asByteArrayOfSize: 2).
			out nextPutAll: 'n' utf8Encoded; nextPut: 0.
			out nextPutAll: (0 asByteArrayOfSize: 4); nextPutAll: (0 asByteArrayOfSize: 2).
			out nextPutAll: (23 asByteArrayOfSize: 4); nextPutAll: (4 asByteArrayOfSize: 2).
			out nextPutAll: (16rFFFFFFFF asByteArrayOfSize: 4); nextPutAll: (0 asByteArrayOfSize: 2) ]).
		self message: $D payload: (ByteArray streamContents: [ :out |
			out nextPutAll: (1 asByteArrayOfSize: 2); nextPutAll: (1 asByteArrayOfSize: 4); nextPutAll: '1' asByteArray ]).
		self message: $C payload: ('SELECT 1' asByteArray , #[0]).
		self message: $Z payload: 'I' asByteArray }.
	^ ByteArray streamContents: [ :out |
		messages with: notificationPayloads do: [ :each :payload |
			out nextPutAll: (self notification: payload); nextPutAll: each ] ]
]

{ #category : 'tests' }
P3NotificationMessageTest >> testNotificationsBetweenEveryMessageOfAResponse [
	| result notifications |
	self useResponse: (self selectOneWith: #( 'a' 'b' 'ñ' '' )).
	result := client query: 'SELECT 1 AS n'.
	self assert: result data equals: #( #( 1 ) ).
	self assert: result results equals: 'SELECT 1'.
	notifications := client takeNotifications.
	self assert: (notifications collect: [ :each | each payload ]) asArray equals: #( 'a' 'b' 'ñ' '' ).
	self assert: (notifications collect: [ :each | each channel ]) asSet equals: #( 'ch' ) asSet.
	self assert: (notifications collect: [ :each | each processId ]) asSet equals: #( 4242 ) asSet
]

{ #category : 'tests' }
P3NotificationMessageTest >> testNotificationsBetweenResponsesAreReadBeforeTheNextRequest [
	"A NotificationResponse after ReadyForQuery is unsolicited: it is read and queued before the next
	request is written, and the next response still answers that request."

	| first second |
	self useResponse: (self selectOneWith: #( 'a' 'b' 'c' 'd' )) , (self notification: 'idle').
	first := client query: 'SELECT 1 AS n'.
	self assert: first data equals: #( #( 1 ) ).
	self assert: (client takeNotifications collect: [ :each | each payload ]) asArray equals: #( 'a' 'b' 'c' 'd' ).
	self assert: (client instVarNamed: #connection) isDataAvailable.
	second := client query: 'SELECT 1 AS n'.
	self assert: second data equals: #( #( 1 ) ).
	self assert: (client takeNotifications collect: [ :each | each payload ]) asArray equals: #( 'idle' 'a' 'b' 'c' 'd' )
]

{ #category : 'running' }
P3NotificationMessageTest >> useResponse: aByteArray [
	"Make my client read aByteArray as the response to its next request, as if connected."

	client := P3Client new.
	client instVarNamed: #connection put: (P3ScriptedStream bytes: aByteArray).
	client instVarNamed: #message put: P3MessageBuffer new.
	client instVarNamed: #session put: 1
]
