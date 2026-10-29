"
I am P3NotificationReceivedEvent.
I am a P3LogEvent.

I represent a NOTIFY that a P3Client read from its connection and queued: I hold the P3ChannelNotification. Like the query events, I am only built while my announcer has subscribers.
"
Class {
	#name : 'P3NotificationReceivedEvent',
	#superclass : 'P3LogEvent',
	#instVars : [
		'notification'
	],
	#category : 'P3-Logging',
	#package : 'P3',
	#tag : 'Logging'
}

{ #category : 'accessing' }
P3NotificationReceivedEvent >> notification [
	^ notification
]

{ #category : 'initialization' }
P3NotificationReceivedEvent >> notification: aChannelNotification [
	notification := aChannelNotification
]

{ #category : 'printing' }
P3NotificationReceivedEvent >> printContentsOn: stream [
	stream print: #Notification; space; print: notification channel.
	stream space; print: notification processId.
	notification payload do: [ :each |
		(String crlf includes: each)
			ifTrue: [ stream space ]
			ifFalse: [ stream nextPut: each ] ]
]
