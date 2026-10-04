"
Unit tests for P3SCRAM.

https://tools.ietf.org/html/rfc5802
https://tools.ietf.org/html/rfc7677

"
Class {
	#name : 'P3SCRAMTest',
	#superclass : 'TestCase',
	#instVars : [
		'scram'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3SCRAMTest >> handshakeWithPassword: password [
	^ self handshakeWithPassword: password salt: 'QSXCR+Q6sek8bf92' iterations: 4096
]

{ #category : 'helpers' }
P3SCRAMTest >> handshakeWithPassword: password iterations: count [
	^ self handshakeWithPassword: password salt: 'QSXCR+Q6sek8bf92' iterations: count
]

{ #category : 'helpers' }
P3SCRAMTest >> handshakeWithPassword: password salt: base64Salt [
	^ self handshakeWithPassword: password salt: base64Salt iterations: 4096
]

{ #category : 'helpers' }
P3SCRAMTest >> handshakeWithPassword: password salt: base64Salt iterations: count [
	"Answer a SCRAM exchange that has received the server challenge and has its salted password computed."

	| client handshake |
	client := P3Client new url: 'psql://user:' , password , '@localhost/db'.
	handshake := client scramSHA256.
	handshake serverFirstMessage: 'r=' , handshake clientNounce , 'srv,s=' , base64Salt , ',i=' , count asString.
	handshake saltedPassword.
	^ handshake
]

{ #category : 'running' }
P3SCRAMTest >> setUp [
	super setUp.
	scram := P3SCRAM new
]

{ #category : 'tests' }
P3SCRAMTest >> testCacheIsKeyedByPasswordSaltAndIterations [
	| a b c d |
	P3SCRAM reset.
	a := self handshakeWithPassword: 'pencil'.
	b := self handshakeWithPassword: 'pencil2'.
	c := self handshakeWithPassword: 'pencil' salt: 'W22ZaJ0SNY7soEsUEjb6gQ=='.
	d := self handshakeWithPassword: 'pencil' iterations: 5000.
	self assert: P3SCRAM store size equals: 4.
	self deny: a saltedPassword equals: b saltedPassword.
	self deny: a saltedPassword equals: c saltedPassword.
	self deny: a saltedPassword equals: d saltedPassword
]

{ #category : 'tests' }
P3SCRAMTest >> testEachHandshakeHasItsOwnStateAndNounce [
	| client first second |
	client := P3Client new url: 'psql://user:pencil@localhost/db'.
	first := client scramSHA256.
	second := client scramSHA256.
	self deny: first == second.
	self deny: first clientNounce equals: second clientNounce
]

{ #category : 'tests' }
P3SCRAMTest >> testSHA1 [
	scram sha1.
	scram user: 'user'.
	scram password: 'pencil'.
	scram clientNounce: 'fyko+d2lbbFgONRv9qkxdawL'.
	self 
		assert: scram clientFirstMessage 
		equals: 'n,,n=user,r=fyko+d2lbbFgONRv9qkxdawL'.
	scram serverFirstMessage: 'r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096'.
	self assert: scram serverNounce equals: '3rfcNHYJY1ZVvWVs7j'.
	self assert: scram salt base64Encoded equals: 'QSXCR+Q6sek8bf92'.
	self assert: scram iterations equals: 4096.
	self 
		assert: scram clientFinalMessage 
		equals: 'c=biws,r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,p=v0X8v3Bz2T0CJGbJQyF0X+HI4Ts='.
	scram serverFinalMessage: 'v=rmF9pqV8S7suAoZWja4dJRkFsKQ='
	
]

{ #category : 'tests' }
P3SCRAMTest >> testSHA256 [
	scram sha256.
	scram user: 'user'.
	scram password: 'pencil'.
	scram clientNounce: 'rOprNGfwEbeRWgbNEkqO'.
	self 
		assert: scram clientFirstMessage 
		equals: 'n,,n=user,r=rOprNGfwEbeRWgbNEkqO'.
	scram serverFirstMessage: 'r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096'.
	self assert: scram serverNounce equals: '%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0'.
	self assert: scram salt base64Encoded equals: 'W22ZaJ0SNY7soEsUEjb6gQ=='.
	self assert: scram iterations equals: 4096.
	self 
		assert: scram clientFinalMessage 
		equals: 'c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ='.
	scram serverFinalMessage: 'v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4='
	
]

{ #category : 'tests' }
P3SCRAMTest >> testSaltedPasswordIsCachedAcrossHandshakes [
	| first second |
	P3SCRAM reset.
	first := self handshakeWithPassword: 'pencil'.
	self assert: P3SCRAM store size equals: 1.
	second := self handshakeWithPassword: 'pencil'.
	self assert: P3SCRAM store size equals: 1.
	self assert: first saltedPassword equals: second saltedPassword.
	self deny: first clientNounce equals: second clientNounce
]
