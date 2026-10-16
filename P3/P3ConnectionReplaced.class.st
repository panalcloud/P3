"
I get signalled by a P3Client that lost its connection outside a transaction and opened a new one on its own. The new connection is a new server session: SET values, temporary tables, LISTEN registrations, advisory locks and server side prepared statements of the old one are gone. P3PreparedStatement prepares itself again, the rest is up to the handler. I am resumable and ignored when unhandled.
"
Class {
	#name : 'P3ConnectionReplaced',
	#superclass : 'Notification',
	#category : 'P3-Core',
	#package : 'P3',
	#tag : 'Core'
}
