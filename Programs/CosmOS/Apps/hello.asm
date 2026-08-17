; This is a basic hello world program for the SplitBit CPU.
; We'll create a loop that outputs each byte of our string to Output 0, the text console.

; Include the system services so we can return.
#Include services.asm

#Program

    #Base 0x2000  ; Change two:

SETD hello        ; Change three
Start:
  LDA             ; Load a byte of the string into A.
  BRA End         ; If A is zero, branch out of the loop.
  OUTA 0x00       ; Output the value in A to Port 0, the text console.
  INCD            ; Increment the Data Pointer to the next byte of the string.
  BRI Start       ; Branch immediately to the start of the loop.

End:
  INIA 0x0A       ; We'll load a linefeed into A and output it to make it look nice.
  OUTA 0x00       ; Output it to the text console.
  ;HALT           ; Terminate the program.
  ; Instead, let's call osExit to return the system nicely. Fourth change.
  SWI osExit

#Data

  #Base 0x1000    ; Five, adjust the base of the data segment.
hello:            ; Throw a label here so we can explicitly point at this data. Six, actually.
"Hello, World!"
