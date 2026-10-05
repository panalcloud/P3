"
I test how P3Client reads the sslmode of its url. A mode that P3 cannot honour must raise: it must never end up connecting without TLS when the url asks for TLS. No server is needed, the url is checked when it is set.
"
Class {
	#name : 'P3SslModeTest',
	#superclass : 'TestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3SslModeTest >> assertModeIsRefused: aMode [
	| error |
	error := [ self clientWithMode: aMode. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil description: 'sslmode=' , aMode , ' was accepted, the client would connect without TLS'.
	self assert: error code equals: 'P3037'.
	self assert: (error messageText includesSubstring: aMode)
]

{ #category : 'helpers' }
P3SslModeTest >> clientWithMode: aMode [
	^ P3Client new url: 'psql://user@localhost:5432/db?sslmode=' , aMode
]

{ #category : 'tests' }
P3SslModeTest >> testDisableMeansNoTls [
	self deny: (self clientWithMode: 'disable') isSSL
]

{ #category : 'tests' }
P3SslModeTest >> testNoSslModeMeansNoTls [
	self deny: (P3Client new url: 'psql://user@localhost/db') isSSL
]

{ #category : 'tests' }
P3SslModeTest >> testOpportunisticModesAreRefused [
	"prefer and allow may fall back to plain text, which P3 does not implement either way."

	self assertModeIsRefused: 'prefer'.
	self assertModeIsRefused: 'allow'
]

{ #category : 'tests' }
P3SslModeTest >> testRequireMeansTls [
	self assert: (self clientWithMode: 'require') isSSL
]

{ #category : 'tests' }
P3SslModeTest >> testUnixSocketUrlChecksTheModeToo [
	self
		should: [ P3Client new url: 'postgresql:///db?host=/tmp&user=u&sslmode=verify-full' ]
		raise: P3Error
]

{ #category : 'tests' }
P3SslModeTest >> testUnknownAndEmptyModesAreRefused [
	"Case matters, as in libpq. A typo must not turn TLS off."

	self assertModeIsRefused: 'REQUIRE'.
	self assertModeIsRefused: 'requre'.
	self assertModeIsRefused: ''
]

{ #category : 'tests' }
P3SslModeTest >> testVerifyModesAreRefused [
	"P3 does not check the server certificate or its host name, so it cannot honour these."

	self assertModeIsRefused: 'verify-ca'.
	self assertModeIsRefused: 'verify-full'
]
