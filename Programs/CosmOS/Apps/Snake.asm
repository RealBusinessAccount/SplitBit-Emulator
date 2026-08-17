; Snake, as an application CosmOS can load and run.
;
; The first program written for this machine that is played rather than watched. It needs
; key mode: in line mode the terminal holds what is typed until Return, so steering would
; mean pressing a direction and then Enter, and by the time it arrived the snake would
; have been into the wall for some time.
;
; It asks the console once a frame whether a key is waiting, and never waits for one. The
; console holds the next key until it is asked, so nothing typed between frames is lost,
; and a script of moves plays back one move to a frame.
;
; WHY IT POLLS RATHER THAN INTERRUPTS. The console can raise an interrupt line when a byte
; arrives, which is the better shape for a game: the loop would never look at the console
; at all. A loaded program cannot use it. Installing a handler means putting an address in
; the vector table, and the loadable program format carries only code and data - a program
; that is not the one the machine booted from has no way to say what its vectors are. So
; interrupts belong to boot images for now, and this asks once a frame, which is what the
; machines this one is pretending to be did anyway.
;
; THE BOARD IS A PAGE, and that is the whole trick this program turns on. Sixteen by
; sixteen is 256 squares, so a square number is a byte, and the board is aligned so that
; the square number IS the low byte of its address. Reaching a square is writing its
; number into the low half of a stored pointer and loading the pointer back - no
; multiplying, no carrying, and the row and column fall out as the two nibbles.
;
; The body is a second page, used as a ring of square numbers with the oldest segment at
; the tail. Moving is putting a square on the head end and taking one off the tail end,
; so the cost of a move does not depend on how long the snake is. The ring wraps at 256
; by itself, because an index into it is a byte and a byte is all it can be.
;
; Note that #Include console.asm comes at the END of this file. A loadable program starts
; at the first byte of its code, so the first instruction in this file has to be the one
; the program begins with.

#Include services.asm

#Program

  #Base 0x2000

start:
  ; The two pointers whose low byte is a square number. Both regions are page aligned, so
  ; the high byte written here is the whole of what does not change, and nothing after
  ; this ever has to work out an address.
  SETD.0 Board
  SETD.1 CellAddress
  STD.0.1
  SETD.0 Body
  SETD.1 BodyAddress
  STD.0.1

  ; Everything is set here rather than trusted to be zero, because a program that is run
  ; twice without being loaded again finds its Data Segment exactly as the last run left
  ; it. The board is the obvious half of that; the score and the direction are the half
  ; that would be missed.
  CALL resetState
  CALL clearBoard
  CALL placeSnake
  CALL placeFood

  SETD.0 ClearScreen
  CALL printString

  ; Key mode, so that one key is one byte and arrives when it is pressed. It is put back
  ; before this returns, and CosmOS puts it back too in case a program stops without
  ; doing so.
  INIA 0x01
  OUTA 0x02

gameLoop:
  CALL takeKey
  SETD.0 Quitting
  LDA.0
  BNA gameOver

  CALL advance
  SETD.0 Dead
  LDA.0
  BNA gameOver

  CALL draw
  CALL pause
  BRI gameLoop

gameOver:
  ; Drawn once more so the last thing on the screen is the position it ended in.
  CALL draw
  SETD.0 Won
  LDA.0
  BNA gameOverWon
  SETD.0 Quitting
  LDA.0
  BNA gameOverQuit
  SETD.0 DeadText
  BRI gameOverSay
gameOverWon:
  SETD.0 WonText
  BRI gameOverSay
gameOverQuit:
  SETD.0 QuitText
gameOverSay:
  CALL printString
  CALL newLine
  RSTA
  OUTA 0x02                 ; Line mode, the way it was found.
  SWI osExit

; ---- Reaching a square ----
;
; A holds a square number. Leaves DP3 pointing at that square of the board.
;
; DP3 because a subroutine cannot hand back any of the others: CALL saves DP0 through DP2
; and RET puts them back, so an assignment to one of them here would be undone on the way
; out. The same reason means a caller must not keep anything in DP3 across one of these.
cellPointer:
  SETD.0 CellAddress
  INCD.0
  STA.0                     ; The square number is the low half of its own address.
  DECD.0
  LDD.3.0
  RET

; A holds a position in the body ring. Leaves DP3 pointing at it.
bodyPointer:
  SETD.0 BodyAddress
  INCD.0
  STA.0
  DECD.0
  LDD.3.0
  RET

; ---- Setting up ----

resetState:
  RSTA
  SETD.0 Score
  STA.0
  SETD.0 Dead
  STA.0
  SETD.0 Quitting
  STA.0
  SETD.0 Won
  STA.0
  SETD.0 Length
  STA.0
  SETD.0 BodyHead
  STA.0
  SETD.0 BodyTail
  STA.0
  INIA 0x03
  SETD.0 Direction
  STA.0                     ; Moving right, which is where the three segments point.

  ; The seed is copied rather than used in place, so that a second run starts the same
  ; game as the first. A game that came out differently every time would be nicer to
  ; play and impossible to record.
  SETD.0 RandomSeed
  SETD.1 RandomState
  LDA.0
  STA.1
  INCD.0
  INCD.1
  LDA.0
  STA.1
  RET

clearBoard:
  SETD.0 Board
  RSTB
clearBoardSquare:
  RSTA
  STA.0
  INCD.0
  INCB
  BNB clearBoardSquare      ; B comes back to zero after all 256 squares.
  RET

; Three segments across the middle of the board, oldest first, so the leftmost is the
; tail and the rightmost is the head.
placeSnake:
  INIA 0x86
  CALL addSegment
  INIA 0x87
  CALL addSegment
  INIA 0x88
  CALL addSegment
  RET

; A holds a square. Marks it as snake and puts it on the head end of the ring.
addSegment:
  PSHA
  CALL cellPointer
  INIB 0x01
  STB.3

  SETD.0 Length
  LDA.0
  CALL bodyPointer          ; The ring fills forwards from zero while setting up.
  POPA
  STA.3

  SETD.0 HeadCell
  STA.0                     ; The newest segment is always the head.
  SETD.0 Length
  LDA.0
  INCA
  STA.0
  DECA
  SETD.0 BodyHead
  STA.0                     ; Which is at Length minus one.
  RET

; ---- Food ----
;
; A square is chosen at random, and if something is already there the search walks
; forwards until it finds somewhere empty. That does two jobs with one loop: it keeps the
; food off the snake, and it means the generator never has to be asked twice.
placeFood:
  CALL randomByte
  MVQA
  SETD.3 FoodStart
  STA.3
placeFoodLook:
  CALL cellPointer
  LDB.3
  BRB placeFoodHere         ; Empty, and A still holds which square it was.
  INCA
  SETD.3 FoodStart
  LDB.3
  XOR                       ; All the way round to where the search began?
  BRQ placeFoodFull
  BRI placeFoodLook

placeFoodHere:
  INIB 0x02
  STB.3                     ; DP3 is still on the square that was found empty.
  RET

placeFoodFull:
  ; Nowhere to put it, which means the snake is the board. There is no way to lose from
  ; here and nothing left to do, so it counts as finishing rather than as an error.
  SETD.0 Won
  INIA 0x01
  STA.0
  SETD.0 Dead
  STA.0
  RET

; A sixteen bit shift register, rotated right one bit a time, with the bit that falls off
; the bottom fed back into four places along it. Q comes back holding the high half, which
; is the part that changes least predictably.
;
; SHR rotates A and B together as one sixteen bit register, so the bit that leaves the
; bottom of B arrives at the top of A. That is not the shift a shift register wants - it
; wants that bit gone - so where the bit came round is exactly where the feedback goes,
; and one XOR both clears it and applies the taps.
randomByte:
  SETD.3 RandomState
  LDA.3
  INCD.3
  LDB.3
  SHR
  PSHB
  INIB 0x80
  AND
  POPB
  BRQ randomNoFeedback
  PSHB
  INIB 0x34                 ; 0x80 clears the bit that came round, 0xB4 is the taps.
  XOR
  MVQA
  POPB
randomNoFeedback:
  STB.3
  DECD.3
  STA.3
  RSTB
  OR                        ; Q is A, which is what a routine hands back in.
  RET

; ---- Steering ----
;
; One key a frame, and never a wait for one. The console keeps the next key until it is
; asked for, so a key pressed while the snake was moving is still there next frame.
takeKey:
  INA 0x01
  INIB 0x01                 ; READY: is there a byte to be had?
  AND
  BRQ takeKeyDone
  INA 0x00

  INIB 0x71                 ; q
  XOR
  BRQ takeKeyQuit
  INIB 0x77                 ; w
  XOR
  BRQ takeKeyUp
  INIB 0x73                 ; s
  XOR
  BRQ takeKeyDown
  INIB 0x61                 ; a
  XOR
  BRQ takeKeyLeft
  INIB 0x64                 ; d
  XOR
  BRQ takeKeyRight
takeKeyDone:
  RET

takeKeyUp:
  RSTA
  BRI takeKeyTurn
takeKeyDown:
  INIA 0x01
  BRI takeKeyTurn
takeKeyLeft:
  INIA 0x02
  BRI takeKeyTurn
takeKeyRight:
  INIA 0x03

takeKeyTurn:
  ; A snake cannot turn back into itself. The four directions are numbered so that two
  ; opposite ones differ in exactly their lowest bit and nothing else, which makes the
  ; whole test one XOR against one.
  PSHA
  SETD.0 Direction
  LDB.0
  XOR
  MVQA
  INIB 0x01
  XOR
  POPA
  BRQ takeKeyDone           ; Opposite, so it is not a turn anybody can make.
  SETD.0 Direction
  STA.0
  RET

takeKeyQuit:
  SETD.0 Quitting
  INIA 0x01
  STA.0
  RET

; ---- Moving ----

advance:
  CALL step
  SETD.0 Dead
  LDA.0
  BNA advanceDone           ; Into a wall, and there is nowhere to move to.

  ; What is in the square the head is moving into?
  SETD.0 NextCell
  LDA.0
  CALL cellPointer
  LDB.3
  BRB advanceMove           ; Empty.
  DECB
  DECB
  BRB advanceEat            ; It held a two, which is food.

  ; A one, so it is the snake. There is exactly one square of itself a snake may move
  ; into, and that is the one the tail is standing on, because the tail is leaving it in
  ; the same move. This is what lets a snake follow itself round a corner instead of
  ; dying on the segment that is getting out of its way.
  ;
  ; Asked as a question about the tail rather than by taking the tail off and looking at
  ; what is left. Both give the same answer, but this one does not have to be undone when
  ; the answer is that the snake is dead, and a dead snake that had already lost its tail
  ; would be drawn a segment short in the last frame anybody sees.
  CALL tailCell
  MVQB
  SETD.0 NextCell
  LDA.0
  XOR
  BNQ advanceHitSelf

advanceMove:
  CALL removeTail
  CALL addHead
  RET

advanceEat:
  RSTB
  STB.3                     ; The food is gone. DP3 is still on that square.
  ; No tail comes off, and that is the whole of what growing is.
  CALL addHead
  SETD.0 Score
  LDA.0
  INCA
  STA.0
  CALL placeFood
advanceDone:
  RET

advanceHitSelf:
  SETD.0 Dead
  INIA 0x01
  STA.0
  RET

; Where the head would go, or a wall. The row is the high nibble of a square number and
; the column is the low one, so every edge of the board is a question about one nibble.
step:
  SETD.0 HeadCell
  LDA.0
  SETD.0 Direction
  LDB.0
  BRB stepUp
  DECB
  BRB stepDown
  DECB
  BRB stepLeft
  BRI stepRight

stepUp:
  INIB 0xF0
  AND
  BRQ stepWall              ; The top row is where the high nibble is zero.
  CCF
  INIB 0x10
  SUB
  BRI stepMoved

stepDown:
  PSHA
  INIB 0xF0
  AND
  MVQA
  INIB 0xF0
  XOR
  POPA
  BRQ stepWall              ; The bottom row is where the high nibble is fifteen.
  CCF
  INIB 0x10
  ADD
  BRI stepMoved

stepLeft:
  INIB 0x0F
  AND
  BRQ stepWall
  CCF
  INIB 0x01
  SUB
  BRI stepMoved

stepRight:
  PSHA
  INIB 0x0F
  AND
  MVQA
  INIB 0x0F
  XOR
  POPA
  BRQ stepWall
  CCF
  INIB 0x01
  ADD

stepMoved:
  MVQA
  SETD.0 NextCell
  STA.0
  RET

stepWall:
  SETD.0 Dead
  INIA 0x01
  STA.0
  RET

addHead:
  SETD.0 NextCell
  LDA.0
  CALL cellPointer
  INIB 0x01
  STB.3

  SETD.0 BodyHead
  LDA.0
  INCA
  STA.0                     ; The ring wraps at 256 on its own, which is why it is a page.
  CALL bodyPointer
  SETD.0 NextCell
  LDA.0
  STA.3

  SETD.0 HeadCell
  STA.0
  SETD.0 Length
  LDA.0
  INCA
  STA.0
  RET

; Q is the square the oldest segment is standing on.
tailCell:
  SETD.0 BodyTail
  LDA.0
  CALL bodyPointer
  LDA.3
  RSTB
  OR
  RET

removeTail:
  SETD.0 BodyTail
  LDA.0
  CALL bodyPointer
  LDA.3                     ; Which square the oldest segment is standing on.
  CALL cellPointer
  RSTB
  STB.3

  SETD.0 BodyTail
  LDA.0
  INCA
  STA.0
  SETD.0 Length
  LDA.0
  DECA
  STA.0
  RET

; ---- Drawing ----
;
; The whole board, every frame, from the top left corner. Sixteen by sixteen is small
; enough that working out what changed would cost more than sending it all again.
draw:
  SETD.0 CursorHome
  CALL printString
  SETD.0 BorderText
  CALL printString
  CALL newLine

  SETD.2 Board              ; Walks the board a square at a time, in order.
  RSTB                      ; Which square, which is also its row and column.
drawRow:
  INIA 0x7C                 ; |
  OUTA 0x00
drawSquare:
  SETD.0 HeadCell
  LDA.0
  XOR                       ; Zero on the one square the head is standing on.
  BRQ drawHead
  LDA.2
  BRA drawEmpty
  DECA
  BRA drawBody
  INIA 0x2A                 ; *
  BRI drawPut
drawHead:
  INIA 0x40                 ; @
  BRI drawPut
drawBody:
  INIA 0x23                 ; #
  BRI drawPut
drawEmpty:
  INIA 0x20
drawPut:
  OUTA 0x00
  INCD.2
  INCB
  INIA 0x0F
  AND
  BNQ drawSquare            ; Sixteen to a row.
  INIA 0x7C
  OUTA 0x00
  CALL newLine
  BNB drawRow               ; And sixteen rows, after which B is back to zero.

  SETD.0 BorderText
  CALL printString
  CALL newLine
  SETD.0 ScoreText
  CALL printString
  SETD.0 Score
  LDA.0
  CALL printByteDecimal
  SETD.0 KeysText
  CALL printString
  CALL newLine
  RET

; ---- Waiting ----
;
; There is no clock on this machine, so time is counted in instructions. At the emulated
; rate this is about an eighth of a second, which is a speed a person can play at. Running
; the emulator faster or slower moves it, and that is the honest answer: the machine has
; no way to know how long a second is and this program is not going to pretend it does.
pause:
  RSTB
pauseOuter:
  RSTA
pauseInner:
  DECA
  BNA pauseInner
  DECB
  BNB pauseOuter
  RET

#Data

  #Base 0x1000

HeadCell:
  0x00
NextCell:
  0x00
Direction:
  0x00
BodyHead:
  0x00
BodyTail:
  0x00
Length:
  0x00
Score:
  0x00
Dead:
  0x00
Quitting:
  0x00
Won:
  0x00
FoodStart:
  0x00

; A square number written into the low byte of one of these makes it the address of that
; square. The high byte is set once at the start and never changes, which is the whole
; reason both regions are page aligned.
CellAddress:
  0x00 0x00
BodyAddress:
  0x00 0x00

; Anything but zero will do, because a shift register that reaches zero stays there.
RandomSeed:
  0xAC 0xE1
RandomState:
  0x00 0x00

ClearScreen:
  0x1B
  "[2J"
CursorHome:
  0x1B
  "[H"

BorderText:
"+----------------+"
ScoreText:
" score "
KeysText:
"    wasd steers, q stops"

DeadText:
"you ran into something"
QuitText:
"stopped"
WonText:
"the board is full and there is nothing left to eat"

  #Align 0x0100
Board:
  #Reserve 0d256
Body:
  #Reserve 0d256

#Include console.asm
