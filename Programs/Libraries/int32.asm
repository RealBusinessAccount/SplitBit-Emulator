#Program
; These routines untested and written entirely by Claude Code!
; int32 subroutines.

; An int32 value is a 32-bit unsigned integer, represented by four bytes,
; in the order most-significant to least-significant.

; The basic operations take two sequential int32 values as operands from Data Memory.
; They assume that the Data Pointer is set to the high byte of Operand A.
; Operands are stored in an eight-byte array in the following order:
;   Operand A, byte 3 (most significant)
;   Operand A, byte 2
;   Operand A, byte 1
;   Operand A, byte 0 (least significant)
;   Operand B, byte 3 (most significant)
;   Operand B, byte 2
;   Operand B, byte 1
;   Operand B, byte 0 (least significant)
; All operations overwrite Operand A. This causes the Data Pointer to point to the result after returning.

int32add:
  ; Add two int32 values.
  ; If the addition results in a carry, the carry flag will be set.
  CCF           ; Clear the Carry Flag.
  DPUP 0d07     ; Move to Operand B's byte 0 (least significant).
  LDB           ; Load it to B.
  DPDN 0d04     ; Move to Operand A's byte 0.
  LDA           ; Load it to A.
  ADD           ; Add them together.
  STQ           ; Store the result.
  DPUP 0d03     ; Move to Operand B's byte 1.
  LDB           ; Load it to B.
  DPDN 0d04     ; Move to Operand A's byte 1.
  LDA           ; Load it to A.
  ADD           ; Add with carry from byte 0.
  STQ           ; Store the result.
  DPUP 0d03     ; Move to Operand B's byte 2.
  LDB           ; Load it to B.
  DPDN 0d04     ; Move to Operand A's byte 2.
  LDA           ; Load it to A.
  ADD           ; Add with carry from byte 1.
  STQ           ; Store the result.
  DPUP 0d03     ; Move to Operand B's byte 3 (most significant).
  LDB           ; Load it to B.
  DPDN 0d04     ; Move to Operand A's byte 3.
  LDA           ; Load it to A.
  ADD           ; Add with carry from byte 2.
  STQ           ; Store the result.
  RET           ; Return to the caller.

int32sub:
  ; Subtract Operand B from Operand A.
  ; If the subtraction results in a borrow, the carry flag will be set.
  CCF           ; Clear the Carry Flag.
  DPUP 0d07     ; Move to Operand B's byte 0 (least significant).
  LDB           ; Load it to B.
  DPDN 0d04     ; Move to Operand A's byte 0.
  LDA           ; Load it to A.
  SUB           ; Subtract B from A.
  STQ           ; Store the result.
  DPUP 0d03     ; Move to Operand B's byte 1.
  LDB           ; Load it to B.
  DPDN 0d04     ; Move to Operand A's byte 1.
  LDA           ; Load it to A.
  SUB           ; Subtract with borrow from byte 0.
  STQ           ; Store the result.
  DPUP 0d03     ; Move to Operand B's byte 2.
  LDB           ; Load it to B.
  DPDN 0d04     ; Move to Operand A's byte 2.
  LDA           ; Load it to A.
  SUB           ; Subtract with borrow from byte 1.
  STQ           ; Store the result.
  DPUP 0d03     ; Move to Operand B's byte 3 (most significant).
  LDB           ; Load it to B.
  DPDN 0d04     ; Move to Operand A's byte 3.
  LDA           ; Load it to A.
  SUB           ; Subtract with borrow from byte 2.
  STQ           ; Store the result.
  RET           ; Return to the caller.
