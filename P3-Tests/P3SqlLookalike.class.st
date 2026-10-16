"
Test object whose print string is a valid SQL fragment. Spliced after SELECT it makes a query with a second row. It shows whether a statement copies the print string of an arbitrary object into the SQL text.
"
Class {
	#name : 'P3SqlLookalike',
	#superclass : 'Object',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'printing' }
P3SqlLookalike >> printOn: aStream [
	aStream nextPutAll: '''x'' UNION SELECT ''injected'''
]
