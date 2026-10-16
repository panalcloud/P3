"
I test the opt-in fallback of P3Client>>#enableUnknownTypesAsText: where a column type P3 has no converter for is answered as the text the server sent, and the connection stays usable. The fallback survives a reconnect, and P3Client class>>#unknownTypesAsTextByDefault: makes it the default of new clients.
"
Class {
	#name : 'P3UnknownTypeTest',
	#superclass : 'P3ResponseTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'running' }
P3UnknownTypeTest >> setUp [
	super setUp.
	client enableUnknownTypesAsText: true
]

{ #category : 'tests' }
P3UnknownTypeTest >> testClassSideDefaultAppliesToNewClients [
	| other |
	[ P3Client unknownTypesAsTextByDefault: true.
	other := P3Client new url: P3ClientTest url; yourself.
	self assert: other isUnknownTypesAsTextEnabled.
	[ self assert: (other query: 'SELECT ''10.0.0.1''::inet') firstFieldOfFirstRecord equals: '10.0.0.1' ]
		ensure: [ other close ].
	P3Client unknownTypesAsTextByDefault: false.
	self deny: P3Client new isUnknownTypesAsTextEnabled ]
		ensure: [ P3Client unknownTypesAsTextByDefault: false ]
]

{ #category : 'tests' }
P3UnknownTypeTest >> testFallbackCanBeDisabledAgain [
	client enableUnknownTypesAsText: false.
	self deny: client isUnknownTypesAsTextEnabled.
	self should: [ client query: 'SELECT ''10.0.0.1''::inet' ] raise: P3Error
]

{ #category : 'tests' }
P3UnknownTypeTest >> testFallbackSurvivesReconnect [
	self assert: client isUnknownTypesAsTextEnabled.
	client close.
	self
		assert: (client query: 'SELECT ''10.0.0.1''::inet') firstFieldOfFirstRecord
		equals: '10.0.0.1'
]

{ #category : 'tests' }
P3UnknownTypeTest >> testUnknownScalarTypesAnswerTheirText [
	"inet, cidr, macaddr, money, xml and ranges have no converter."

	#( #( 'SELECT ''10.0.0.1/8''::inet' '10.0.0.1/8' )
	   #( 'SELECT ''10.0.0.0/8''::cidr' '10.0.0.0/8' )
	   #( 'SELECT ''08:00:2b:01:02:03''::macaddr' '08:00:2b:01:02:03' )
	   #( 'SELECT ''<a/>''::xml' '<a/>' )
	   #( 'SELECT ''[1,5)''::int4range' '[1,5)' )
	   #( 'SELECT ''a & b''::tsquery' '''a'' & ''b''' ) ) do: [ :each |
		self
			assert: (client query: each first) firstFieldOfFirstRecord
			equals: each second ]
]

{ #category : 'tests' }
P3UnknownTypeTest >> testUnknownTypeInPreparedStatementAnswersItsText [
	| statement |
	statement := client prepare: 'SELECT $1::inet' named: 'p3_unknown_type_test'.
	self
		assert: (statement query: #( '10.0.0.1' )) firstFieldOfFirstRecord
		equals: '10.0.0.1'
]

{ #category : 'tests' }
P3UnknownTypeTest >> testUnknownTypeKeepsConnectionInStep [
	(client query: 'SELECT ''10.0.0.1''::inet, 1 FROM generate_series(1, 3)') data.
	self
		assert: (client query: 'SELECT 111') data
		equals: #( #( 111 ) )
]
