"
I test the names that P3Client>>prepare: gives to statements. The server keeps at most 63 bytes of a name, not characters, and refuses a name that is already in use in the session. Two different queries must never end up with the same name, and preparing the same query twice must not fail.
"
Class {
	#name : 'P3PreparedStatementNameTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3PreparedStatementNameTest >> byteSizeOf: aString [
	^ (ZnCharacterEncoder utf8 encodeString: aString) size
]

{ #category : 'helpers' }
P3PreparedStatementNameTest >> nonAsciiQuery: suffix [
	"A query of 50 characters that is more than 63 bytes long once encoded, and that differs from
	another one only at its end."

	^ 'SELECT ''' , (String new: 40 withAll: (Character value: 241)) , suffix , ''''
]

{ #category : 'tests' }
P3PreparedStatementNameTest >> testExplicitNameInUseByAnotherQueryIsStillRefused [
	| statement error |
	statement := client prepare: 'SELECT 1' named: 'p3_name_test'.
	error := [ client prepare: 'SELECT 2' named: 'p3_name_test'. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil.
	self assert: error code equals: '42P05'.
	self assert: (client query: 'SELECT 3') firstFieldOfFirstRecord equals: 3.
	statement close
]

{ #category : 'tests' }
P3PreparedStatementNameTest >> testLongAsciiQueriesDifferingAfterTheLimitGetDistinctNames [
	| prefix first second |
	prefix := 'SELECT ''' , (String new: 80 withAll: $x).
	first := client prepare: prefix , '1'''.
	second := client prepare: prefix , '2'''.
	self deny: first name equals: second name.
	first close.
	second close
]

{ #category : 'tests' }
P3PreparedStatementNameTest >> testNameNeverExceedsTheServerLimitInBytes [
	{ 'SELECT 1'.
	  self nonAsciiQuery: 'a'.
	  'SELECT ''' , (String new: 200 withAll: $x) , ''''.
	  'SELECT ''' , (String new: 100 withAll: (Character value: 8364)) , '''' } do: [ :each |
		| statement |
		statement := client prepare: each.
		self assert: (self byteSizeOf: statement name) <= 63 description: 'Name of ' , each printString.
		statement close ]
]

{ #category : 'tests' }
P3PreparedStatementNameTest >> testNonAsciiQueriesThatShareTheirFirst63BytesGetDistinctNames [
	| first second text |
	text := String new: 40 withAll: (Character value: 241).
	self assert: (self nonAsciiQuery: 'a') size < 63.
	first := client prepare: (self nonAsciiQuery: 'a').
	second := client prepare: (self nonAsciiQuery: 'b').
	self deny: first name equals: second name.
	self assert: (first query: #()) firstFieldOfFirstRecord equals: text , 'a'.
	self assert: (second query: #()) firstFieldOfFirstRecord equals: text , 'b'.
	first close.
	second close
]

{ #category : 'tests' }
P3PreparedStatementNameTest >> testPreparingAfterCloseAnswersANewWorkingStatement [
	| first second |
	first := client prepare: 'SELECT $1::int + 1'.
	first close.
	second := client prepare: 'SELECT $1::int + 1'.
	self deny: second == first.
	self assert: (second query: #(1)) firstFieldOfFirstRecord equals: 2.
	self should: [ first query: #(1) ] raise: P3Error.
	second close
]

{ #category : 'tests' }
P3PreparedStatementNameTest >> testPreparingTheSameQueryTwiceAnswersTheSameStatement [
	| first second |
	first := client prepare: 'SELECT $1::int + 1'.
	second := client prepare: 'SELECT $1::int + 1'.
	self assert: second == first.
	self assert: (second query: #(1)) firstFieldOfFirstRecord equals: 2.
	first close
]

{ #category : 'tests' }
P3PreparedStatementNameTest >> testQueryPreparedBeforeAReplacementIsPreparedAgainByPrepare [
	"The statement of a lost session is not handed out: it is prepared again first."

	| first second |
	first := client prepare: 'SELECT $1::int + 1'.
	[ client query: 'SELECT pg_terminate_backend(pg_backend_pid())' ] on: P3Error do: [ :e | e return ].
	second := client prepare: 'SELECT $1::int + 1'.
	self assert: (second query: #(1)) firstFieldOfFirstRecord equals: 2.
	second close
]

{ #category : 'tests' }
P3PreparedStatementNameTest >> testShortQueryIsItsOwnName [
	| statement |
	statement := client prepare: 'SELECT 1'.
	self assert: statement name equals: 'SELECT 1'.
	statement close
]
