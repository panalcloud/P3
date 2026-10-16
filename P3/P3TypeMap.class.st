"
I map PostgreSQL type OIDs to P3TypeMapping objects. The standard map (see #standard) is built once, shared and read-only. A connection works on an extension (see #extension): its own mappings are looked up first, then those of the map it extends, so a connection can add types or overload converters without touching the standard map or any other connection.
"
Class {
	#name : 'P3TypeMap',
	#superclass : 'Object',
	#instVars : [
		'mappings',
		'parent',
		'isFrozen',
		'unknownNames',
		'unknownNamesMutex'
	],
	#classVars : [
		'Standard'
	],
	#category : 'P3-Support',
	#package : 'P3',
	#tag : 'Support'
}
