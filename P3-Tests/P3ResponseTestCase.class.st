"
I am an abstract test case for reading a P3Client response.

My subclasses break a response in a specific way and then check that the connection is still positioned at the start of the next response. #assertConnectionAnswersItsOwnQueries is the shared check: it sends two queries, because an unread response shifts answers by one, so the first query after the break answers nothing and the second answers the first.

I hold one client, connected in #setUp and closed in #tearDown. Subclasses that need a second connection add their own instance variable and use #newConnectedClient.

Configure the connection through P3ClientTest class >> #url:, like the other tests in this package.
"
Class {
	#name : 'P3ResponseTestCase',
	#superclass : 'TestCase',
	#instVars : [
		'client'
	],
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}
