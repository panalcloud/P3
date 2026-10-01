Extension { #name : 'UUID' }

{ #category : '*P3' }
UUID >> p3PrintUsing: delegate on: stream [
	"Print me on stream via double dispatch on delegate.
	Check the implementors of #p3PrintUsing:on:"

	delegate printUUID: self on: stream
]
