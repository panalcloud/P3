"
I am P3ListenRestoredEvent.
I am a P3LogEvent.

I represent a P3Client that replaced a lost connection and issued LISTEN again for the channels it listened on, see P3Client>>#connect. Notifications sent while the connection was down are lost: a listener that sees me has to resynchronise. My session is the new one.
"
Class {
	#name : 'P3ListenRestoredEvent',
	#superclass : 'P3LogEvent',
	#instVars : [
		'channels'
	],
	#category : 'P3-Logging',
	#package : 'P3',
	#tag : 'Logging'
}

{ #category : 'accessing' }
P3ListenRestoredEvent >> channels [
	^ channels
]

{ #category : 'initialization' }
P3ListenRestoredEvent >> channels: aCollection [
	channels := aCollection
]

{ #category : 'printing' }
P3ListenRestoredEvent >> printContentsOn: stream [
	stream print: #ListenRestored.
	channels do: [ :each | stream space; print: each ]
]
