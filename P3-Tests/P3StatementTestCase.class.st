"
Abstract superclass for tests that need a live PostgreSQL connection. It opens one client per test and closes it afterwards, so a test can change session settings freely. The helpers run a statement through a formatted statement or a prepared statement and answer the first value read back.
"
Class {
	#name : 'P3StatementTestCase',
	#superclass : 'TestCase',
	#instVars : [
		'client'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'testing' }
P3StatementTestCase class >> isAbstract [
	"The abstract classes have no tests of their own."

	^ self == P3StatementTestCase
]

{ #category : 'helpers' }
P3StatementTestCase >> assertConnectionAnswersItsOwnQueries [
	"Two queries in a row: a response left unread shifts the first answer to the second query."

	self assert: (client query: 'SELECT 111') firstFieldOfFirstRecord equals: 111.
	self assert: (client query: 'SELECT 222') firstFieldOfFirstRecord equals: 222
]

{ #category : 'helpers' }
P3StatementTestCase >> boundSqlOf: sqlTemplate with: arguments [
	"Answer the SQL text that a formatted statement writes for sqlTemplate and arguments."

	^ (client format: sqlTemplate) bind: arguments
]

{ #category : 'helpers' }
P3StatementTestCase >> preparedValueOf: sqlTemplate with: arguments [
	"Run sqlTemplate as a prepared statement with arguments and answer the single value read back."

	| statement |
	statement := client prepare: sqlTemplate.
	^ [ (statement query: arguments) firstFieldOfFirstRecord ] ensure: [ statement close ]
]

{ #category : 'helpers' }
P3StatementTestCase >> rowsOf: sqlTemplate with: arguments [
	"Run sqlTemplate as a formatted statement and answer all the rows read back."

	^ ((client format: sqlTemplate) query: arguments) records
]

{ #category : 'running' }
P3StatementTestCase >> setUp [
	super setUp.
	client := P3Client new.
	client url: P3ClientTest url.
	client timeout: 10. "second"
	client connect
]

{ #category : 'running' }
P3StatementTestCase >> tearDown [
	client ifNotNil: [ client close ].
	super tearDown
]

{ #category : 'helpers' }
P3StatementTestCase >> valueOf: sqlTemplate with: arguments [
	"Run sqlTemplate as a formatted statement with arguments and answer the single value read back."

	^ ((client format: sqlTemplate) query: arguments) firstFieldOfFirstRecord
]
