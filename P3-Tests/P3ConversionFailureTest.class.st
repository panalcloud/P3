"
I test what happens to a P3Client connection when converting a field value fails.

The converter raises from inside the loop that reads the rows of a response. The rest of that response (remaining DataRow, CommandComplete, ReadyForQuery) must be read before the error is passed on, otherwise the next query on the same connection reads the previous query's messages.

My tests make int4 unconvertible on purpose (see #withUnconvertibleInt4Do:) instead of relying on a type P3Converter happens not to cover, so they keep testing the recovery path as P3TypeMap standard grows.

Configure the connection through P3ClientTest class >> #url:, like the other tests in this package.
"
Class {
	#name : 'P3ConversionFailureTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'accessing' }
P3ConversionFailureTest >> expectedFailures [
	^ #( #testConnectionAnswersItsOwnQueriesAfterFailureOnMultipleRows #testConnectionAnswersItsOwnQueriesAfterFailureOnSingleRow #testConnectionAnswersItsOwnQueriesAfterNonP3ErrorInConverter #testIsWorkingAfterConversionFailure )
]

{ #category : 'private' }
P3ConversionFailureTest >> int4Oid [
	"The type OID I break to simulate a value P3 cannot convert."

	^ 23
]

{ #category : 'tests' }
P3ConversionFailureTest >> testConnectionAnswersItsOwnQueriesAfterFailureOnMultipleRows [
	"Failing on the first of several rows leaves DataRow messages in the stream. The next query
	reads one of them with no row description at all, so it fails inside processDataRowUsing:
	instead of answering something wrong."

	self
		should: [ self withUnconvertibleInt4Do: [
			client query: 'SELECT * FROM generate_series(1, 5)' ] ]
		raise: P3Error.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests' }
P3ConversionFailureTest >> testConnectionAnswersItsOwnQueriesAfterFailureOnSingleRow [
	"One unread DataRow plus CommandComplete and ReadyForQuery are left in the stream. The next
	query reads the CommandComplete, answers a result with no descriptions and no data, and the
	query after that answers the previous one."

	self
		should: [ self withUnconvertibleInt4Do: [ client query: 'SELECT 1' ] ]
		raise: P3Error.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests' }
P3ConversionFailureTest >> testConnectionAnswersItsOwnQueriesAfterNonP3ErrorInConverter [
	"Any exception escaping a converter leaves the response unread, not only the P3Error for an
	unknown type OID, so recovery cannot be attached to P3Error alone."

	self
		should: [ self withInt4ConversionFailing: [ 1 / 0 ] do: [ client query: 'SELECT 1' ] ]
		raise: ZeroDivide.
	self assertConnectionAnswersItsOwnQueries
]

{ #category : 'tests' }
P3ConversionFailureTest >> testConversionFailureIsSignalledAsLocalP3Error [
	"The error itself is already reported correctly. This guards the shape of the error while the
	recovery around it changes."

	| error |
	error := nil.
	[ self withUnconvertibleInt4Do: [ client query: 'SELECT 1' ] ]
		on: P3Error
		do: [ :signalled | error := signalled ].
	self assert: error notNil.
	self assert: error isLocal.
	self assert: error code equals: 'P3030'.
	self assert: error messageText equals: 'Cannot convert type with OID 23'
]

{ #category : 'tests' }
P3ConversionFailureTest >> testIsWorkingAfterConversionFailure [
	"isWorking is the client's own answer to 'can I still talk to the server'. It must not say yes
	while the protocol stream is one response behind."

	self
		should: [ self withUnconvertibleInt4Do: [ client query: 'SELECT 1' ] ]
		raise: P3Error.
	self assert: client isWorking
]

{ #category : 'private' }
P3ConversionFailureTest >> withInt4ConversionFailing: failureBlock do: aBlock [
	"Evaluate aBlock while int4 values cannot be converted: my client's converter runs
	failureBlock instead. This reproduces a conversion failure at exactly the point where
	P3Converter signals one, for any server and any typeMap. The standard int4 converter is
	always restored."

	^ [ client converter
			mapOid: self int4Oid
			type: #int4
			to: [ :bytes :length :description | failureBlock value ].
	  aBlock value ]
		ensure: [ client converter
			mapOid: self int4Oid
			type: #int4
			to: #convertIntegerFrom:length:description: ]
]

{ #category : 'private' }
P3ConversionFailureTest >> withUnconvertibleInt4Do: aBlock [
	"Evaluate aBlock while reading an int4 raises the same P3Error that an unknown type OID does."

	^ self
		withInt4ConversionFailing: [ (P3Error cannotConvertTypeOid: self int4Oid) signal ]
		do: aBlock
]
