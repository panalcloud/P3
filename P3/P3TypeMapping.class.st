"
I am one entry of a P3TypeMap: the type OID, the type name, and the converter that reads values of that type. The converter is a selector understood by P3Converter, or a block taking bytes, length and description.
"
Class {
	#name : 'P3TypeMapping',
	#superclass : 'Object',
	#instVars : [
		'oid',
		'name',
		'converter'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}
