#Program
; int16 subroutines.

; An int16 value is a 16 bit unsigned integer, represented by two bytes, in the order most-significant, least-significant.

; The basic operations take two sequential int16 values as operands from the Data Memory.
; They assume that the Data Pointer is set to the high byte of operand A.
; Operands are stored in a four-byte array in the following order:
  ; Operand A, high byte
  ; Operand A, low byte
  ; Operand B, high byte
  ; Operand B, low byte
; All operations overwrite Operand A. This causes the Data Pointer to point to the result immediately after returning.

int16add:
  ; Add two int16 values.
  ; If the addtion results in a carry, the carry flag will be set.
  CCF       ; Clear the Carry Flag, just in case.
  DPUP 0d03 ; Move to Operand B's low byte.
  LDB       ; Load it to B.
  DPDN 0d02 ; Move to Operand A's low byte.
  LDA       ; Load it to A.
  ADD       ; Add them together.
  STQ       ; Store the result.
  INCD      ; Go to Operand B's high byte.
  LDB       ; Load it to B.
  DPDN 0d02 ; Go to Operand A's high byte.
  LDA       ; Load it to A.
  ADD       ; Add them together.
  STQ       ; Store the result.
  RET       ; Return to the caller.

int16sub:
  ; Subtract one int16 value from another.
  ; If the addtion results in a carry, the carry flag will be set.
  CCF       ; Clear the Carry Flag, just in case.
  DPUP 0d03 ; Move to Operand B's low byte.
  LDB       ; Load it to B.
  DPDN 0d02 ; Move to Operand A's low byte.
  LDA       ; Load it to A.
  SUB       ; Subtract B from A.
  STQ       ; Store the result.
  INCD      ; Go to Operand B's high byte.
  LDB       ; Load it to B.
  DPDN 0d02 ; Go to Operand A's high byte.
  LDA       ; Load it to A.
  SUB       ; Subtract B from A.
  STQ       ; Store the result.
  RET       ; Return to the caller.

int16div:
  ; Divide Operand A by Operand B, store the quotient in Operand B, store the remainder in Operand A.
  ; First, check and see if Operand B is zero, and abort if so.
  DPUP 0x02 ; Move to Operand B.
  LDA       ; Load the high byte.
  INCD
  LDB       ; Load the low byte.
  DPDN 0x03 ; Return the Data Pointer to the start.
  OR        ; Do a bitwise OR.
  ; If Q is zero, then our dividend was zero, and we can't have that.
  BRQ int16divByZero
  ; Otherwise, proceed.
  RSTA      ; Set A to 0.
  RSTB      ; Set B to 0.
 int16divLoop:
  ; Now, subtract the Operand B from Operand A.
  CALL int16sub
  ; If that subtraction resulted in a carry, we're done.
  BRC int16divEnd
  ; Otherwise, we need to increment the quotient counter.
  INCB      ; If this overflows B, we need to increment A.
  BRC int16divCarry
  BRI int16divLoop
 int16divCarry:
  INCA
  BRI int16divLoop
 int16divEnd:
  ; Add Operand B to Operand A to obtain the remainder.
  CALL int16add
  ; Overwrite Operand B with the quotient.
  DPUP 0x02
  STA
  INCD
  STB
  RET       ; Return to the caller.
 int16divByZero:
  ; You're not supposed to go here! Set Operand A to zero and return.
  STA       ; A is necessarily already zero in order to be here, so just store it.
  INCD
  STA
  RET       ; Return to the caller.

int16mult:
  ; Multiplies two int16 values.
  CCF   ; Clear the carry flag.
  DPUP 0d03     ; Move to the low byte of Operand B.
  LDB
