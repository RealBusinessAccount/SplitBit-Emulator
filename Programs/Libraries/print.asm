; print.asm

; Some simple SplitBit subroutines for printing.
; Anachronaut
; 10/27/2024

#Program
  BRI start                 ; Branch immediately to the start of the program.

lineFeed:
  INIA 0x0A                 ; Load the character for linefeed into A.
  OUTA 0x00                 ; Output it.
  RET                       ; Return to the caller.

; Expects A to contain the number of spaces to print.
blankSpace:
  INIB 0x20                 ; Set B to the ASCII value for space.
  OUTB 0x00                 ; Print it.
  BRA printDone             ; If A is zero, we're done.
  DECA                      ; Decrement A.
  BRI blankSpace            ; Branch back to the loop again.

printString:                ; Expects Data Pointer to be set to the beginning of the string to be printed.
    LDA                     ; Move the first character of the string into A.
    BRA printDone           ; If A is NULL, the string is finished, so return.
    OUTA 0x00               ; Output the character.
    INCD                    ; Increment Data Pointer to the next character.
    BRI printString         ; Branch to the beginning of the loop.
    printDone:
    RET                     ; Return to the caller.

; Expects A to contain the value to be printed in decimal form.
printByteDecimal:
  ; Clear the buffer we're going to write into.
  SETD DecimalValue         ; Set the Data Pointer to the buffer.
  RSTB                      ; Set B to 0.
  STB                       ; Store it in the buffer.
  INCD                      ; Increment to the tens place.
  STB                       ; Store 0 in it.
  INCD                      ; Increment to the hundred's place.
  STB                       ; Store 0 in it.
  INIB 0d10                 ; Load 10 into B.
  PSHA                      ; Save the value onto the stack.
 printDecimalLoopStart:
  POPA                      ; Pop the value to A from the stack.
  CCF                       ; Clear the Carry Flag.
  SUB                       ; Subtract 10 from the value in A.
  BRC getOnes               ; If 10 is bigger than A, We're done looping and A contains the ones.
  BRA getOnes               ; If the value 0, we're also done.
  ; Otherwise, increment the tens place.
  SETD DecimalValue         ; Set the Data Pointer to the buffer.
  INCD                      ; Increment to the tens place.
  PSHQ                      ; Save the new value onto the stack.
  LDA                       ; Load the number of tens into A.
  INCA                      ; Increment it.
  ; Now check to see if there are ten tens and we need to carry to the hundreds.
  CCF                       ; Clear the Carry Flag.
  SUB                       ; Subtract 10 from A.
  BRQ incrementHundreds     ; If Q is 0, set the tens to 0 and increment the hundreds place.
  STA                       ; Otherwise, store the value back to the tens place.
  BRI printDecimalLoopStart ; and loop again.
 incrementHundreds:
  STQ                       ; Store 0 in the tens place.
  INCD                      ; Increment the Data Pointer to the hundreds place.
  LDA                       ; Load it into A.
  INCA                      ; Increment it.
  STA                       ; Store it back again.
  BRI printDecimalLoopStart ; and Loop again.
 getOnes:
  SETD DecimalValue         ; Set the Data Pointer to the ones place.
  STA                       ; Store A in it.
  ; At this point we're done. We just need to print the digits with the printDecimalDigit subroutine.
  INCD INCD                 ; Increment the Data Pointer twice to the hundreds place.
 decimalCheckLoop:
  LDA                       ; Load the value into A.
  BRA checkTens             ; If the hundreds are 0, skip printing their digit.
  CALL printDecimalDigit    ; Otherwise, print it.
  DECD
  LDA
  CALL printDecimalDigit    ; And the tens place, too.
  BRI printOnes             ; And finally, the ones.
 checkTens:
  DECD                      ; Decrement to the tens place.
  LDA                       ; Load it into A.
  BRA printOnes             ; If the tens are zero, skip printing their digit, too.
  CALL printDecimalDigit    ; Otherwise, print it.
 printOnes:
  DECD                      ; Decrement to the ones place.
  LDA
  CALL printDecimalDigit    ; Print it no matter what.
  RET                       ; We're done, return to the caller.

; Expects A to contain the byte you want to print as a hexadecimal value.
printByteHex:
  INIB 0x00                 ; Set B to 0.
  SHR SHR SHR SHR           ; Shift Right four times to move the high nybble into the lower half of A.
  CALL printHexDigit        ; Print the nybble.
  INIA 0x00                 ; Set A to 0.
  SHL SHL SHL SHL           ; Shift left four times to move the low nybble back into the lower half of A.
  CALL printHexDigit        ; Print the nybble.
  RET                       ; Return to the caller.

; Expects A to contain the nybble you want to print.
printHexDigit:
  INIB 0d10                 ; Set B to 10.
  SUB                       ; Subtract it.
  BRC printDecimalDigit     ; If the Carry Flag is set, the digit is less than 9. Print it.
  ; Since it's greater than 9, add the ASCII offset for capital letters.
  INIB 0x37                 ; Set B to the offset.
  ADD                       ; Add it to A.
  OUTQ 0x00                 ; Print the result.
  RET                       ; Return to the caller.

; Expects A to contain a single BCD digit to print.
printDecimalDigit:
  INIB 0x30                 ; Load ASCII offset for numbers into B.
  CCF                       ; Clear the Carry Flag.
  ADD                       ; Add it to A.
  OUTQ 0x00                 ; Send it to the output.
  RET                       ; Return from subroutine.

#Data

; This is where printDecimal stores its result.
DecimalValue:
  0x00        ; The ones place.
  0x00        ; The tens place.
  0x00        ; The hundreds place.
