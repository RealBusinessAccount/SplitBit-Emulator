; Sixteen bit arithmetic, for an assembler that counts in addresses.
;
; sbfs.asm has routines like these and the assembler cannot use them: it does not include
; the filesystem, because it reaches the disk through the system's services instead. That
; is the no-linker tax, paid in about a hundred and fifty bytes, and it is cheaper than the
; two and a half kilobytes including sbfs.asm would cost.
;
; Everything here works on numbers in memory rather than in registers, because a CALL puts
; A, B and Data Pointers 0 to 2 back as it found them. Only memory survives a return.
;
; Numbers are stored most significant byte first, the way every number on this machine is.
;
; Written by Anachronaut

#Program

; The two byte number at DP0 becomes the one at DP2. Destination first, so a call reads
; the way an assignment does.
numSet:
  LDA.2
  STA.0
  INCD.2
  INCD.0
  LDA.2
  STA.0
  RET

; The two byte number at DP0 becomes itself plus the one at DP2.
numAdd:
  DPUP.0 0d01
  DPUP.2 0d01
  LDA.0
  LDB.2
  CCF
  ADD
  MVQA
  STA.0
  DPDN.0 0d01
  DPDN.2 0d01
  LDA.0
  LDB.2
  ADD                       ; Carries in from the low half. Nothing between touches it.
  MVQA
  STA.0
  RET

; Adds the byte in A to the two byte number at DP0.
numAddByte:
  DPUP.0 0d01
  LDB.0
  CCF
  ADD
  MVQA
  STA.0
  BNC numAddByteDone
  DPDN.0 0d01
  LDA.0
  INCA
  STA.0
numAddByteDone:
  RET

; Adds one to the two byte number at DP0.
numStep:
  DPUP.0 0d01
  LDA.0
  INCA
  STA.0
  BNC numStepDone           ; It did not wrap, so the high byte is untouched.
  DPDN.0 0d01
  LDA.0
  INCA
  STA.0
numStepDone:
  RET

; Compares the two byte number at DP0 with the one at DP2. Q is zero if they are equal,
; and the Carry Flag is set if the one at DP0 is the smaller. Both come back, because
; neither Q nor the Status register is put back by a return.
numCompare:
  LDA.0
  LDB.2
  CCF
  SUB                       ; The high bytes settle it unless they are the same.
  BNQ numCompareDone
  INCD.0
  INCD.2
  LDA.0
  LDB.2
  CCF
  SUB
numCompareDone:
  RET

; The two byte number at DP0 becomes zero.
numZero:
  RSTA
  STA.0
  INCD.0
  STA.0
  RET
