; Conway's Game of Life rewritten for SplitBit's four-Data-Pointer ISA.
;
; The representation and display match 16x16Life.asm: a visible 16x16 field,
; a dead border, and interleaved current/next bytes. DP0 walks the board, DP1
; and DP2 address the loop counters, and volatile DP3 walks the neighborhood.

#Include print.asm

#Program

start:
  CALL seedGlider
  SETD.0 ClearScreen
  CALL printString

generationLoop:
  CALL renderBoard
  CALL evolveBoard
  CALL commitBoard
  CALL frameDelay
  BRI generationLoop

seedGlider:
  SETD.0 Board
  DPUP.0 0d42
  INIA 0x01
  STA.0
  SETD.0 Board
  DPUP.0 0d80
  STA.0
  SETD.0 Board
  DPUP.0 0d112
  STA.0
  DPUP.0 0d02
  STA.0
  DPUP.0 0d02
  STA.0
  RET

renderBoard:
  SETD.0 CursorHome
  CALL printString
  SETD.1 RowCount
  SETD.2 ColCount
  INIA 0d16
  STA.1
  SETD.0 Board
  DPUP.0 0d38

renderRow:
  INIA 0d16
  STA.2
renderCell:
  LDA.0
  BRA renderDead
  INIB 0x23
  OUTB 0x00
  BRI renderCellDone
renderDead:
  INIB 0x20
  OUTB 0x00
renderCellDone:
  DPUP.0 0d02
  LDA.2
  DECA
  STA.2
  BRA renderRowDone
  BRI renderCell

renderRowDone:
  CALL lineFeed
  DPUP.0 0d04
  LDA.1
  DECA
  STA.1
  BRA renderDone
  BRI renderRow
renderDone:
  RET

evolveBoard:
  SETD.1 RowCount
  SETD.2 ColCount
  INIA 0d16
  STA.1
  SETD.0 Board
  DPUP.0 0d38

evolveRow:
  INIA 0d16
  STA.2
evolveCellLoop:
  CALL evolveCell
  DPUP.0 0d02
  LDA.2
  DECA
  STA.2
  BRA evolveRowDone
  BRI evolveCellLoop

evolveRowDone:
  DPUP.0 0d04
  LDA.1
  DECA
  STA.1
  BRA evolveDone
  BRI evolveRow
evolveDone:
  RET

evolveCell:
  CALL countNeighbors
  MVQB              ; B is the neighbor count from here down.

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
  INCD.0
  STA.0
  DECD.0
  RET

preserveCell:
  LDA.0
  BRA makeDead

makeAlive:
  INIA 0x01
  INCD.0
  STA.0
  DECD.0
  RET

; Return the eight-neighbor sum in Q. One Stack round-trip copies DP0 into
; volatile DP3; MVQA then keeps the running total entirely in registers.
countNeighbors:
  PSHD.0
  POPD.3
  RSTA
  DPDN.3 0d38

  LDB.3
  CCF
  ADD
  MVQA
  DPUP.3 0d02

  LDB.3
  CCF
  ADD
  MVQA
  DPUP.3 0d02

  LDB.3
  CCF
  ADD
  MVQA
  DPUP.3 0d32

  LDB.3
  CCF
  ADD
  MVQA
  DPUP.3 0d04

  LDB.3
  CCF
  ADD
  MVQA
  DPUP.3 0d32

  LDB.3
  CCF
  ADD
  MVQA
  DPUP.3 0d02

  LDB.3
  CCF
  ADD
  MVQA
  DPUP.3 0d02

  LDB.3
  CCF
  ADD
  RET

commitBoard:
  SETD.1 RowCount
  SETD.2 ColCount
  INIA 0d18
  STA.1
  SETD.0 Board

commitRow:
  INIA 0d18
  STA.2
commitCell:
  INCD.0
  LDA.0
  DECD.0
  STA.0
  DPUP.0 0d02
  LDA.2
  DECA
  STA.2
  BRA commitRowDone
  BRI commitCell

commitRowDone:
  LDA.1
  DECA
  STA.1
  BRA commitDone
  BRI commitRow
commitDone:
  RET

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

; 18 by 18 cells with the current and next states interleaved, so 648 bytes. The
; original leaves this implicit and leans on Data Memory being zero, which works but
; means the assembler believes the board is one byte long: anything placed after it
; would land inside it, and nothing would say so. Reserving the region states how far
; it reaches, so a label added below here is safe.
Board:
  #Reserve 0d648
