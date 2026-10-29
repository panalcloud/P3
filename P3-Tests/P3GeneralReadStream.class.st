"
I am a ReadStream that P3Converter does not read with its fast readers: they only take a plain ReadStream on the bytes of a message. Values read from me go through the general readers (the character encoder, Integer class>>#readFrom:base:, ScaledDecimal class>>#readFrom:, P3ISO8601Parser), so P3ConverterFastPathTest compares the two.
"
Class {
	#name : 'P3GeneralReadStream',
	#superclass : 'ReadStream',
	#category : 'P3-Tests',
	#package : 'P3-Tests'
}
