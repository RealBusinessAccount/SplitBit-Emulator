; printHello.asm

; As a demonstration of the new print routines, here's a new implementation for hello.asm
; Anachronaut
; 10/27/2024

; Include the subroutine file.
#Include print.asm

#Program
Start:
SETD myString       ; Set the Data Pointer to the string we want to print.
CALL printString    ; Call the subroutine.
CALL lineFeed       ; Call the linefeed subroutine.
HALT                ; Stop the CPU.

#Data

myString:
  "Hello, World!"
