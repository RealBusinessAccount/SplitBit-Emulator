; A program that bases one segment and forgets the other.
;
; This is the shape of a real bug: the original Fib-8, brought over to CosmOS as an
; application, based its code at 0x2000 but got its Data Segment from an included library
; and never based it. The three bytes went to 0x0000, on top of the console's own
; variables, and it appeared to work because those three bytes are scratch that readLine
; rewrites before every use. A larger data segment would have reached the decimal table
; and the mounted filesystem behind it, and failed somewhere else entirely.
;
; Nothing relocates, so the assembler is the last place to catch it.

#Program

    #Base 0x2000

start:
  HALT

#Data

value:
  0x00
