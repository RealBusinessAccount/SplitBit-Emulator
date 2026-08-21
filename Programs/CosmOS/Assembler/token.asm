; Tokens out of characters.
;
; A token is a run of characters with whitespace or a comment on either side, or anything
; between a pair of quotes. That is the whole of the lexical grammar: SplitBit assembly has
; no operators, no punctuation and no line continuation, so there is nothing here that has
; to look ahead more than one character.
;
; ONE CHARACTER OF LOOKAHEAD, and it is held here rather than in the reader. A word ends
; when something that is not part of it turns up, and that something has already been read
; by the time anyone knows - so it is put in TokPending and taken again next time. Keeping
; it at this level rather than pushing it back into the reader means the line number needs
; no arithmetic: srcNext counted the newline when it handed it out, and it stays counted.
;
; Zero means "nothing held", which is safe because a source file is text and a text file
; has no zero bytes in it. A file that did would be rejected as unassemblable long before
; the difference showed.
;
; Written by Anachronaut

#Program

; The next token, into TokText with a zero after it. Q is zero if there was one.
;
; TokLength is how long it is, TokString says whether it arrived in quotes, and TokLine is
; the line it STARTED on - captured before the token is read, because a token ending in a
; newline has already moved the reader on to the next line by the time it is finished.
tokNext:
  SETD.0 TokHeld
  LDA.0
  BRA tokFresh
  RSTA
  STA.0
  RSTA
  RSTB
  CCF
  ADD                       ; The one that was handed back, exactly as it was.
  RET

tokFresh:
  RSTA
  SETD.0 TokString
  STA.0

tokSkip:
  CALL tokGet
  BNQ tokEnded
  CALL tokIsSpace
  BRQ tokSkip

  SETD.0 TokChar
  LDA.0
  INIB 0x3B                 ; A semicolon starts a comment.
  XOR
  BNQ tokBegin

tokComment:
  CALL tokGet
  BNQ tokEnded
  SETD.0 TokChar
  LDA.0
  INIB 0x0A
  XOR
  BNQ tokComment            ; Everything up to the newline belongs to the comment.
  BRI tokSkip

tokBegin:
  ; Where it starts, for anything that has to complain about it later.
  SETD.0 TokLine
  SETD.2 SrcLine
  CALL numSet

  RSTA
  SETD.0 TokLength
  STA.0
  SETD.0 TokText
  SETD.1 TokPointer
  STD.0.1

  SETD.0 TokChar
  LDA.0
  INIB 0x22                 ; A quote starts a string.
  XOR
  BNQ tokWord

  INIA 0d1
  SETD.0 TokString
  STA.0

tokStringLoop:
  CALL tokGet
  BNQ tokDone               ; The file ended inside a string. Take what there is; the
                            ; classifier will have something to complain about.
  SETD.0 TokChar
  LDA.0
  INIB 0x22
  XOR
  BRQ tokDone
  CALL tokAppend
  BRI tokStringLoop

tokWord:
  CALL tokAppend
tokWordLoop:
  CALL tokGet
  BNQ tokDone
  CALL tokIsSpace
  BRQ tokHoldDone
  SETD.0 TokChar
  LDA.0
  INIB 0x3B
  XOR
  BRQ tokHoldDone           ; A comment butting straight up against a word ends it.
  CALL tokAppend
  BRI tokWordLoop

tokHoldDone:
  ; Whatever ended the word was not part of it, so it goes back to be looked at again.
  SETD.0 TokChar
  LDA.0
  SETD.0 TokPending
  STA.0

tokDone:
  SETD.1 TokPointer
  LDD.0.1
  RSTA
  STA.0                     ; The zero that makes it a string.
  RSTA
  RSTB
  CCF
  ADD                       ; Q is zero: there was a token.
  RET

tokEnded:
  RSTA
  SETD.0 TokLength
  STA.0
  SETD.0 TokText
  STA.0
  RSTA
  INIB 0d1
  CCF
  ADD                       ; Q is not zero: the source is finished.
  RET

; Puts the held character back into the file it came from, leaving nothing in hand.
;
; This is what #Include calls before the reader puts the current file aside. The character
; the tokenizer is holding was read from that file and has not been used, so it goes back
; into it; there is then nothing to carry across the include and nothing to hand back at a
; moment that might land in the middle of a word.
tokUnread:
  SETD.0 TokPending
  LDA.0
  BRA tokUnreadDone
  CALL srcStepBack
  RSTA
  SETD.0 TokPending
  STA.0
tokUnreadDone:
  RET

; Hands the token just read back, so that the next tokNext produces it again.
;
; ONE TOKEN, and only where nothing has changed it since. The Vector Segment needs it: a
; name there may be followed by a number, by a handler, or by the next line's name, and
; which it is cannot be known without looking. Do NOT use it after anything that alters
; TokText - a label definition with its colon written over would come back as a use of the
; name rather than as a definition of it.
tokBack:
  INIA 0d1
  SETD.0 TokHeld
  STA.0
  RET

; The next character, into TokChar. Q is zero if there was one. Takes the held one first.
tokGet:
  SETD.0 TokPending
  LDA.0
  BRA tokGetFresh
  SETD.0 TokChar
  STA.0
  RSTA
  SETD.0 TokPending
  STA.0
  RSTA
  RSTB
  CCF
  ADD
  RET

tokGetFresh:
  CALL srcNext
  BNQ tokGetNone
  SETD.0 SrcChar
  LDA.0
  SETD.0 TokChar
  STA.0
  RSTA
  RSTB
  CCF
  ADD
  RET

tokGetNone:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Adds TokChar to the token being built, unless it is already as long as one may be.
;
; A token that runs over is truncated rather than refused, and the classifier refuses it
; afterwards: nothing 255 characters long is a valid mnemonic, literal or label, so the
; error that comes out names what was wrong with it rather than only how long it was.
tokAppend:
  SETD.0 TokLength
  LDA.0
  INIB 0xFF
  XOR
  BRQ tokAppendFull
  SETD.1 TokPointer
  LDD.0.1
  SETD.2 TokChar
  LDA.2
  STA.0
  INCD.0
  STD.0.1
  SETD.0 TokLength
  LDA.0
  INCA
  STA.0
tokAppendFull:
  RET

; Q is zero if TokChar is whitespace: a space, or anything in the run from tab to carriage
; return, which is what the C library calls a space and what the other assembler uses.
tokIsSpace:
  SETD.0 TokChar
  LDA.0
  INIB 0x20
  XOR
  BRQ tokSpaceYes

  SETD.0 TokChar
  LDA.0
  INIB 0x09
  CCF
  SUB
  BRC tokSpaceNo            ; Below a tab.
  SETD.0 TokChar
  LDA.0
  INIB 0x0E
  CCF
  SUB
  BNC tokSpaceNo            ; Past a carriage return.

tokSpaceYes:
  RSTA
  RSTB
  CCF
  ADD
  RET

tokSpaceNo:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

#Data

TokLine:
  0x00 0x00
TokPointer:
  0x00 0x00
TokLength:
  0x00
TokString:
  0x00
TokChar:
  0x00
TokPending:
  0x00
TokHeld:
  0x00

; As long as a token may be, and one more for the zero. The other assembler stops at the
; same 255, and the limit is worth matching rather than choosing again.
TokText:
  #Reserve 0d256
