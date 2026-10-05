"
I test how P3 reads the text of a numeric without a server, in P3Converter>>scaledDecimalFrom:. A numeric is read as a ScaledDecimal, which is a fraction. NaN and the infinities of a numeric have no ScaledDecimal, so reading them signals a P3Error. The server tests are in P3NumericServerTest.
"
Class {
	#name : 'P3NumericTest',
	#superclass : 'TestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3NumericTest >> errorReading: aString [
	"Answer the P3Error that reading aString signals. Fail when it is read, or when the error is another kind."

	^ [ self readNumeric: aString. self fail: aString printString , ' was read as a number' ]
		on: P3Error
		do: [ :error | error ]
]

{ #category : 'private' }
P3NumericTest >> readNumeric: aString [
	^ P3Converter new scaledDecimalFrom: aString
]

{ #category : 'tests-reading' }
P3NumericTest >> testErrorNamesTheTargetType [
	"The reader of the error must learn why a value that the server holds cannot be read."

	| text |
	text := (self errorReading: 'NaN') messageText.
	self assert: (text includesSubstring: 'ScaledDecimal') description: text
]

{ #category : 'tests-reading' }
P3NumericTest >> testNonFiniteValuesSignalP3Error [
	#('NaN' 'Infinity' '-Infinity') do: [ :each | | error |
		error := self errorReading: each.
		self assert: error code equals: 'P3034'.
		self assert: error isLocal.
		self assert: (error messageText includesSubstring: each) description: error messageText ]
]

{ #category : 'tests-reading' }
P3NumericTest >> testReadFiniteValues [
	self assert: (self readNumeric: '1.5') equals: 1.5s1.
	self assert: (self readNumeric: '-0.25') equals: -0.25s2.
	self assert: (self readNumeric: '0') equals: 0.
	self assert: (self readNumeric: '123') equals: 123.
	self assert: (self readNumeric: '0.000') equals: 0
]

{ #category : 'tests-reading' }
P3NumericTest >> testReadIsExactForLongValues [
	self
		assert: (self readNumeric: '12345678901234567890.123456789')
		equals: 12345678901234567890123456789 / (10 raisedTo: 9).
	self
		assert: (self readNumeric: '-0.000000000000000000001')
		equals: -1 / (10 raisedTo: 21)
]

{ #category : 'tests-reading' }
P3NumericTest >> testReadKeepsTheScaleOfTheText [
	self assert: (self readNumeric: '1.50') scale equals: 2.
	self assert: (self readNumeric: '-7.125') scale equals: 3
]
