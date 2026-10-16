"
I am P3ArrayElementPrinter.

I print values as elements of a PostgreSQL array literal, {e1,e2,...}. I understand the same printing-dispatched protocol as P3MessageBuilder and take the text of each value from it, but I write that text as a quoted element, escaping the double quote and the backslash. Without the quotes, a comma, a brace, whitespace, an empty string or the text NULL inside a value changes the structure of the array instead of being part of one element.

Two values are structure and not text, so they are written unquoted: nil is the NULL element, and a nested collection keeps its own braces.

P3MessageBuilder>>#printValuesArray:on: creates and uses me. P3ArrayValueParser reads back what I write.
"
Class {
	#name : 'P3ArrayElementPrinter',
	#superclass : 'Object',
	#instVars : [
		'builder'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'instance creation' }
P3ArrayElementPrinter class >> on: aMessageBuilder [
	^ self new setBuilder: aMessageBuilder
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printBitString: bitString on: stream [
	self printQuoted: [ :out | builder printBitString: bitString on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printByteArray: byteArray on: stream [
	"The bytea hex format begins with a backslash, which is an escape inside an array literal"

	self printQuoted: [ :out | builder printByteArray: byteArray on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printDate: date on: stream [
	self printQuoted: [ :out | builder printUnquotedDate: date on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printDateAndTime: dateAndTime on: stream [
	self printQuoted: [ :out | builder printUnquotedDateAndTime: dateAndTime on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printFloat: float on: stream [
	self printQuoted: [ :out | builder printFloat: float on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printGeometricObject: geometricObject on: stream [
	self printQuoted: [ :out | builder printGeometricObject: geometricObject on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printInterval: interval on: stream [
	"An interval holds spaces, which end an unquoted element"

	self printQuoted: [ :out | builder printInterval: interval on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printNullOn: stream [
	"nil is the NULL element. It is written unquoted, since a quoted NULL is the text NULL."

	stream nextPutAll: 'NULL'
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printObject: object on: stream [
	"Quote the standard print string representation, as PostgreSQL accepts a quoted element
	for every element type"

	self printQuoted: [ :out | builder printObject: object on: out ] on: stream
]

{ #category : 'private' }
P3ArrayElementPrinter >> printQuoted: aBlock on: stream [
	"Write the text that aBlock writes as one quoted array element. Inside a quoted element
	only the double quote and the backslash have a meaning, and a backslash escapes both."

	stream nextPut: $".
	(String streamContents: aBlock) do: [ :char |
		(char = $" or: [ char = $\ ]) ifTrue: [ stream nextPut: $\ ].
		stream nextPut: char ].
	stream nextPut: $"
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printScaledDecimal: scaledDecimal on: stream [
	self printQuoted: [ :out | builder printScaledDecimal: scaledDecimal on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printString: string on: stream [
	"A string is written as is inside the quotes, where it needs no other escaping"

	self printQuoted: [ :out | out nextPutAll: string ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printTime: time on: stream [
	self printQuoted: [ :out | builder printUnquotedTime: time on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printUUID: uuid on: stream [
	self printQuoted: [ :out | builder printUUID: uuid on: out ] on: stream
]

{ #category : 'printing-dispatched' }
P3ArrayElementPrinter >> printValuesArray: valuesArray on: stream [
	"A nested collection is a sub-array: it keeps its own braces and is not quoted."

	builder printValuesArray: valuesArray on: stream
]

{ #category : 'initialization' }
P3ArrayElementPrinter >> setBuilder: aMessageBuilder [
	"Set the P3MessageBuilder that knows the text representation of each value"

	builder := aMessageBuilder
]
