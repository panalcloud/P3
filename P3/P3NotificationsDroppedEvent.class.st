"
I am P3NotificationsDroppedEvent.
I am a P3LogEvent.

I represent a notification that a P3Client dropped because its queue held #limit notifications already, see P3Client>>#notificationLimit. My droppedCount is the client's total so far. I am only built while my announcer has subscribers: P3Client>>#droppedNotificationCount is the reliable way to notice drops.
"
Class {
	#name : 'P3NotificationsDroppedEvent',
	#superclass : 'P3LogEvent',
	#instVars : [
		'droppedCount',
		'limit'
	],
	#category : 'P3-Logging',
	#package : 'P3',
	#tag : 'Logging'
}

{ #category : 'accessing' }
P3NotificationsDroppedEvent >> droppedCount [
	"How many notifications the client dropped in total, this one included."

	^ droppedCount
]

{ #category : 'initialization' }
P3NotificationsDroppedEvent >> droppedCount: countInteger limit: limitInteger [
	droppedCount := countInteger.
	limit := limitInteger
]

{ #category : 'accessing' }
P3NotificationsDroppedEvent >> limit [
	^ limit
]

{ #category : 'printing' }
P3NotificationsDroppedEvent >> printContentsOn: stream [
	stream print: #NotificationsDropped; space; print: droppedCount; nextPutAll: ' in total, limit '; print: limit
]
