"
I am the NeoJSONReader that P3Converter uses to read json and jsonb values.

I read exactly as NeoJSONReader does. When property names are Symbols, I find the Symbol of a name in a dictionary that the converter keeps for all the values it reads, instead of interning the name again for every object: the same few names come back in every row. The dictionary keeps at most #propertyNameLimit names, so values with ever new names do not make it grow without end; other names are interned as usual.
"
Class {
	#name : 'P3JSONReader',
	#superclass : 'NeoJSONReader',
	#instVars : [
		'propertyNames'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}

{ #category : 'accessing' }
P3JSONReader class >> propertyNameLimit [
	"The number of property names whose Symbol is kept, see #parsePropertyName"

	^ 1024
]

{ #category : 'parsing' }
P3JSONReader >> parsePropertyName [
	"As NeoJSONReader>>#parsePropertyName, with the Symbol taken from my propertyNames when it is there"

	| name |
	name := self parseValue.
	name isString
		ifFalse: [ ^ self error: 'property name must be a string, not ' , name asString ].
	(propertyNamesAsSymbols and: [ propertyNames notNil ])
		ifFalse: [ ^ propertyNamesAsSymbols ifTrue: [ name asSymbol ] ifFalse: [ name ] ].
	^ propertyNames
		at: name
		ifAbsent: [ | symbol |
			symbol := name asSymbol.
			propertyNames size < self class propertyNameLimit
				ifTrue: [ propertyNames at: name put: symbol ].
			symbol ]
]

{ #category : 'initialization' }
P3JSONReader >> propertyNames: aDictionary [
	"Use aDictionary from the String of a property name to its Symbol, and add to it"

	propertyNames := aDictionary
]
