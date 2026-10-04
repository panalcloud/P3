"
Tests which parts of a SQL template P3FormattedStatement replaces placeholders in. Only a $n outside string literals, dollar quoted bodies, quoted identifiers, identifiers and comments is a placeholder. The literal tests inspect the bound text, the server tests run it.
"
Class {
	#name : 'P3FormattedStatementPlaceholderTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'helpers' }
P3FormattedStatementPlaceholderTest >> assertTemplate: aTemplate with: arguments bindsTo: expectedSql [
	self assert: (self boundSqlOf: aTemplate with: arguments) equals: expectedSql
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testDifferentDollarTagDoesNotCloseBody [
	"Only a closing tag equal to the opening tag ends the body."

	self
		assertTemplate: 'SELECT $a$ $b$ $1 $a$, $1'
		with: { 5 }
		bindsTo: 'SELECT $a$ $b$ $1 $a$, 5'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testDollarInsideIdentifierIsKept [
	"A dollar sign is a valid character inside an identifier."

	self assertTemplate: 'SELECT 1 AS col$1' with: #() bindsTo: 'SELECT 1 AS col$1'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testEscapedQuoteDoesNotEndStringLiteral [
	"A doubled quote stays inside the literal, so the $1 after it is still literal text and the last one is a placeholder."

	self
		assertTemplate: 'SELECT ''it''''s $1'', $1'
		with: { 5 }
		bindsTo: 'SELECT ''it''''s $1'', 5'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testNestedBlockCommentEndsAtOutermostCloser [
	"PostgreSQL block comments nest, so the first */ does not end the comment."

	self
		assertTemplate: 'SELECT /* a /* b */ $1 */ $1'
		with: { 5 }
		bindsTo: 'SELECT /* a /* b */ $1 */ 5'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testPlaceholderAfterLiteralIsReplaced [
	self assertTemplate: 'SELECT ''$1'', $1' with: { 5 } bindsTo: 'SELECT ''$1'', 5'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testPlaceholderInBlockCommentIsKept [
	self
		assertTemplate: 'SELECT /* cost $1 */ $1'
		with: { 5 }
		bindsTo: 'SELECT /* cost $1 */ 5'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testPlaceholderInDollarQuotedBodyIsKept [
	self assertTemplate: 'SELECT $$cost $1$$' with: { 5 } bindsTo: 'SELECT $$cost $1$$'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testPlaceholderInEscapeStringLiteralIsKept [
	self assertTemplate: 'SELECT E''price $1''' with: { 5 } bindsTo: 'SELECT E''price $1'''
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testPlaceholderInLineCommentIsKept [
	self
		assertTemplate: 'SELECT 1 -- cost $1', String lf, ', $1'
		with: { 5 }
		bindsTo: 'SELECT 1 -- cost $1', String lf, ', 5'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testPlaceholderInQuotedIdentifierIsKept [
	self assertTemplate: 'SELECT 1 AS "col $1"' with: { 5 } bindsTo: 'SELECT 1 AS "col $1"'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testPlaceholderInStringLiteralIsKept [
	self assertTemplate: 'SELECT ''price $1''' with: { 5 } bindsTo: 'SELECT ''price $1'''
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testPlaceholderInTaggedDollarQuotedBodyIsKept [
	self assertTemplate: 'SELECT $tag$cost $1$tag$' with: { 5 } bindsTo: 'SELECT $tag$cost $1$tag$'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testQuoteInsideCommentDoesNotStartLiteral [
	self
		assertTemplate: 'SELECT 1 /* it''s */, $1'
		with: { 5 }
		bindsTo: 'SELECT 1 /* it''s */, 5'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testQuoteInsideDollarQuotedBodyDoesNotStartLiteral [
	"The single quote belongs to the dollar quoted body, so the $1 after the body is a placeholder."

	self
		assertTemplate: 'SELECT $$it''s$$, $1'
		with: { 5 }
		bindsTo: 'SELECT $$it''s$$, 5'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testRepeatedPlaceholderIsReplacedEachTime [
	self assertTemplate: 'SELECT $1 + $1' with: { 5 } bindsTo: 'SELECT 5 + 5'
]

{ #category : 'tests-server' }
P3FormattedStatementPlaceholderTest >> testServerAcceptsCommentsHoldingPlaceholders [
	"With one argument, a $2 inside a comment must not be looked up."

	self assert: (self valueOf: 'SELECT $1 /* $2 */' with: { 5 }) equals: 5.
	self assert: (self valueOf: 'SELECT $1 -- $2' with: { 5 }) equals: 5
]

{ #category : 'tests-server' }
P3FormattedStatementPlaceholderTest >> testServerBindsTextThatLooksLikePlaceholder [
	"The text of an argument is data. A $2 inside it must not be bound again."

	self assert: (self valueOf: 'SELECT $1::text' with: { 'cost $2' }) equals: 'cost $2'
]

{ #category : 'tests-server' }
P3FormattedStatementPlaceholderTest >> testServerKeepsIdentifierWithDollar [
	self assert: (self valueOf: 'SELECT 7 AS col$1' with: #()) equals: 7
]

{ #category : 'tests-server' }
P3FormattedStatementPlaceholderTest >> testServerReadsDollarQuotedBodyUnchanged [
	self assert: (self valueOf: 'SELECT $$cost $1$$' with: { 5 }) equals: 'cost $1'.
	self assert: (self valueOf: 'SELECT $q$it''s $1$q$' with: { 5 }) equals: 'it''s $1'
]

{ #category : 'tests-server' }
P3FormattedStatementPlaceholderTest >> testServerReadsJsonTextUnchanged [
	"A JSON document with a $1 inside a string value is data, not a placeholder."

	self
		assert: (self valueOf: 'SELECT (''{"a": "$1"}''::jsonb) ->> ''a''' with: { 5 })
		equals: '$1'
]

{ #category : 'tests-server' }
P3FormattedStatementPlaceholderTest >> testServerReadsStringLiteralUnchanged [
	self assert: (self valueOf: 'SELECT ''price $1''' with: { 5 }) equals: 'price $1'
]

{ #category : 'tests-literal' }
P3FormattedStatementPlaceholderTest >> testTwoDigitPlaceholderIsNotReadAsFirstDigit [
	"$10 is the tenth argument, not the first argument followed by a zero."

	self
		assertTemplate: 'SELECT $1, $10'
		with: (1 to: 10)
		bindsTo: 'SELECT 1, 10'
]
