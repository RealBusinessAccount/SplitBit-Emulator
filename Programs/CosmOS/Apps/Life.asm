; Conway's Game of Life, as an application CosmOS can load and run.
;
; Ported from gameOfLife/16x16LifeModern.asm. The simulation is unchanged: the same
; interleaved 18 by 18 board with a dead border, the same four-Data-Pointer rewrite of
; the neighbor count, and the same glider.
;
; What had to change is when it stops. On the bare machine this program never stopped,
; because Life has no end state to reach and nothing was waiting for the machine back.
; Under CosmOS a program owns the console until it returns, so a program that never ends
; takes the shell with it. There is no HALT to fall into and no key that can interrupt
; it: console input is a blocking read, so a running program cannot ask whether anybody
; has pressed anything.
;
; So it stops on its own, two ways:
;
;   IT SETTLES. commitBoard already walks the current and next state of every cell side
;   by side, so it can notice for free whether any of them differed. When none did, the
;   board has reached a state it will stay in forever and there is nothing left to show.
;   The glider does reach one: it crosses the field, runs into the dead border, and
;   collapses into a block in the corner at generation 54.
;
;   IT RUNS OUT. Settling catches still lifes and extinction. It does not catch an
;   oscillator - a blinker would flip back and forth forever and never be "unchanged" -
;   so there is a generation limit behind it. It is not meant to be the answer. It is
;   there so that no seed anybody tries later can take the shell down with it.
;
; Note that #Include print.asm comes at the END of this file rather than the beginning.
; print.asm opens with a branch to start, which is what a boot image wants at address
; zero; a loadable program wants its own first instruction at its code base instead.

#Include services.asm

#Program

    #Base 0x2000

start:
  CALL seedGlider
  SETD.0 ClearScreen
  CALL printString
  SETD.3 GenerationsLeft
  INIA 0xFF
  STA.3

  ; Key mode, so that one keypress is one byte and stops it. In line mode the terminal
  ; holds what is typed until Return, so nothing arrives until then and "press any key"
  ; would really mean "press any key and then Return". It is put back before this program
  ; returns; CosmOS puts it back too, in case a program stops without doing so.
  INIA 0x01
  OUTA 0x02

generationLoop:
  CALL renderBoard
  CALL evolveBoard
  CALL commitBoard

  ; Has anybody asked it to stop? The status port answers without waiting, which is the
  ; whole reason it exists: reading the data port here would stop the simulation dead
  ; until somebody typed something, which is the opposite of what is wanted.
  ;
  ; READY is clear at the end of input as well as when nothing has been typed, so running
  ; with input from a file - which is how the tests run it - never stops here. It runs to
  ; the still life instead, and that is the right answer in both places.
  INA 0x01
  INIB 0x01                 ; READY
  AND
  BRQ lifeNoKey
  INA 0x00                  ; Take the key, so it is not left waiting for the shell.
  BRI lifeStopped
lifeNoKey:

  ; commitBoard leaves the flag set if any cell differed from what replaced it. DP3 is
  ; pointed at it again rather than trusting what the call left behind: RET does not put
  ; DP3 back, so its value after a call is the callee's business and not a promise.
  SETD.3 BoardChanged
  LDA.3
  BRA lifeSettled

  SETD.3 GenerationsLeft
  LDA.3
  DECA
  STA.3
  BRA lifeRanOut

  CALL frameDelay
  BRI generationLoop

; The three ways it can be over. Each one only picks the words; the tidying up is the same
; for all of them and is written once, which is also how the console cannot be left in key
; mode down one path and not another.
lifeStopped:
  SETD.0 StoppedText
  BRI lifeEnd

lifeSettled:
  SETD.0 SettledText
  BRI lifeEnd

lifeRanOut:
  SETD.0 RanOutText

lifeEnd:
  RSTA
  OUTA 0x02                 ; Line mode, the way it was found.
  CALL lineFeed
  CALL printString          ; DP0 still holds the words: CALL puts DP0 back.
  CALL lineFeed
  SWI osExit

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

; Copies each cell's next state over its current one, and says whether any of them
; differed. The comparison is what the bare metal version did not need: it is one XOR
; on two bytes that are already in registers, in a loop that was already visiting every
; cell, which is why "has it settled" costs almost nothing to ask.
;
; DP3 holds the flag for the whole walk. commitBoard calls nothing, so nothing else can
; want DP3 while it works.
commitBoard:
  SETD.3 BoardChanged
  RSTA
  STA.3
  SETD.1 RowCount
  SETD.2 ColCount
  INIA 0d18
  STA.1
  SETD.0 Board

commitRow:
  INIA 0d18
  STA.2
commitCell:
  LDB.0                     ; The cell as it stands.
  INCD.0
  LDA.0                     ; The cell as it is about to stand.
  DECD.0
  STA.0
  XOR                       ; Q is zero only if those two were the same.
  BRQ commitSame
  INIA 0x01
  STA.3                     ; Something moved, so this is not the last generation.
commitSame:
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

    #Base 0x1000

RowCount:
  0x00
ColCount:
  0x00

; Cleared at the top of every commitBoard and set by any cell that changed, so after a
; commit it describes that generation and no other.
BoardChanged:
  0x00
; Counts down. One byte is enough for a limit that is not meant to be reached.
GenerationsLeft:
  0x00

SettledText:
"the board has settled"
RanOutText:
"stopped: still changing after 255 generations"
StoppedText:
"stopped"

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

#Include print.asm
