"
I am a statement parameter that cannot be written.

P3PreparedStatement builds a Bind message per row by sending #p3PrintUsing:on: to each value. I raise instead, so a test can make the building of one row of a batch fail and check that none of the rows reached the server.
"
Class {
	#name : 'P3FailingParameter',
	#superclass : 'Object',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}

{ #category : 'printing' }
P3FailingParameter >> p3PrintUsing: messageBuilder on: stream [
	"Fail the way any value whose printing raises does."

	^ 1 / 0
]
