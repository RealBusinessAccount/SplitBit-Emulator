; print.asm

; Some simple SplitBit subroutines for printing.
; Anachronaut
; 10/27/2024

#Program
  BRI Start             ; Branch immediately to the start of the program.

printString:
  CALL saveRegisters    ; Store the registers so we can  restore them later.
  printLoop:
    LDA                   ; Move the first character of the string into A.
    BRA Return            ; If A is NULL, the string is finished, so return.
    OUTA 0x00             ; Output the character.
    INCD                  ; Increment Data Pointer to the next character.
    BRI printLoop         ; Branch to the beginning of the loop.

lineFeed:
  CALL saveRegisters    ; Save the registers so they can be restored.
  INIA 0x0A             ; Load the character for linefeed into A.
  OUTA 0x00             ; Output it.
  CALL restoreRegisters
  BRI Return            ; We're done.

saveRegisters:          ; Subroutine for storing the registers.
  PSHD                  ; Store the Data Pointer, push it to the stack.
  SETD Registers        ; Set the Data Pointer to the address for the registers.
  STQ                   ; Store Q.
  INCD                  ; Move to the next address.
  STA                   ; Store A.
  INCD                  ; Move to the next address.
  STB                   ; Store B.
  POPD                  ; Restore the Data Pointer.
  RET                   ; Return to the caller.

restoreRegisters:
  PSHD                  ; Save the Data Pointer.
  SETD Registers        ; Set the Data Pointer to the registers address.
  RSTB                  ; Set B to 0.
  LDA                   ; Load the value for Q into A.
  ADD                   ; Add 0 to move the value to Q.
  INCD                  ; Move to the next register value.
  LDA                   ; Load A with its value.
  INCD                  ; Move to the next register value.
  LDB                   ; Load B with its value.
  POPD                  ; Restore the Data Pointer.
  RET                   ; Return to the caller.

Return:
  CALL restoreRegisters ; Restore the registers.
  RET                   ; Return to the caller.

#Data

Registers:    ; This is where saveRegisters stores the registers temporarily.
  0x00        ; Q Register
  0x00        ; A Register
  0x00        ; B Register
