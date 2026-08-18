; text.asm
; Picking a line of typing apart.
;
; A shell reads a line and has to decide what was asked for. That is two jobs: cutting the
; first word off the line, and telling whether a word is the one being looked for. There
; is nothing else here, because there is nothing else a command line needs yet.
;
; Written by Anachronaut

#Program

; DP0 names a line ending in a zero byte. Cuts the first word off it, in place, by writing
; a zero byte over the space that ends the word. DP0 is unchanged, because a RET puts it
; back, so afterwards DP0 names just the first word.
;
; Where the rest of the line begins goes in TextRest, with any spaces between skipped. A
; line with only one word on it leaves TextRest naming that line's zero byte, which reads
; as an empty argument rather than as a missing one, and is the same thing here.
textSplit:
  LDA.0
  BRA textSplitHere     ; The line ended, so the whole of it was one word.
  INIB 0x20
  CCF
  SUB
  BRQ textSplitCut
  INCD.0
  BRI textSplit

textSplitCut:
  RSTA
  STA.0                 ; The space becomes the end of the word.
  INCD.0

textSplitSkip:
  LDA.0
  BRA textSplitHere
  INIB 0x20
  CCF
  SUB
  BNQ textSplitHere     ; Something that is not a space: the rest starts here.
  INCD.0
  BRI textSplitSkip

textSplitHere:
  SETD.1 TextRest
  STD.0.1
  RET

; DP0 and DP1 name strings ending in zero bytes. Q is zero if they are the same.
;
; The two ending together is what makes them the same. Comparing until one of them ends
; would call "dir" and "dirty" the same word, which is the kind of thing a shell gets
; wrong once and confusingly.
textSame:
  LDA.0
  LDB.1
  CCF
  SUB
  BNQ textDiffer
  LDA.0
  BRA textAlike         ; Equal, and both of them zero: they ended together.
  INCD.0
  INCD.1
  BRI textSame

textAlike:
  RSTA
  RSTB
  CCF
  ADD                   ; Q is zero: the same.
  RET

textDiffer:
  RSTA
  INIB 0d1
  CCF
  ADD                   ; Q is one: not the same.
  RET

; DP0 names text. Reads hexadecimal digits off the front of it into TextValue, most
; significant byte first. Q is zero if there was at least one digit to read.
;
; Digits past the fourth push the earlier ones off the top rather than being refused,
; which is what typing over an address does on every monitor there has ever been.
textHexWord:
  RSTA
  SETD.1 TextValue
  STA.1
  INCD.1
  STA.1
  SETD.1 TextDigits
  STA.1

textHexLoop:
  LDA.0
  CALL textHexDigit
  PSHQ
  POPA
  INIB 0xFF
  CCF
  SUB
  BRQ textHexEnd        ; Not a digit, so the number stopped before it.

  CALL textHexShift
  SETD.1 TextDigits
  LDA.1
  INCA
  STA.1
  INCD.0
  BRI textHexLoop

textHexEnd:
  SETD.1 TextDigits
  LDA.1
  BRA textHexNothing
  RSTA
  RSTB
  CCF
  ADD                   ; Q is zero: there was a number.
  RET
textHexNothing:
  RSTA
  INIB 0d1
  CCF
  ADD                   ; Q is one: there was not.
  RET

; A holds the digit just read. Moves TextValue up by one place and puts the digit in the
; hole that leaves.
;
; A and B are a circular shift register sixteen bits long, so rotating them left four
; times multiplies the pair by sixteen. What fell off the top of the high byte comes round
; into the bottom of the low one, which is exactly the nybble the new digit wants, so it
; is masked away first.
textHexShift:
  SETD.1 TextDigit
  STA.1

  SETD.0 TextValue
  LDA.0
  INCD.0
  LDB.0
  SHL SHL SHL SHL

  SETD.0 TextValue
  STA.0                 ; The high byte is finished.

  PSHB
  POPA
  INIB 0xF0
  AND
  MVQA
  SETD.1 TextDigit
  LDB.1
  OR
  SETD.0 TextValue
  INCD.0
  STQ.0
  RET

; A holds a character. Q is what it is worth as a hexadecimal digit, or 0xFF if it is not
; one. Upper and lower case both count, because nobody wants to be told which they meant.
;
; Everything below works from the distance above '0', which is why the letters are tested
; at seventeen and thirty two rather than at anything recognisable.
textHexDigit:
  INIB 0x30
  CCF
  SUB
  BRC textHexNo         ; Below '0'.
  MVQA
  INIB 0d10
  CCF
  SUB
  BNC textHexUpper      ; Ten or more above '0', so not 0 to 9.
  RSTB
  CCF
  ADD                   ; Q is the digit itself.
  RET

textHexUpper:
  INIB 0d17
  CCF
  SUB
  BRC textHexNo         ; Between '9' and 'A'.
  MVQA
  INIB 0d6
  CCF
  SUB
  BNC textHexLower      ; Past 'F'.
  INIB 0d10
  CCF
  ADD
  RET

textHexLower:
  INIB 0d32
  CCF
  SUB
  BRC textHexNo         ; Between 'F' and 'a'.
  MVQA
  INIB 0d6
  CCF
  SUB
  BNC textHexNo         ; Past 'f'.
  INIB 0d10
  CCF
  ADD
  RET

textHexNo:
  RSTA
  INIB 0xFF
  CCF
  ADD
  RET

; ---- A number written in decimal ----
;
; DP0 names it. Q is the value, and TextDigits says how many digits were read, which is
; zero when there was no number there at all. Stops at the first thing that is not a digit.
;
; Decimal rather than hex, and one byte rather than two, because this is for the numbers a
; person types at a program: a line number, a count, a how many. Nobody counts lines in
; hex, and nobody types a line number above 255 on a machine this size. textHexWord is
; still the one for an address, where hex is what everybody means.
;
; Ten times the running total is worked out as eight of it plus two of it, because nothing
; on this machine multiplies. Anything past 255 wraps, which is what the same sum does
; everywhere else here.
textNumber:
  RSTA
  SETD.1 TextValue
  STA.1
  SETD.1 TextDigits
  STA.1

textNumberLoop:
  LDA.0
  BRA textNumberDone

  ; Below '0' or above '9' ends it.
  INIB 0d48
  CCF
  SUB
  BRC textNumberDone            ; It borrowed, so the character was below '0'.
  MVQA
  INIB 0d10
  CCF
  SUB
  BNC textNumberDone            ; It did not borrow, so it was ten or more past '0'.

  PSHA                          ; The digit, while the total is multiplied.
  SETD.1 TextValue
  LDA.1
  LDB.1
  CCF
  ADD                           ; Twice.
  MVQA
  MVQB
  PSHA                          ; Twice, kept: ten is eight and two.
  CCF
  ADD                           ; Four times.
  MVQA
  MVQB
  CCF
  ADD                           ; Eight times.
  MVQA
  POPB
  CCF
  ADD                           ; Ten times.
  MVQA
  POPB
  CCF
  ADD                           ; And the digit.
  SETD.1 TextValue
  STQ.1

  SETD.1 TextDigits
  LDA.1
  INCA
  STA.1
  INCD.0
  BRI textNumberLoop

textNumberDone:
  SETD.1 TextValue
  LDA.1
  RSTB
  CCF
  ADD                           ; Q is the value, the way a routine hands a byte back.
  RET

#Data

; Where the rest of the line begins, after textSplit has taken a word off the front.
TextRest:
  0x00 0x00

; What textHexWord read, and what it needs while reading it.
TextValue:
  0x00 0x00
TextDigits:
  0x00
TextDigit:
  0x00
