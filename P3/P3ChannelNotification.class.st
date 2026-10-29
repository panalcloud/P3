"
I am one NOTIFY delivered to a P3Client that issued LISTEN.

I carry the channel I was sent on, the payload the notifier passed (empty when it passed none), the process id of the backend that sent it, and the time I was read (#receivedAt). P3Client keeps me in its queue while reading a response, because the server delivers me once and would otherwise be lost. See P3Client>>#takeNotifications and P3Client>>#waitForNotification:.

I am read from a NotificationResponse message: Int32 process id, then the channel and the payload as strings in the connection encoding.

I am not a P3Notification, which is a server notice (NoticeResponse) signalled as an Exception.
"
Class {
	#name : 'P3ChannelNotification',
	#superclass : 'Object',
	#instVars : [
		'processId',
		'channel',
		'payload',
		'receivedAt'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'instance creation' }
P3ChannelNotification class >> processId: anInteger channel: channelString payload: payloadString [
	^ self new
		setProcessId: anInteger channel: channelString payload: payloadString;
		yourself
]

{ #category : 'accessing' }
P3ChannelNotification >> channel [
	^ channel
]

{ #category : 'accessing' }
P3ChannelNotification >> payload [
	^ payload
]

{ #category : 'printing' }
P3ChannelNotification >> printOn: stream [
	super printOn: stream.
	stream nextPut: $(.
	stream << channel.
	payload ifNotEmpty: [ stream space; print: payload ].
	stream nextPut: $)
]

{ #category : 'accessing' }
P3ChannelNotification >> processId [
	"The id of the backend process that sent me."

	^ processId
]

{ #category : 'accessing' }
P3ChannelNotification >> receivedAt [
	"When P3Client read me from the connection."

	^ receivedAt
]

{ #category : 'initialization' }
P3ChannelNotification >> setProcessId: anInteger channel: channelString payload: payloadString [
	processId := anInteger.
	channel := channelString.
	payload := payloadString.
	receivedAt := DateAndTime now
]
