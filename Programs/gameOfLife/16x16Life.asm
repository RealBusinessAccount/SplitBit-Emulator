; Conway's Game of Life for SplitBit.
;
; The visible field is 16x16, surrounded by a permanently dead one-cell border.
; Each of the 18x18 allocated cells is stored as two adjacent bytes:
;   current state, next state
; This makes double buffering possible with SplitBit's single Data Pointer.
;
; The initial pattern is a glider. ANSI terminal control codes redraw the field
; in place. Press Ctrl-C to stop the emulator.

#Include Libraries/print.asm

#Program

start:
  CALL seedGlider
  SETD ClearScreen
  CALL printString

generationLoop:
  CALL renderBoard
  CALL evolveBoard
  CALL commitBoard
  CALL frameDelay
  BRI generationLoop

seedGlider:
  ; Coordinates in the padded field:
  ;   .#.
  ;   ..#
  ;   ###
  SETD Board
  DPUP 0d42
  INIA 0x01
  STA
  SETD Board
  DPUP 0d80
  STA
  SETD Board
  DPUP 0d112
  STA
  SETD Board
  DPUP 0d114
  STA
  SETD Board
  DPUP 0d116
  STA
  RET

renderBoard:
  SETD CursorHome
  CALL printString
  SETD Board
  DPUP 0d38
  INIA 0d16
  SETD RowCount
  STA
  SETD Board
  DPUP 0d38

renderRow:
  PSHD
  INIA 0d16
  SETD ColCount
  STA
  POPD

renderCell:
  LDA
  BRA renderDead
  INIB 0x23
  OUTB 0x00
  BRI renderCellDone
renderDead:
  INIB 0x20
  OUTB 0x00
renderCellDone:
  DPUP 0d02
  PSHD
  SETD ColCount
  LDA
  DECA
  STA
  BRA renderRowDone
  POPD
  BRI renderCell

renderRowDone:
  POPD
  CALL lineFeed
  DPUP 0d04
  PSHD
  SETD RowCount
  LDA
  DECA
  STA
  BRA renderDone
  POPD
  BRI renderRow

renderDone:
  POPD
  RET

evolveBoard:
  SETD Board
  DPUP 0d38
  INIA 0d16
  SETD RowCount
  STA
  SETD Board
  DPUP 0d38

evolveRow:
  PSHD
  INIA 0d16
  SETD ColCount
  STA
  POPD

evolveCellLoop:
  CALL evolveCell
  DPUP 0d02
  PSHD
  SETD ColCount
  LDA
  DECA
  STA
  BRA evolveRowDone
  POPD
  BRI evolveCellLoop

evolveRowDone:
  POPD
  DPUP 0d04
  PSHD
  SETD RowCount
  LDA
  DECA
  STA
  BRA evolveDone
  POPD
  BRI evolveRow

evolveDone:
  POPD
  RET

; DP points to the current-state byte of a visible cell.
evolveCell:
  CALL countNeighbors
  PSHQ
  LDA
  POPB

  ; Three neighbors always produces a live cell.
  INIA 0d03
  CCF
  SUB
  BRQ makeAlive

  ; Two neighbors preserve the current state.
  INIA 0d02
  CCF
  SUB
  BRQ preserveCell

makeDead:
  RSTA
  INCD
  STA
  DECD
  RET

preserveCell:
  LDA
  BRA makeDead

makeAlive:
  INIA 0x01
  INCD
  STA
  DECD
  RET

; Return the sum of the eight neighboring current-state bytes in Q.
; With interleaved cells and an 18-cell row, the relative offsets are:
; -38, -36, -34, -2, +2, +34, +36, +38.
countNeighbors:
  RSTA
  DPDN 0d38

  LDB
  CCF
  ADD
  PSHQ
  POPA
  DPUP 0d02

  LDB
  CCF
  ADD
  PSHQ
  POPA
  DPUP 0d02

  LDB
  CCF
  ADD
  PSHQ
  POPA
  DPUP 0d32

  LDB
  CCF
  ADD
  PSHQ
  POPA
  DPUP 0d04

  LDB
  CCF
  ADD
  PSHQ
  POPA
  DPUP 0d32

  LDB
  CCF
  ADD
  PSHQ
  POPA
  DPUP 0d02

  LDB
  CCF
  ADD
  PSHQ
  POPA
  DPUP 0d02

  LDB
  CCF
  ADD
  RET

; Copy every next-state byte to its adjacent current-state byte.
; The border's next bytes remain zero, so it stays permanently dead.
commitBoard:
  SETD Board
  INIA 0d18
  SETD RowCount
  STA
  SETD Board

commitRow:
  PSHD
  INIA 0d18
  SETD ColCount
  STA
  POPD

commitCell:
  INCD
  LDA
  DECD
  STA
  DPUP 0d02
  PSHD
  SETD ColCount
  LDA
  DECA
  STA
  BRA commitRowDone
  POPD
  BRI commitCell

commitRowDone:
  POPD
  PSHD
  SETD RowCount
  LDA
  DECA
  STA
  BRA commitDone
  POPD
  BRI commitRow

commitDone:
  POPD
  RET

; Approximately 0.2 seconds at the emulator's nominal 1 MHz rate.
frameDelay:
  INIA 0xFF
delayOuter:
  INIB 0xFF
delayInner:
  DECB
  BRB delayInnerDone
  BRI delayInner
delayInnerDone:
  DECA
  BRA delayDone
  BRI delayOuter
delayDone:
  RET

#Data

RowCount:
  0x00
ColCount:
  0x00

ClearScreen:
  0x1B
  "[2J"
CursorHome:
  0x1B
  "[H"

; The emulator zero-fills the remainder of Data Memory. Board names the first
; byte of a 648-byte logical allocation (18 * 18 * 2).
Board:
  0x00
