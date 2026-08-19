; A software interrupt handing something back.
;
; RETI restores every register from the frame, which is what makes an interrupt safe to
; arrive at an arbitrary moment: the interrupted code cannot tell it happened. A SERVICE is
; not arbitrary - it was asked for - and the same rule means it has no way to answer.
;
; So a service that has something to say writes it INTO ITS OWN FRAME, over the saved
; register, and lets RETI put it back. MVSD is what makes the frame reachable: it copies
; the Stack Pointer into a Data Pointer, and the frame sits just above it.
;
;   +1  Status        +5  DP3 high      +9   DP1 high      +13  resume high
;   +2  Q             +6  DP3 low       +10  DP1 low       +14  resume low
;   +3  A             +7  DP2 high      +11  DP0 high
;   +4  B             +8  DP2 low       +12  DP0 low
;
; WHICH REGISTERS A SERVICE MAY ANSWER IN is a convention rather than a rule, and it is the
; same one CALL already has: Q and DP3. A subroutine cannot hand back A, B or DP0 to DP2
; because RET puts them back; a service could write over any of them, and should not, for
; exactly the reason the first list exists. A caller expects what it kept to still be there.
;
; ONLY THE HANDLER ITSELF CAN DO THIS. The offsets are from where the Stack Pointer is, and
; a CALL moves it by ten. A routine called by a handler that tried this would be writing
; into its own return address.
;
; Correct output is:
;   quiet: 7          a service that says nothing leaves Q as it found it
;   answer: 42        one that does, does not
;   pointer: ABC      and DP3 comes back the same way

#Include console.asm

#Program

start:
  ; Something recognisable in Q, so that a service leaving it alone is visible.
  INIA 0d7
  RSTB
  CCF
  ADD

  SETD.0 QuietText
  CALL printString
  SWI quiet
  MVQA
  CALL printByteDecimal
  CALL newLine

  SETD.0 AnswerText
  CALL printString
  SWI answer
  MVQA
  CALL printByteDecimal
  CALL newLine

  SETD.0 PointerText
  CALL printString
  SWI pointer
  PSHD.3
  POPD.0
  CALL printString
  CALL newLine
  HALT

; Says nothing, so whatever the caller had in Q is still there afterwards.
quiet:
  INIA 0d99
  RSTB
  CCF
  ADD                   ; Q is 99 in here, and nobody outside will ever know.
  RETI

answer:
  INIA 0d42
  MVSD.1
  DPUP.1 0d02           ; The saved Q.
  STA.1
  RETI

pointer:
  SETD.0 Letters
  MVSD.1
  DPUP.1 0d05           ; The saved DP3, high byte first the way everything is stored.
  PSHD.0
  POPA                  ; The low half comes off the Stack first.
  POPB
  STB.1
  INCD.1
  STA.1
  RETI

#Data

QuietText:
"quiet: "
AnswerText:
"answer: "
PointerText:
"pointer: "
Letters:
"ABC"

#Vectors

  Boot     start
  quiet    quiet
  answer   answer
  pointer  pointer
