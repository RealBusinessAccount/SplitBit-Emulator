; A program whose data contains the names of directives.
;
; The quotes are gone by the time the assembler looks at a token, so "#Program" written as
; a string looked exactly like the directive. It was read as one: the segment silently
; changed in the middle of the Data Segment, the string's nine bytes were charged to the
; Program cursor instead, and every label defined after it came out nine bytes wrong. The
; file still had a valid header and a plausible length, so nothing said a word - the only
; symptom was a program that jumped into the middle of an instruction.
;
; This is the fourth of that family. A string spelling a mnemonic assembled as that
; instruction, a string beginning with a zero was rejected as a malformed literal, a string
; in the Program Segment was discarded in silence, and now this.
;
; It came up because an assembler written FOR this machine has to compare tokens against
; the directive names, so it necessarily has them in its data. Nothing else ever did.
;
; What it checks: that the strings survive as strings, and that a label defined after them
; still points where it should. Everything after Directives would shift if the bug came
; back, so printing Message is the test.
;
; Written by Anachronaut

#Program

start:
  SETD.0 Directives
  CALL show
  SETD.0 Message
  CALL show
  HALT

show:
  LDA.0
  BRA showDone
  OUTA 0x00
  INCD.0
  BRI show
showDone:
  RET

#Data

Directives:
"#Program #Data #Include #Vectors #Base #Align #Reserve
"
Message:
"and a label after them still points at itself
"
