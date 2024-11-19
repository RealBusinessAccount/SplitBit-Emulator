; A library of math subroutines for SplitBit.

#Program

int16add:
    ; Add two two-byte unsigned integers.
    ; Operands are stored in a four-byte array in the following order:
    ; Operand A, high byte
    ; Operand A, low byte
    ; Operand B, high byte
    ; Operand B, low byte
    ; The result is stored by overwriting Operand A.
    ; This subroutine expects the Data Pointer to be set to the start of the array.
    ; After execution, this routine leaves the data pointer set to the high byte of the result.
    ; If the addtion results in a carry, the carry flag will be set.
  CCF             ; Clear the Carry Flag, just in case.
  DPUP 0d03       ; Move to Operand B's low byte.
  LDB             ; Load it to B.
  DPDN 0d02       ; Move to Operand A's low byte.
  LDA             ; Load it to A.
  ADD             ; Add them together.
  STQ             ; Store the result.
  INCD            ; Go to Operand B's high byte.
  LDB             ; Load it to B.
  DPDN 0d02       ; Go to Operand A's high byte.
  LDA             ; Load it to A.
  ADD             ; Add them together.
  STQ             ; Store the result.
  RET             ; Return to the caller.

int16sub:
    ; Subtract two two-byte unsigned integers.
    ; Operands are stored in a four-byte array in the following order:
    ; Operand A, high byte
    ; Operand A, low byte
    ; Operand B, high byte
    ; Operand B, low byte
    ; Operand B is subtracted from Operand A and the result is stored by overwriting Operand A.
    ; This subroutine expects the Data Pointer to be set to the start of the array.
    ; After execution, this routine leaves the data pointer set to the high byte of the result.
    ; If the addtion results in a carry, the carry flag will be set.
  CCF             ; Clear the Carry Flag, just in case.
  DPUP 0d03       ; Move to Operand B's low byte.
  LDB             ; Load it to B.
  DPDN 0d02       ; Move to Operand A's low byte.
  LDA             ; Load it to A.
  SUB             ; Subtract B from A.
  STQ             ; Store the result.
  INCD            ; Go to Operand B's high byte.
  LDB             ; Load it to B.
  DPDN 0d02       ; Go to Operand A's high byte.
  LDA             ; Load it to A.
  SUB             ; Subtract B from A.
  STQ             ; Store the result.
  RET             ; Return to the caller.

#Data

Int16operands:
  0x00 ; Operand A high byte.
  0x00 ; Operand A low byte.
  0x00 ; Operand B high byte.
  0x00 ; Operand B low byte.
