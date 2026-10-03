"
I test what happens to a P3Client connection when converting a field value fails.

P3Converter signals P3Error (#cannotConvertTypeOid:) from inside the row reading loop of
P3Client>>runQueryResult and P3Client>>runExtendedQueryResult:. The rest of the server response
(remaining DataRow, CommandComplete, ReadyForQuery) must be read before the error is re-signalled,
otherwise the next query on the same connection reads the previous query's messages.

Most of my tests make int4 unconvertible on purpose (see #withUnconvertibleInt4Do:) instead of
relying on a type P3Converter happens not to cover, so they keep testing the recovery path as
P3TypeMap standard grows.

#testCatalogTypesAreConvertible and #testTypeNameOfUnknownTypeOid cover the converter coverage
for pg_catalog types.

Configure the connection through P3ClientTest class >> #url:, like the other tests in this package.
"
Class {
	#name : 'P3ConversionFailureTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3ConversionFailureTest >> int4Oid [
	"The type OID I break to simulate a value P3 cannot convert."

	^ 23
]

{ #category : 'tests' }
P3ConversionFailureTest >> testCatalogTypeAclitemArrayConvertsToStringArray [
	"_aclitem (1034), the array type of aclitem (1033): read each grant entry as a raw string,
	e.g. 'alice=arwdDxt/alice', rather than parsing the grantee/privileges/grantor structure."

	| acl |
	acl := (client query: 'SELECT relacl FROM pg_class WHERE relacl IS NOT NULL LIMIT 1')
		firstFieldOfFirstRecord.
	self assert: acl class equals: Array.
	self assert: acl notEmpty.
	acl do: [ :each | self assert: each isString ]
]

{ #category : 'tests' }
P3ConversionFailureTest >> testCatalogTypeCharConvertsToCharacter [
	"""char"" (OID 18) is PostgreSQL's internal single-byte type, distinct from bpchar/varchar."

	self
		assert: (client query: 'SELECT ''x''::"char"') firstFieldOfFirstRecord
		equals: $x
]

{ #category : 'tests' }
P3ConversionFailureTest >> testCatalogTypeInt2VectorConvertsToIntegerArray [
	"int2vector (OID 22) is textually the same space-separated integer list as oidvector (30),
	just narrower elements; the same vector parser reads both."

	self
		assert: (client query: 'SELECT ''1 2''::int2vector') firstFieldOfFirstRecord
		equals: #( 1 2 )
]

{ #category : 'tests' }
P3ConversionFailureTest >> testCatalogTypePgNodeTreeConvertsToString [
	"pg_node_tree (194) is an internal serialized expression tree; read as raw text, not parsed.
	p3_test's pg_attrdef starts out empty, so create a default expression to read one back."

	client execute: 'CREATE TEMP TABLE p3_node_tree_probe (i int DEFAULT 1 + 1)'.
	self
		assert: (client
			query: 'SELECT adbin FROM pg_attrdef WHERE adrelid = ''p3_node_tree_probe''::regclass')
			firstFieldOfFirstRecord
		isString
]

{ #category : 'tests' }
P3ConversionFailureTest >> testCatalogTypeRegprocConvertsToString [
	"regproc (OID 24) prints as the plain function name."

	self
		assert: (client query: 'SELECT ''int4in''::regproc') firstFieldOfFirstRecord
		equals: 'int4in'
]

{ #category : 'tests' }
P3ConversionFailureTest >> testCatalogTypeXidAndCidConvertToIntegers [
	"xid (28) and cid (29) are the system columns xmin/cmin: unsigned transaction/command
	counters, printed as plain decimals. pg_class always has visible rows."

	| record |
	record := (client query: 'SELECT xmin, cmin FROM pg_class LIMIT 1') firstRecord.
	self assert: record first isInteger.
	self assert: record second isInteger
]

{ #category : 'tests' }
P3ConversionFailureTest >> testCatalogTypesAreConvertible [
	"pg_catalog columns should be readable without ::text casts. Each expression gets its own
	client because an unconvertible value desynchronises the connection it was read on, which
	would make every later expression fail for the wrong reason."

	| unconvertible |
	unconvertible := OrderedCollection new.
	#( #( 'SELECT ''x''::"char"' '"char"' )
	   #( 'SELECT ''1 2''::int2vector' 'int2vector' )
	   #( 'SELECT ''int4in''::regproc' 'regproc' )
	   #( 'SELECT xmin FROM pg_class LIMIT 1' 'xid' )
	   #( 'SELECT cmin FROM pg_class LIMIT 1' 'cid' )
	   #( 'SELECT adbin FROM pg_attrdef LIMIT 1' 'pg_node_tree' )
	   #( 'SELECT relacl FROM pg_class WHERE relacl IS NOT NULL LIMIT 1' '_aclitem' ) )
		do: [ :each |
			| probe |
			probe := P3Client new url: P3ClientTest url; yourself.
			[ [ probe query: each first ]
				on: P3Error
				do: [ :error | unconvertible add: each second -> error messageText ] ]
				ensure: [ [ probe close ] on: Error do: [ :error | ] ] ].
	self assert: unconvertible asArray equals: #()
]

{ #category : 'tests' }
P3ConversionFailureTest >> testConnectionAnswersItsOwnQueriesAfterFailureInPreparedStatement [
	"runExtendedQueryResult: reads rows the same way runQueryResult does and leaves the same
	messages unread. The statement is not closed: closing it needs the connection the failure
	broke, and tearDown drops the whole client anyway."

	| statement |
	statement := client prepare: 'SELECT $1::int4' named: 'p3_conversion_failure_test'.
	self
		should: [ self withUnconvertibleInt4Do: [ statement query: #( 7 ) ] ]
		raise: P3Error.
	self assertConnectionAnswersItsOwnQueries
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

{ #category : 'tests' }
P3ConversionFailureTest >> testResultConvenienceAccessorsAnswerWhenDataIsNil [
	"A P3Result with nil data (no DataRow was ever read, e.g. because the query never got a
	response) must answer, not raise: isWorking depends on firstFieldOfFirstRecord not blowing up
	on a MessageNotUnderstood when there is nothing to read."

	| result |
	result := P3Result descriptions: nil data: nil results: 'SELECT 0'.
	self assert: result firstRecord isNil.
	self assert: result firstFieldOfFirstRecord isNil.
	self assert: result firstColumnData isEmpty.
	self assert: result recordsAsDictionaries isEmpty
]

{ #category : 'tests' }
P3ConversionFailureTest >> testTypeModifierIsSigned [
	"processRowDescription: reads atttypmod with uint32, so 'no modifier' (-1) arrives as
	4294967295 and every caller has to know to normalise it."

	| descriptions |
	descriptions := (client
		prepare: 'SELECT 1::int4 AS n, ''x''::varchar(18) AS v'
		named: 'p3_conversion_failure_test_typmod') fieldDescriptions.
	self assert: (descriptions first) typeModifier equals: -1.
	self assert: (descriptions second) typeModifier equals: 22
]

{ #category : 'tests' }
P3ConversionFailureTest >> testTypeNameOfUnknownTypeOid [
	"typeName answers a Symbol for a type in P3TypeMap standard and the Integer OID for any
	other, so a caller cannot use the answer without first knowing which it got. Describing a
	statement needs no converter, so this works even for a type nothing can read.

	regclass (2205) is deliberately outside typeMap: it must stay a type P3Converter does not
	convert, or this test would pass for the wrong reason (typeName of a type P3 does know is
	trivially a Symbol, which says nothing about how it answers for an unknown one)."

	| description |
	description := (client
		prepare: 'SELECT ''pg_class''::regclass'
		named: 'p3_conversion_failure_test_typename') fieldDescriptions first.
	self assert: description typeOid equals: 2205.
	self assert: description typeName isSymbol
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
