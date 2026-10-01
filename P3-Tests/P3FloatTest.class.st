"
I test how P3 reads and writes floating point numbers without a server. Reading is P3Converter>>floatFrom:, which gets the text of float4, float8 and the elements of their arrays. Writing is the text that a bound Float becomes. The server tests are in P3FloatServerTest.
"
Class {
	#name : 'P3FloatTest',
	#superclass : 'TestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3FloatTest >> assertIsNegativeZero: aFloat [
	self assert: aFloat printString equals: '-0.0'
]

{ #category : 'private' }
P3FloatTest >> digitsOf: aFloat [
	"Shortest digits in the server notation, with an explicit plus after the e."

	| text index |
	text := aFloat printString.
	index := text indexOf: $e.
	(index > 0 and: [ (text at: index + 1) ~= $- ]) ifFalse: [ ^ text ].
	^ (text copyFrom: 1 to: index) , '+' , (text copyFrom: index + 1 to: text size)
]

{ #category : 'private' }
P3FloatTest >> readFloat: aString [
	^ P3Converter new floatFrom: aString
]

{ #category : 'tests-reading' }
P3FloatTest >> testReadExponentWithExplicitPlus [
	"The sign after the e is part of the number."

	self assert: (self readFloat: '1e+100') equals: 1.0e100.
	self assert: (self readFloat: '1e15') equals: 1.0e15.
	self assert: (self readFloat: '-1e+20') equals: -1.0e20.
	self assert: (self readFloat: '1.5E+300') equals: 1.5e300.
	self assert: (self readFloat: '1.2345678901234568e+17') equals: 1.2345678901234568e17
]

{ #category : 'tests-reading' }
P3FloatTest >> testReadIsExactForEveryDoubleItPrintsBack [
	"A double printed with the shortest digits that identify it must read back as the same double."

	| random |
	random := Random seed: 20260930.
	300 timesRepeat: [ | mantissa exponent value |
		mantissa := (random nextInt: (1 bitShift: 52)) + (1 bitShift: 52).
		exponent := (random nextInt: 1900) - 1000.
		value := (mantissa * (2 raisedTo: exponent)) asFloat.
		(random nextInt: 2) = 1 ifTrue: [ value := value negated ].
		self
			assert: (self readFloat: (self digitsOf: value)) = value
			description: value printString ]
]

{ #category : 'tests-reading' }
P3FloatTest >> testReadLimitsOfDouble [
	self assert: (self readFloat: '1.7976931348623157e+308') equals: Float fmax.
	self assert: (self readFloat: '5e-324') equals: (1 / (2 raisedTo: 1074)) asFloat.
	self assert: (self readFloat: '-1.7976931348623157e+308') equals: Float fmax negated
]

{ #category : 'tests-reading' }
P3FloatTest >> testReadNegativeExponent [
	self assert: (self readFloat: '1e-7') equals: 1.0e-7.
	self assert: (self readFloat: '-1.5e-07') equals: -1.5e-7.
	self assert: (self readFloat: '2.2250738585072014e-308') equals: 2.2250738585072014e-308
]

{ #category : 'tests-reading' }
P3FloatTest >> testReadNegativeZeroKeepsItsSign [
	self assertIsNegativeZero: (self readFloat: '-0').
	self assertIsNegativeZero: (self readFloat: '-0.0').
	self assert: (self readFloat: '0') printString equals: '0.0'.
	self assert: (self readFloat: '0.0') printString equals: '0.0'
]

{ #category : 'tests-reading' }
P3FloatTest >> testReadNonFiniteValues [
	self assert: (self readFloat: 'NaN') isNaN.
	self assert: (self readFloat: 'Infinity') equals: Float infinity.
	self assert: (self readFloat: '-Infinity') equals: Float infinity negated
]

{ #category : 'tests-reading' }
P3FloatTest >> testReadPlainDecimals [
	self assert: (self readFloat: '0') equals: 0.0.
	self assert: (self readFloat: '1') equals: 1.0.
	self assert: (self readFloat: '0.1') equals: 0.1.
	self assert: (self readFloat: '-2.5') equals: -2.5.
	self assert: (self readFloat: '123456789.125') equals: 123456789.125.
	self assert: (self readFloat: '+1.5') equals: 1.5
]

{ #category : 'tests-reading' }
P3FloatTest >> testReadRefusesTextThatIsNotAFloat [
	#('' 'abc' '1e' '1e+' '1.2.3' '--1' '1 2' '1e5x' '.') do: [ :each |
		self should: [ self readFloat: each ] raise: P3Error description: each printString ]
]

{ #category : 'tests-writing' }
P3FloatTest >> testWriteNeverUsesSmalltalkNames [
	#(1.5 -2.5 1.0e100 -0.0) , { Float nan. Float infinity. Float infinity negated } do: [ :each | | text |
		text := self writtenTextOf: each.
		self deny: (text includesSubstring: 'Float') description: text.
		self deny: (text includesSubstring: 'negated') description: text ]
]

{ #category : 'tests-writing' }
P3FloatTest >> testWriteNonFiniteValuesInTheServerNotation [
	self assert: (self writtenTextOf: Float nan) equals: 'NaN'.
	self assert: (self writtenTextOf: Float infinity) equals: 'Infinity'.
	self assert: (self writtenTextOf: Float infinity negated) equals: '-Infinity'
]

{ #category : 'tests-writing' }
P3FloatTest >> testWrittenFiniteValueReadsBackAsTheSameDouble [
	"The text a prepared statement sends, read by P3 again, gives the same double. A value written with fewer digits than it needs, or with an exponent form the server refuses, fails in the server tests."

	| values |
	values := { 0.0. -0.0. 1.5. -2.5. 0.1. 1.0e100. -1.0e-100. 1.0e15. 123456789.125. Float fmax. 5.0e-324. 2.2250738585072014e-308 }.
	values do: [ :each |
		self
			assert: (self readFloat: (self writtenTextOf: each)) printString = each printString
			description: each printString ]
]

{ #category : 'private' }
P3FloatTest >> writtenTextOf: aFloat [
	"The text that a prepared statement sends for aFloat, and the one inside an array literal."

	^ String streamContents: [ :stream | aFloat p3PrintUsing: P3MessageBuilder new on: stream ]
]
