Extension { #name : 'Float' }

{ #category : '*P3' }
Float >> p3PrintUsing: delegate on: stream [
	"Print me on stream via double dispatch on delegate.
	Check the implementors of #p3PrintUsing:on:"

	delegate printFloat: self on: stream
]
