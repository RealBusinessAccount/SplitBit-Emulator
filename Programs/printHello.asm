; printHello.asm

; As a demonstration of the new print routines, here's a new implementation for hello.asm
; Anachronaut
; 10/27/2024

; Include the subroutine file.
#Include print.asm

#Program

start:
  SETD MyString           ; Set the Data Pointer to the start of MyString.
  CALL printString        ; Call the string printing subroutine.
  CALL lineFeed           ; Call the line feed subroutine to end the line.
  SETD MyDecimal          ; Set the Data Pointer to the value to print as a decimal.
  CALL printDecimal       ; Call the decimal printing subroutine.
  SETD MyMessage          ; Set the Data Pointer to another string.
  CALL printString        ; Call the string printing subroutine again.
  CALL lineFeed           ; Call the line feed subroutine to end the line.
  HALT                    ; Stop the program.

#Data

MyString:
  "Hello, World! "

MyDecimal:
  0d42

MyMessage:
  " is the great answer."
