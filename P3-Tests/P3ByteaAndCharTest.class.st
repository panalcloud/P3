"
I test reading bytea in both bytea_output formats, and the single byte type ""char"". I need a server, see P3ClientTest class >> #url.
"
Class {
	#name : 'P3ByteaAndCharTest',
	#superclass : 'P3StatementTestCase',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'accessing' }
P3ByteaAndCharTest >> expectedFailures [
	^ #( #testByteaReadsTheEscapeFormat #testCharTypeReadsEveryByteValue #testEscapeFormatTextWithoutAServer )
]

{ #category : 'tests' }
P3ByteaAndCharTest >> testByteaReadsTheEscapeFormat [
	"The server writes bytea as hex or in the escape format, depending on bytea_output."

	| sql |
	sql := 'SELECT ''\x00ff415c7e5c5c''::bytea, ''\x''::bytea, ''\x5c78''::bytea'.
	client execute: 'SET bytea_output = escape'.
	self assert: (client query: sql) firstRecord equals: { #[0 255 65 92 126 92 92]. #[]. #[92 120] }.
	client execute: 'SET bytea_output = hex'.
	self assert: (client query: sql) firstRecord equals: { #[0 255 65 92 126 92 92]. #[]. #[92 120] }
]

{ #category : 'tests' }
P3ByteaAndCharTest >> testCharTypeReadsEveryByteValue [
	"The server writes the zero byte as an empty text and a byte with the high bit set as a backslash and three octal digits."

	| values |
	values := (client query: 'SELECT 0::"char", 65::"char", 92::"char", (-128)::"char", (-1)::"char"') firstRecord.
	self assert: values equals: { Character value: 0. $A. $\. Character value: 128. Character value: 255 }
]

{ #category : 'tests' }
P3ByteaAndCharTest >> testEscapeFormatTextWithoutAServer [
	| converter |
	converter := P3Converter new.
	self assert: (converter byteArrayFromEscapeFormat: 'a\\b\000\377z' asByteArray) equals: #[97 92 98 0 255 122].
	self should: [ converter byteArrayFromEscapeFormat: '\9zz' asByteArray ] raise: P3Error.
	self should: [ converter octalValueOf: 'xyz' asByteArray ] raise: P3Error
]
