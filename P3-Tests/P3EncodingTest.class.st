"
I test the text that is not row data. What P3 sends before and during authentication (user, database, password, options) is UTF-8, and the startup packet asks for client_encoding UTF8. The fields of ErrorResponse and NoticeResponse are decoded with the connection encoding, so a message that quotes user data or is translated reads as written. A test that needs a role or a database with a non ASCII name creates it and drops it again; the connecting user needs CREATEROLE and CREATEDB.
"
Class {
	#name : 'P3EncodingTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3EncodingTest >> bytes: bytes include: part [
	^ (1 to: bytes size - part size + 1) anySatisfy: [ :start |
		(bytes copyFrom: start to: start + part size - 1) = part ]
]

{ #category : 'helpers' }
P3EncodingTest >> clientFor: userName password: password database: databaseName [
	| other |
	other := P3Client new url: P3ClientTest url; yourself.
	other user: userName; password: password.
	databaseName ifNotNil: [ other database: databaseName ].
	other timeout: 10.
	^ other
]

{ #category : 'tests' }
P3EncodingTest >> testAsciiConnectionIsUnchanged [
	self assert: (client query: 'SELECT current_user') firstFieldOfFirstRecord equals: client user.
	self assert: (client query: 'SHOW client_encoding') firstFieldOfFirstRecord equals: 'UTF8'
]

{ #category : 'tests' }
P3EncodingTest >> testDatabaseNameWithNonAsciiCharactersConnects [
	| name other |
	name := 'd' , self umlaut asString , 'ta_p3'.
	client execute: 'DROP DATABASE IF EXISTS "' , name , '"'.
	client execute: 'CREATE DATABASE "' , name , '"'.
	[ other := self clientFor: client user password: client password database: name.
	[ other connect.
	self assert: (other query: 'SELECT current_database()') firstFieldOfFirstRecord equals: name ]
		ensure: [ other close ] ]
		ensure: [ client execute: 'DROP DATABASE IF EXISTS "' , name , '"' ]
]

{ #category : 'tests' }
P3EncodingTest >> testErrorMessageQuotingNonAsciiTextIsReadAsWritten [
	| error text |
	text := 'Gr' , self umlaut asString , 'sse'.
	error := [ client query: 'SELECT ''' , text , '''::int'. nil ] on: P3Error do: [ :e | e ].
	self assert: error notNil.
	self assert: (error messageText includesSubstring: text) description: error messageText
]

{ #category : 'tests' }
P3EncodingTest >> testMd5PasswordIsHashedAsUtf8 [
	| other salt credential expected |
	other := P3Client new.
	other user: 'm' , self umlaut asString , 'ller'; password: 'p' , self umlaut asString , 'ss'.
	salt := #[1 2 3 4].
	credential := (MD5 hashMessage: ('p' , self umlaut asString , 'ssm' , self umlaut asString , 'ller') utf8Encoded) hex.
	expected := 'md5' , (MD5 hashMessage: credential asByteArray , salt) hex.
	self assert: (other md5PasswordMessage: salt) equals: expected asByteArray , #[0]
]

{ #category : 'tests' }
P3EncodingTest >> testNoticeTextWithNonAsciiCharactersIsReadAsWritten [
	| text notices |
	text := 'Gr' , self umlaut asString , 'sse'.
	notices := OrderedCollection new.
	[ client execute: 'DO $$ BEGIN RAISE NOTICE ''' , text , '''; END $$' ]
		on: P3Notification
		do: [ :notification | notices add: notification messageText. notification resume ].
	self assert: notices size equals: 1.
	self assert: (notices first includesSubstring: text) description: notices first
]

{ #category : 'tests' }
P3EncodingTest >> testStartupAsksForUtf8WhateverTheRoleDefaultIs [
	"The role defaults to LATIN1. The client asks for UTF8 in the startup packet, so the session
	is UTF8 and a character outside Latin-1 is read as itself."

	| name other euro |
	name := 'enc_p3'.
	euro := Character value: 8364.
	self withRole: name password: 'secret' do: [
		other := self clientFor: name password: 'secret' database: nil.
		[ other connect.
		self assert: (other query: 'SHOW client_encoding') firstFieldOfFirstRecord equals: 'UTF8'.
		self assert: (other query: 'SELECT chr(8364)') firstFieldOfFirstRecord equals: (String with: euro) ]
			ensure: [ other close ] ]
]

{ #category : 'tests' }
P3EncodingTest >> testStartupMessageIsUtf8 [
	| other bytes |
	other := P3Client new.
	other user: 'm' , self umlaut asString , 'ller'; database: 'd' , self umlaut asString , 'ta'.
	bytes := other startupMessage.
	self assert: (self bytes: bytes include: #[109 195 188 108 108 101 114 0]) description: 'user'.
	self assert: (self bytes: bytes include: #[100 195 188 116 97 0]) description: 'database'.
	self assert: (self bytes: bytes include: 'client_encoding' asByteArray , #[0] , 'UTF8' asByteArray , #[0]) description: 'client_encoding'
]

{ #category : 'tests' }
P3EncodingTest >> testUndecodableErrorTextDoesNotHideTheError [
	"Error text that is not valid in the connection encoding must still arrive as an error."

	| converter info |
	converter := P3Converter new.
	info := (P3Client new converter: converter; yourself) errorNoticeInfo: (ReadStream on: #[77 255 254 0 0]).
	self assert: info isEmpty not.
	self assert: (info at: (Character value: 77)) size equals: 2
]

{ #category : 'tests' }
P3EncodingTest >> testUnknownServerEncodingDoesNotFailTheConnect [
	| converter |
	converter := P3Converter new.
	self shouldnt: [ converter initializeFrom: (Dictionary with: 'client_encoding' -> 'NOT_AN_ENCODING') ] raise: Error
]

{ #category : 'tests' }
P3EncodingTest >> testUserAndPasswordWithNonAsciiCharactersAuthenticate [
	| name password other |
	name := 'm' , self umlaut asString , 'ller_p3'.
	password := 'p' , self umlaut asString , 'ssword'.
	self withRole: name password: password do: [
		other := self clientFor: name password: password database: nil.
		[ other connect.
		self assert: (other query: 'SELECT current_user') firstFieldOfFirstRecord equals: name ]
			ensure: [ other close ] ]
]

{ #category : 'helpers' }
P3EncodingTest >> umlaut [
	^ Character value: 252
]

{ #category : 'helpers' }
P3EncodingTest >> withRole: roleName password: password do: aBlock [
	"Create a login role with a LATIN1 default client_encoding, evaluate aBlock, drop the role."

	client execute: 'DROP ROLE IF EXISTS "' , roleName , '"'.
	client execute: 'CREATE ROLE "' , roleName , '" LOGIN PASSWORD ''' , password , ''''.
	client execute: 'ALTER ROLE "' , roleName , '" SET client_encoding TO ''LATIN1'''.
	^ [ aBlock value ] ensure: [ client execute: 'DROP ROLE IF EXISTS "' , roleName , '"' ]
]
