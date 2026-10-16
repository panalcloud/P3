"
I test which authentication methods a P3Client accepts, see P3Client>>#requireAuth:. A method that is not accepted fails the connect before anything secret is sent. The server of P3ClientTest class >> #url is expected to ask for SCRAM-SHA-256.
"
Class {
	#name : 'P3AuthenticationTest',
	#superclass : 'TestCase',
	#instVars : [
		'client'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'private' }
P3AuthenticationTest >> clientRequiring: methods [
	^ client := P3Client new url: P3ClientTest url; requireAuth: methods; yourself
]

{ #category : 'running' }
P3AuthenticationTest >> tearDown [
	client ifNotNil: [ [ client close ] on: Error do: [ :error | ] ].
	super tearDown
]

{ #category : 'tests' }
P3AuthenticationTest >> testAMethodThatIsNotRequiredFailsTheConnect [
	| error |
	error := [ (self clientRequiring: #( 'md5' )) connect. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil.
	self assert: error code equals: 'P3023'.
	self deny: client isConnected
]

{ #category : 'tests' }
P3AuthenticationTest >> testCleartextPasswordNeedsTlsByDefault [
	| plain |
	plain := P3Client new url: 'psql://user:secret@localhost/db'.
	self deny: (plain isAuthenticationAllowed: 'password').
	self assert: (plain isAuthenticationAllowed: 'md5').
	self assert: (plain isAuthenticationAllowed: 'scram-sha-256').
	self assert: (plain isAuthenticationAllowed: 'none').
	plain requireAuth: #( 'password' ).
	self assert: (plain isAuthenticationAllowed: 'password')
]

{ #category : 'tests' }
P3AuthenticationTest >> testNoAuthenticationIsRefusedUnlessRequired [
	"A server that answers AuthenticationOk without asking for anything proves nothing about itself."

	self deny: ((P3Client new requireAuth: #( 'scram-sha-256' ); yourself) isAuthenticationAllowed: 'none').
	self assert: ((P3Client new requireAuth: #( 'none' 'scram-sha-256' ); yourself) isAuthenticationAllowed: 'none')
]

{ #category : 'tests' }
P3AuthenticationTest >> testRefusedCleartextPasswordIsNotSent [
	"The refusal comes before the password is written: there is no connection to write it to here."

	| plain error |
	plain := P3Client new url: 'psql://user:secret@localhost/db'.
	error := [ plain handleAuthentication: 3. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil.
	self assert: error code equals: 'P3023'
]

{ #category : 'tests' }
P3AuthenticationTest >> testRequireAuthCanBeGivenInTheUrl [
	self
		assert: (P3Client new url: 'psql://user@localhost/db?require_auth=scram-sha-256,md5') requireAuth
		equals: #( 'scram-sha-256' 'md5' ).
	self assert: (P3Client new url: 'psql://user@localhost/db') requireAuth isNil
]

{ #category : 'tests' }
P3AuthenticationTest >> testScramIsAcceptedWhenRequired [
	self assert: (self clientRequiring: #( 'scram-sha-256' )) isWorking
]

{ #category : 'tests' }
P3AuthenticationTest >> testUnknownMethodNamesAreRefused [
	self should: [ P3Client new requireAuth: #( 'scram' ) ] raise: P3Error
]
