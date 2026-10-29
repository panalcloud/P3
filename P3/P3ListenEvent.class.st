"
I am P3ListenEvent.
I am a P3LogEvent.

I represent a change of the channels a P3Client listens on: my action is #listen or #unlisten with a channel, or #unlistenAll without one. See P3Client>>#listen:. A registration restored on a new connection is a P3ListenRestoredEvent instead.
"
Class {
	#name : 'P3ListenEvent',
	#superclass : 'P3LogEvent',
	#instVars : [
		'action',
		'channel'
	],
	#category : 'P3-Logging',
	#package : 'P3',
	#tag : 'Logging'
}

{ #category : 'accessing' }
P3ListenEvent >> action [
	"#listen, #unlisten or #unlistenAll."

	^ action
]

{ #category : 'initialization' }
P3ListenEvent >> action: aSymbol channel: aStringOrNil [
	action := aSymbol.
	channel := aStringOrNil
]

{ #category : 'accessing' }
P3ListenEvent >> channel [
	"The channel of #listen and #unlisten, nil for #unlistenAll."

	^ channel
]

{ #category : 'printing' }
P3ListenEvent >> printContentsOn: stream [
	stream print: (action ifNotNil: [ action capitalized asSymbol ]).
	channel ifNotNil: [ stream space; print: channel ]
]
