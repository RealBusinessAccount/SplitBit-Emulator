; A program that keeps a file without knowing how a filesystem works.
;
; INCLUDES NOTHING BUT THE SERVICE NAMES. No sbfs.asm, no console.asm - the system has both
; of those running already, and this asks it rather than carrying a second copy. That is the
; whole point of the program: if it works, a tool that edits documents does not need two and
; a half kilobytes of filesystem bound into it.
;
; It writes a file, reads it back, says how big it was, renames it, and takes it away again,
; which is every file service there is.
;
; ---- What you will see before the handlers are written ----
;
; The numbers are pinned but nothing answers to them yet, so the first call dispatches
; through an empty vector and the machine stops:
;
;   Fault: Software vector 21, dispatched from Program Address 0x200B, has no handler
;   installed.
;
; That is the fault working properly rather than the program being broken. A vector with
; nothing in it is not a jump to address zero; it is a stop, with the vector named and the
; place it was called from named, which is as much as the machine can know.

#Include services.asm

#Program

  #Base 0x2000

start:
  ; ---- Write it ----
  ;
  ; A and B together are how many bytes there are, most significant first, which is the
  ; same sixteen bits a length always is on this machine.
  SETD.0 Name
  SETD.1 Body
  RSTA
  INIB 0d22                 ; The text and its newline. NOT the zero the assembler put
  SWI osFileSave            ; after it: a text file ends where the text ends.
  BNQ noSave
  SETD.0 SavedText
  SWI osPrintString

  ; ---- Read it back ----
  ;
  ; DP3 comes back holding how many bytes there were, because that is one of the two things
  ; a service is allowed to answer in and a file that fits in memory has a length that fits
  ; in a pointer.
  SETD.0 Name
  SETD.1 Landing
  SWI osFileRead
  BNQ noRead
  SETD.0 ReadText
  SWI osPrintString

  PSHD.3
  POPB                      ; The low byte is on top, the way a pointer is pushed.
  POPA
  SWI osPrintNumber
  SETD.0 BytesText
  SWI osPrintString

  ; And now the length is needed for something rather than just reported. What came back is
  ; a file, not a string: nothing on the disk ends in a zero byte, because the entry says
  ; where it stops instead. So a zero goes on the end before it can be printed as one.
  SETD.1 Landing
  PSHD.3
  POPB
  POPA
walkToEnd:
  BRB atEnd
  INCD.1
  DECB
  BRI walkToEnd
atEnd:
  RSTA
  STA.1

  SETD.0 Landing
  SWI osPrintString

  ; ---- Call it something else ----
  SETD.0 Name
  SETD.1 OtherName
  SWI osFileRename
  BNQ noRename
  SETD.0 RenamedText
  SWI osPrintString

  ; ---- And take it away ----
  SETD.0 OtherName
  SWI osFileDelete
  BNQ noDelete
  SETD.0 DeletedText
  SWI osPrintString

  ; Reading it now should fail, and a service saying no is not the same as one that is not
  ; there: this comes back with an answer rather than stopping the machine.
  SETD.0 OtherName
  SETD.1 Landing
  SWI osFileRead
  BRQ stillThere
  SETD.0 GoneText
  SWI osPrintString
  SWI osExit

stillThere:
  SETD.0 StillText
  SWI osPrintString
  SWI osExit

noSave:
  SETD.0 NoSaveText
  SWI osPrintString
  SWI osExit
noRead:
  SETD.0 NoReadText
  SWI osPrintString
  SWI osExit
noRename:
  SETD.0 NoRenameText
  SWI osPrintString
  SWI osExit
noDelete:
  SETD.0 NoDeleteText
  SWI osPrintString
  SWI osExit

#Data

  #Base 0x1000

Name:
"kept.txt"
OtherName:
"moved.txt"

Body:
"a file kept by asking
"

SavedText:
"saved it
"
ReadText:
"read it back, "
BytesText:
" bytes:
"
RenamedText:
"renamed it
"
DeletedText:
"deleted it
"
GoneText:
"and it is gone
"
StillText:
"but it is still there
"

NoSaveText:
"it would not save
"
NoReadText:
"it would not read
"
NoRenameText:
"it would not rename
"
NoDeleteText:
"it would not delete
"

Landing:
  #Reserve 0d256
