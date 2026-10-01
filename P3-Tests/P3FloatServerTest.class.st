"
I test floating point numbers against the live server. The server is the oracle and no text it prints is copied into an expectation. A float is built as mantissa * 2^exponent, which is exact in a double. The server computes it with power(), the image with integers and fractions, so the two sides share no text format. Reading compares the value that P3 reads with the one the image computes. Writing asks the server to compare the bound value with the one it computes.
"
Class {
	#name : 'P3FloatServerTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3FloatServerTest >> allPairs [
	^ self fixedPairs , self randomPairs
]

{ #category : 'private' }
P3FloatServerTest >> assertSame: actual as: expected description: aString [
	"Same double. NaN is the same as NaN, and zero keeps its sign."

	| same |
	same := (actual isFloat and: [ expected isFloat ])
		and: [ expected isNaN
			ifTrue: [ actual isNaN ]
			ifFalse: [ actual = expected and: [ actual printString = expected printString ] ] ].
	self assert: same description: aString , ': got ' , actual printString , ', wanted ' , expected printString
]

{ #category : 'fixtures' }
P3FloatServerTest >> fixedPairs [
	"Mantissa and exponent. The value is mantissa * 2^exponent, with a mantissa of at most 53 bits."

	| widest |
	widest := (1 bitShift: 53) - 1.
	^ {
		1 -> 0.
		1 -> -1.
		3 -> 1.
		-5 -> 0.
		1 -> 100.
		-1 -> 300.
		1 -> -300.
		widest -> 0.
		widest negated -> 0.
		widest -> 960.
		widest -> 971.
		widest -> -1000.
		1 -> -1022.
		1 -> -1074.
		(1 bitShift: 52) -> 11.
		123456789 -> 40 }
]

{ #category : 'fixtures' }
P3FloatServerTest >> randomPairs [
	"150 pairs from a fixed seed. The product stays finite and normal."

	| random |
	random := Random seed: 20260930.
	^ (1 to: 150) collect: [ :each | | mantissa |
		mantissa := (random nextInt: (1 bitShift: 52)) + (1 bitShift: 52).
		(random nextInt: 2) = 1 ifTrue: [ mantissa := mantissa negated ].
		mantissa -> ((random nextInt: 1900) - 1000) ]
]

{ #category : 'private' }
P3FloatServerTest >> readOf: aSelectSql [
	^ (client query: aSelectSql) firstFieldOfFirstRecord
]

{ #category : 'private' }
P3FloatServerTest >> serverSqlOfPair: aPair [
	"The server builds the same double with power(), no text format of mine is involved."

	^ '(({1})::float8 * power(2::float8, {2}))' format: { aPair key printString. aPair value printString }
]

{ #category : 'tests-writing' }
P3FloatServerTest >> testBoundFloatArrayEqualsOneTheServerBuilds [
	"Floats as array elements, including the values that have no digits."

	| pairs values sql |
	pairs := self fixedPairs.
	values := (pairs collect: [ :each | self valueOfPair: each ]) , { Float nan. Float infinity. Float infinity negated. -0.0 }.
	sql := 'SELECT $1::float8[] = ARRAY[' , (', ' join: (pairs collect: [ :each | self serverSqlOfPair: each ])) , ', ''NaN''::float8, ''Infinity''::float8, ''-Infinity''::float8, -(0::float8)]'.
	self assert: (self preparedValueOf: sql with: { values }) description: 'prepared array'.
	self assert: (self valueOf: sql with: { values }) description: 'formatted array'
]

{ #category : 'tests-writing' }
P3FloatServerTest >> testBoundFloatEqualsOneTheServerBuilds [
	"The server compares what P3 wrote with the double it builds itself."

	self allPairs do: [ :pair | | sql value |
		value := self valueOfPair: pair.
		sql := 'SELECT $1::float8 = ' , (self serverSqlOfPair: pair).
		self assert: (self valueOf: sql with: { value }) description: 'formatted write of ' , pair printString.
		self assert: (self preparedValueOf: sql with: { value }) description: 'prepared write of ' , pair printString ]
]

{ #category : 'tests-writing' }
P3FloatServerTest >> testBoundFloatRoundTripsExactly [
	"P3 writes, the server parses and returns the value, P3 reads it. The tests above find a reader and a writer error that cancel out."

	self allPairs do: [ :pair | | value |
		value := self valueOfPair: pair.
		self
			assertSame: (self valueOf: 'SELECT $1::float8' with: { value })
			as: value
			description: 'formatted round trip of ' , pair printString.
		self
			assertSame: (self preparedValueOf: 'SELECT $1::float8' with: { value })
			as: value
			description: 'prepared round trip of ' , pair printString ]
]

{ #category : 'tests-writing' }
P3FloatServerTest >> testBoundNegativeZeroReachesServerAsNegativeZero [
	"atan2(0, x) is pi for a negative zero and 0 for a positive one. The server decides by the sign, not by text."

	| sql |
	sql := 'SELECT atan2(0::float8, $1::float8) > 3'.
	self assert: (self valueOf: sql with: { -0.0 }) description: 'formatted'.
	self assert: (self preparedValueOf: sql with: { -0.0 }) description: 'prepared'.
	self deny: (self valueOf: sql with: { 0.0 }) description: 'formatted positive'.
	self deny: (self preparedValueOf: sql with: { 0.0 }) description: 'prepared positive'
]

{ #category : 'tests-writing' }
P3FloatServerTest >> testBoundNonFiniteFloatsEqualTheServersOwn [
	"NaN equals NaN in the server, so equality tells the value arrived."

	#( #( 'NaN' ) #( 'Infinity' ) #( '-Infinity' ) ) do: [ :each | | sql value |
		value := each first = 'NaN' ifTrue: [ Float nan ] ifFalse: [ each first = 'Infinity' ifTrue: [ Float infinity ] ifFalse: [ Float infinity negated ] ].
		sql := 'SELECT $1::float8 = ''' , each first , '''::float8'.
		self assert: (self valueOf: sql with: { value }) description: 'formatted ' , each first.
		self assert: (self preparedValueOf: sql with: { value }) description: 'prepared ' , each first ]
]

{ #category : 'tests-reading' }
P3FloatServerTest >> testFloat4BuiltByServerIsReadWithinItsPrecision [
	"The server writes the fewest digits that identify the float4, so the double read from them differs from the float4 by less than its precision."

	| random |
	random := Random seed: 20260930.
	150 timesRepeat: [ | pair expected actual |
		pair := ((random nextInt: (1 bitShift: 24)) * ((random nextInt: 2) = 1 ifTrue: [ 1 ] ifFalse: [ -1 ])) -> ((random nextInt: 200) - 100).
		expected := self valueOfPair: pair.
		actual := self readOf: 'SELECT ' , (self serverSqlOfPair: pair) , '::float4'.
		self
			assert: (actual isFloat and: [ (actual - expected) abs <= (expected abs * 1.0e-6) ])
			description: 'float4 ' , pair printString , ': got ' , actual printString , ', wanted ' , expected printString ]
]

{ #category : 'tests-reading' }
P3FloatServerTest >> testFloat8ArrayBuiltByServerIsReadExactly [
	| pairs expected actual |
	pairs := self fixedPairs , (self randomPairs first: 30).
	expected := pairs collect: [ :each | self valueOfPair: each ].
	actual := self readOf: 'SELECT ARRAY[' , (', ' join: (pairs collect: [ :each | self serverSqlOfPair: each ])) , ']'.
	self assert: actual size equals: expected size.
	actual with: expected do: [ :got :wanted |
		self assertSame: got as: wanted description: 'float8 array element' ]
]

{ #category : 'tests-reading' }
P3FloatServerTest >> testFloat8BuiltByServerIsReadExactly [
	self allPairs do: [ :pair |
		self
			assertSame: (self readOf: 'SELECT ' , (self serverSqlOfPair: pair))
			as: (self valueOfPair: pair)
			description: 'float8 ' , pair printString ]
]

{ #category : 'tests-reading' }
P3FloatServerTest >> testNegativeZeroBuiltByServerKeepsItsSign [
	"The server negates a zero. Unary minus on a float zero gives minus zero."

	self assertSame: (self readOf: 'SELECT -(0::float8)') as: -0.0 description: 'float8'.
	self assertSame: (self readOf: 'SELECT -(0::float4)') as: -0.0 description: 'float4'.
	self assertSame: (self readOf: 'SELECT 0::float8') as: 0.0 description: 'positive zero'.
	self assertSame: ((self readOf: 'SELECT ARRAY[-(0::float8), 0::float8]') first) as: -0.0 description: 'array'
]

{ #category : 'tests-reading' }
P3FloatServerTest >> testNonFiniteValuesAreRead [
	self assert: (self readOf: 'SELECT ''NaN''::float8') isNaN.
	self assert: (self readOf: 'SELECT ''NaN''::float4') isNaN.
	self assert: (self readOf: 'SELECT ''Infinity''::float8') equals: Float infinity.
	self assert: (self readOf: 'SELECT ''-Infinity''::float8') equals: Float infinity negated.
	self assert: (self readOf: 'SELECT ''Infinity''::float4') equals: Float infinity.
	self assert: (self readOf: 'SELECT ''-Infinity''::float4') equals: Float infinity negated.
	self assert: (self readOf: 'SELECT ARRAY[''NaN'', ''Infinity'', ''-Infinity'']::float8[]') third equals: Float infinity negated
]

{ #category : 'private' }
P3FloatServerTest >> valueOfPair: aPair [
	"The double mantissa * 2^exponent, exact."

	^ (aPair key * (2 raisedTo: aPair value)) asFloat
]
