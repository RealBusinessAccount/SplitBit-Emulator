; This file supplies basic support for int8 values.

#Program

; Basic int8 subroutines.

; An int8 value is an 8 bit unsigned integer. Just a byte literally interpreted as a value.
; Basic operations on int8 values use A and B as operands with the result returned in Q, similar to the bare arithmetic instructions of SplitBit.

int8mult:
  ; Multiply A by B and return the result in Q.
  ; This subroutine is limited to outputs in the range of 0-255.
  ; It does not reliably return with the Carry Flag set if the result is too large to fit in the range.
  ; First, check if either is zero, and if so, return zero.
  BRB return0
  BRA return0
  PSHB ; Push the multiplier to the stack.
  PSHA ; Push the multiplicand to the stack.
  POPB ; Pop the multiplicand into B.
  RSTA ; Set A to 0.
  CCF  ; Clear the Carry Flag, just in case.
 int8multLoop:
  ADD  ; Add the multiplicand to A.
  POPA ; Pop the multiplier into A.
  DECA ; Subtract one from the multiplier.
  BRA int8multDone ; If the multiplier becomes zero, we're done.
  PSHA ; Push the multiplier back to the stack.
  PSHQ ; Push the running total to the stack.
  POPA ; Pop the running total into A.
  BRI int8multLoop
 return0:
  RSTA
  RSTB
  ADD
 int8multDone:
  RET

int8div:
  ; Divide A by B and return the quotient in Q.
  ; First, check if either A or B are 0, if so, return 0.
  BRB return0
  BRA return0
  ; This dance of pushes, pops, and addition creates a quotient counter on the Stack while preserving A and B.
  PSHA ; Push A to the Stack.
  PSHB ; Push B to the Stack.
  RSTA ; Set A and B to 0.
  RSTB
  ADD  ; Add them together, setting Q to 0.
  POPB ; Restore B.
  POPA ; Restore A.
  PSHQ ; Push a 0 onto the Stack.
  ; The Carry Flag is clear and we can proceed with the division.
 int8divLoop:
  SUB  ; Subtract B from A.
  ; If we generate a carry we're done.
  BRC int8divDone
  ; Otherwise, increment the quotient counter and subtract again.
  POPA ; Pop the quotient counter from the stack.
  INCA ; Increment it.
  PSHA ; Push it back onto the stack.
  PSHQ ; Push the running total onto the stack.
  POPA ; Pop the runing total into A.
  BRI int8divLoop ; Branch back to the loop.
 int8divDone:
  CCF  ; Clear the Carry Flag.
  POPA ; Pop the quotient into A.
  RSTB ; Set B to 0.
  ADD  ; Add them together to move the result to Q.
  RET  ; Return to the caller.

int8mod:
  ; Divide A by B and return the remainder in Q.
  ; If A or B are 0, return 0.
  BRB return0
  BRA return0
 int8modLoop:
  SUB ; Subtract B from A.
  BRC int8modDone
  PSHQ
  POPA
  BRI int8modLoop
 int8modDone:
  ; Add the divisor to Q to get the remainder.
  CCF
  PSHQ
  POPA
  ADD
  RET
