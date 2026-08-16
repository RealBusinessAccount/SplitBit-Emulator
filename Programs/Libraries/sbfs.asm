; sbfs.asm
; Reading the SplitBit Filesystem.
;
; The other implementation of this format is SplitDisk on the host. Nothing is shared
; between them but the written specification, so anything that changes here has to change
; there in the same breath.
;
; The disk's buffer is registered as bank 3, and every block read lands there and is then
; blitted where it is wanted. The CPU never touches the buffer directly, because nothing
; can: memory a device brings is reachable only through the controller.
;
; Written by Anachronaut

#Program

; Registers the disk's buffer, reads the superblock, and checks that the disk really is
; one of ours. Q is zero if the disk is ready to be read.
sbfsMount:
  INIA 0d3
  OUTA 0xE3
  INIA 0x20
  OUTA 0xE2
  INIA 0x03
  OUTA 0xE8             ; RegisterBank: bank 3 is the disk's buffer.

  SETD.0 SbfsBlock
  RSTA
  STA.0
  INCD.0
  STA.0                 ; Block 0, the superblock.
  CALL sbfsReadBlock
  BRQ sbfsMountRead
  RET                   ; The read failed, and Q says so.

sbfsMountRead:
  SETD.1 SbfsBuffer
  CALL sbfsBufferOut

  ; "SBFS", or this is not a disk of ours. A blank image is all zeroes, so without this
  ; an unformatted disk would look like a formatted one with no files on it.
  SETD.0 SbfsBuffer
  SETD.2 SbfsMagic
  INIA 0d4
  SETD.1 SbfsCount
  STA.1
sbfsMagicLoop:
  CALL sbfsSameByte
  BRQ sbfsMagicSame
  RET                   ; Q is the difference, which is not zero.
sbfsMagicSame:
  INCD.0
  INCD.2
  LDA.1
  DECA
  STA.1
  BNA sbfsMagicLoop

sbfsMagicDone:
  ; The version has to be one we understand.
  SETD.0 SbfsBuffer
  DPUP.0 0d04
  LDA.0
  INIB 0d1
  XOR
  BRQ sbfsGeometry
  RET                   ; A version we do not know.

sbfsGeometry:
  ; Where the directory is and how big it is. The superblock carries both so that disks
  ; of different sizes can have different directories without a new format.
  SETD.0 SbfsBuffer
  DPUP.0 0d08
  SETD.1 SbfsDirStart
  CALL sbfsCopyWord
  SETD.0 SbfsBuffer
  DPUP.0 0d10
  SETD.1 SbfsDirBlocks
  CALL sbfsCopyWord
  SETD.0 SbfsBuffer
  DPUP.0 0d06
  SETD.1 SbfsDiskBlocks
  CALL sbfsCopyWord
  RSTA
  RSTB
  CCF
  ADD                   ; Q is zero: mounted.
  RET

; Finds a file by name. DP0 points at a name, ending in a zero byte. Q is zero if it was
; found, and then SbfsFileStart, SbfsFileBlocks and SbfsFileTail describe it.
sbfsFind:
  SETD.1 SbfsWanted
  CALL sbfsKeepName

  ; Start at the first directory block and work through them all.
  SETD.0 SbfsDirStart
  SETD.1 SbfsBlock
  CALL sbfsCopyWord
  SETD.0 SbfsDirBlocks
  DPUP.0 0d01
  LDA.0
  SETD.1 SbfsLeft
  STA.1                 ; Only the low byte: a directory of 256 blocks is 2048 files.

sbfsFindBlock:
  CALL sbfsReadBlock
  BRQ sbfsFindLoaded
  RET                   ; The read failed.
sbfsFindLoaded:
  SETD.1 SbfsBuffer
  CALL sbfsBufferOut

  ; Eight entries to a block, thirty two bytes each.
  SETD.2 SbfsBuffer
  INIA 0d8
  SETD.1 SbfsCount
  STA.1

sbfsFindEntry:
  LDA.2
  INIB 0x01
  AND
  BRQ sbfsFindNext      ; The in use bit is down, so this entry is free.
  CALL sbfsMatchEntry
  BRQ sbfsFindFound

sbfsFindNext:
  DPUP.2 0d32
  LDA.1
  DECA
  STA.1
  BNA sbfsFindEntry

sbfsFindNextBlock:
  SETD.0 SbfsBlock
  CALL sbfsStepWord
  SETD.1 SbfsLeft
  LDA.1
  DECA
  STA.1
  BRA sbfsFindMissing
  BRI sbfsFindBlock

sbfsFindMissing:
  ; Nothing of that name. Q has to be something other than zero to say so.
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

sbfsFindFound:
  ; DP2 is on the entry. Keep it in DP3 while the pieces are taken out of it: DP3 is the
  ; pointer a CALL does not put back, so it is the only one that survives a subroutine.
  ; Copying it into DP0 has to be done here rather than in a routine of its own, for the
  ; same reason: a routine that set DP0 would have the assignment undone by its own RET.
  PSHD.2
  POPD.3

  PSHD.3
  POPD.0
  DPUP.0 0d01
  SETD.1 SbfsFileStart
  CALL sbfsCopyWord

  PSHD.3
  POPD.0
  DPUP.0 0d03
  SETD.1 SbfsFileBlocks
  CALL sbfsCopyWord

  PSHD.3
  POPD.0
  DPUP.0 0d05
  LDA.0
  SETD.1 SbfsFileTail
  STA.1

  RSTA
  RSTB
  CCF
  ADD                   ; Q is zero: found.
  RET

; Compares the name in the entry at DP2 with the one kept in SbfsWanted. Q is zero if
; they are the same. Names are padded with zeroes rather than terminated, so a name that
; fills the field has no terminator to look for, which is why the count is what stops it.
sbfsMatchEntry:
  PSHD.2
  POPD.0
  DPUP.0 0d06           ; The name inside the entry.
  SETD.2 SbfsWanted
  INIA 0d22
  SETD.1 SbfsCount
  STA.1

sbfsMatchLoop:
  CALL sbfsSameByte
  BRQ sbfsMatchSame
  RET                   ; They differ, and Q is the difference.
sbfsMatchSame:
  LDA.0
  BRA sbfsMatchYes      ; Both ended in the same place.
  INCD.0
  INCD.2
  LDA.1
  DECA
  STA.1
  BNA sbfsMatchLoop     ; Twenty two the same is the same name, so falling out is a match.

sbfsMatchYes:
  RSTA
  RSTB
  CCF
  ADD
  RET

; Copies the name at DP0 into DP1, twenty two bytes of it, padding with zeroes the way an
; entry is padded so that the two can be compared as they stand.
sbfsKeepName:
  INIA 0d22
  SETD.2 SbfsCount
  STA.2
  RSTB                  ; B stays zero once the name has ended.
sbfsKeepLoop:
  LDA.0
  BRA sbfsKeepPad
  STA.1
  INCD.0
  BRI sbfsKeepStep
sbfsKeepPad:
  STB.1
sbfsKeepStep:
  INCD.1
  LDA.2
  DECA
  STA.2
  BNA sbfsKeepLoop
sbfsKeepDone:
  RET

; Reads the file that sbfsFind found into Data Memory at DP1. Q is zero if it worked.
;
; Whole blocks are copied whole, including the last one, so the bytes after the end of a
; file are whatever else was in that block on the disk. SbfsFileTail says where the file
; actually stops, and it is the caller's business to respect it.
;
; A file of more than 255 blocks is not handled here. That is 64K, which is the whole of
; Data Memory, so it could not be read into it anyway.
sbfsRead:
  PSHD.1
  POPD.3                ; Where it goes. DP3 survives a CALL, and nothing called here
                        ; touches it.
  SETD.0 SbfsFileStart
  SETD.1 SbfsBlock
  CALL sbfsCopyWord

  SETD.0 SbfsFileBlocks
  DPUP.0 0d01
  LDA.0
  SETD.1 SbfsLeft
  STA.1
  SETD.0 SbfsFileTail
  LDA.0
  BRA sbfsReadCounted   ; No part block on the end.
  SETD.0 SbfsLeft
  LDA.0
  INCA
  STA.0                 ; One more block for the tail.

sbfsReadCounted:
  SETD.0 SbfsLeft
  LDA.0
  BRA sbfsReadDone      ; An empty file has nothing to read.

sbfsReadLoop:
  CALL sbfsReadBlock
  BRQ sbfsReadGot
  RET                   ; The read failed, and Q says so.
sbfsReadGot:
  PSHD.3
  POPD.1
  CALL sbfsBufferOut

  ; On by a whole block. DPUP carries one byte at a time, so 256 takes two of them.
  DPUP.3 0xFF
  DPUP.3 0x01
  SETD.0 SbfsBlock
  CALL sbfsStepWord

  SETD.0 SbfsLeft
  LDA.0
  DECA
  STA.0
  BNA sbfsReadLoop

sbfsReadDone:
  RSTA
  RSTB
  CCF
  ADD                   ; Q is zero: read.
  RET

; ---- Writing ----

; Where the first block that can hold a file is: past the superblock and the directory.
sbfsFirstData:
  SETD.0 SbfsCandidate
  SETD.2 SbfsDirStart
  CALL sbfsSetWord
  SETD.0 SbfsCandidate
  SETD.2 SbfsDirBlocks
  CALL sbfsAddWord
  RET

; SbfsEntryStart and SbfsEntryEnd describe the file in the entry at DP2. The end is one
; past the last block it holds, and a file of nothing holds none, so its end is its start.
sbfsEntryBounds:
  PSHD.2
  POPD.3
  PSHD.3
  POPD.0
  DPUP.0 0d01
  SETD.1 SbfsEntryStart
  CALL sbfsCopyWord
  SETD.0 SbfsEntryEnd
  SETD.2 SbfsEntryStart
  CALL sbfsSetWord
  PSHD.3
  POPD.0
  DPUP.0 0d03
  SETD.1 SbfsScratch
  CALL sbfsCopyWord
  SETD.0 SbfsEntryEnd
  SETD.2 SbfsScratch
  CALL sbfsAddWord
  PSHD.3
  POPD.0
  DPUP.0 0d05
  LDA.0
  BRA sbfsBoundsDone    ; No part block on the end.
  SETD.0 SbfsEntryEnd
  SETD.2 SbfsOne
  CALL sbfsAddWord
sbfsBoundsDone:
  RET

; Finds a run of SbfsWantBlocks free blocks and puts where it begins in SbfsFileStart.
; Q is zero if there was room.
;
; First fit, walking the directory, because with files laid down contiguously the
; directory already says which blocks are spoken for. There is no allocation table to
; consult and none to keep right.
sbfsAllocate:
  CALL sbfsFirstData

sbfsAllocTry:
  SETD.0 SbfsCandEnd
  SETD.2 SbfsCandidate
  CALL sbfsSetWord
  SETD.0 SbfsCandEnd
  SETD.2 SbfsWantBlocks
  CALL sbfsAddWord

  ; Past the end of the disk means there is nowhere left to look.
  SETD.0 SbfsDiskBlocks
  SETD.2 SbfsCandEnd
  CALL sbfsCompareWord
  BRC sbfsAllocNoRoom   ; The disk is smaller than where this run would end.

  SETD.0 SbfsDirStart
  SETD.1 SbfsBlock
  CALL sbfsCopyWord
  SETD.0 SbfsDirBlocks
  DPUP.0 0d01
  LDA.0
  SETD.1 SbfsLeft
  STA.1

sbfsAllocBlock:
  CALL sbfsReadBlock
  BNQ sbfsAllocFailed
  SETD.1 SbfsBuffer
  CALL sbfsBufferOut
  SETD.2 SbfsBuffer
  INIA 0d8
  SETD.1 SbfsCount
  STA.1

sbfsAllocEntry:
  LDA.2
  INIB 0x01
  AND
  BRQ sbfsAllocNext     ; A free entry holds nothing, so it is in nobody's way.
  CALL sbfsEntryBounds

  ; The comparisons need DP2 for their own purposes, so where this entry is goes on the
  ; Stack for the duration. Working it out again afterwards was the first way this was
  ; written, and it was both longer and wrong.
  PSHD.2

  ; Two runs overlap when each begins before the other ends.
  SETD.0 SbfsCandidate
  SETD.2 SbfsEntryEnd
  CALL sbfsCompareWord
  BNC sbfsAllocClear
  SETD.0 SbfsEntryStart
  SETD.2 SbfsCandEnd
  CALL sbfsCompareWord
  BNC sbfsAllocClear

  ; They do overlap, so try again from the far end of whatever is in the way.
  POPD.2
  SETD.0 SbfsCandidate
  SETD.2 SbfsEntryEnd
  CALL sbfsSetWord
  BRI sbfsAllocTry

sbfsAllocClear:
  POPD.2

sbfsAllocNext:
  DPUP.2 0d32
  SETD.1 SbfsCount
  LDA.1
  DECA
  STA.1
  BNA sbfsAllocEntry

  SETD.0 SbfsBlock
  CALL sbfsStepWord
  SETD.1 SbfsLeft
  LDA.1
  DECA
  STA.1
  BNA sbfsAllocBlock

  ; Nothing was in the way, so this is where it goes.
  SETD.0 SbfsFileStart
  SETD.2 SbfsCandidate
  CALL sbfsSetWord
  RSTA
  RSTB
  CCF
  ADD
  RET

sbfsAllocNoRoom:
sbfsAllocFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; The two byte number at DP0 becomes the one at DP2. Written destination first, so that a
; call reads the way an assignment does. sbfsCopyWord goes the other way, source first,
; which is a difference worth keeping in mind: getting it backwards here quietly destroyed
; a value that had just been worked out.
sbfsSetWord:
  LDA.2
  STA.0
  INCD.2
  INCD.0
  LDA.2
  STA.0
  RET

; The two byte number at DP0 becomes itself less the one at DP2.
sbfsSubWord:
  DPUP.0 0d01
  DPUP.2 0d01
  LDA.0
  LDB.2
  CCF
  SUB
  MVQA
  STA.0
  DPDN.0 0d01
  DPDN.2 0d01
  LDA.0
  LDB.2
  SUB                   ; Borrows in from the low half.
  MVQA
  STA.0
  RET

; How many blocks a file of SbfsFileBlocks and SbfsFileTail actually occupies, into
; SbfsWantBlocks. A file of nothing occupies none.
sbfsFileExtent:
  SETD.0 SbfsWantBlocks
  SETD.2 SbfsFileBlocks
  CALL sbfsSetWord
  SETD.0 SbfsFileTail
  LDA.0
  BRA sbfsExtentDone
  SETD.0 SbfsWantBlocks
  SETD.2 SbfsOne
  CALL sbfsAddWord
sbfsExtentDone:
  RET

; Makes a file. DP0 names it, and SbfsFileBlocks with SbfsFileTail say how big it is,
; which has to be settled before it is made because nothing here can grow one afterwards.
; Q is zero if it was made, and then SbfsFileStart says where its blocks are.
sbfsCreate:
  SETD.1 SbfsWanted
  CALL sbfsKeepName

  CALL sbfsFileExtent
  CALL sbfsAllocate
  BNQ sbfsCreateFailed

  ; Walk the directory for an entry nobody is using.
  SETD.0 SbfsDirStart
  SETD.1 SbfsBlock
  CALL sbfsCopyWord
  SETD.0 SbfsDirBlocks
  DPUP.0 0d01
  LDA.0
  SETD.1 SbfsLeft
  STA.1

sbfsCreateBlock:
  CALL sbfsReadBlock
  BNQ sbfsCreateFailed
  SETD.1 SbfsBuffer
  CALL sbfsBufferOut
  SETD.2 SbfsBuffer
  INIA 0d8
  SETD.1 SbfsCount
  STA.1

sbfsCreateEntry:
  LDA.2
  INIB 0x01
  AND
  BRQ sbfsCreateFill    ; This one is free.
  DPUP.2 0d32
  SETD.1 SbfsCount
  LDA.1
  DECA
  STA.1
  BNA sbfsCreateEntry

  SETD.0 SbfsBlock
  CALL sbfsStepWord
  SETD.1 SbfsLeft
  LDA.1
  DECA
  STA.1
  BNA sbfsCreateBlock

sbfsCreateFull:
  RSTA
  INIB 0d1
  CCF
  ADD                   ; Every entry is taken.
  RET

sbfsCreateFill:
  ; DP2 is on the entry. Fill it in, then put the whole block back on the disk.
  PSHD.2
  POPD.3
  INIA 0x01
  STA.3                 ; In use.

  PSHD.3
  POPD.1
  DPUP.1 0d01
  SETD.0 SbfsFileStart
  CALL sbfsCopyWord

  PSHD.3
  POPD.1
  DPUP.1 0d03
  SETD.0 SbfsFileBlocks
  CALL sbfsCopyWord

  PSHD.3
  POPD.1
  DPUP.1 0d05
  SETD.0 SbfsFileTail
  LDA.0
  STA.1

  PSHD.3
  POPD.1
  DPUP.1 0d06
  SETD.0 SbfsWanted
  INIA 0d22
  SETD.2 SbfsCount
  STA.2
sbfsCreateName:
  LDA.0
  STA.1
  INCD.0
  INCD.1
  LDA.2
  DECA
  STA.2
  BNA sbfsCreateName

  SETD.1 SbfsBuffer
  CALL sbfsBufferIn
  CALL sbfsWriteBlock
  BNQ sbfsCreateFailed

  ; The free count is a note rather than the truth, but it should still be kept right.
  RSTA
  SETD.0 SbfsBlock
  STA.0
  INCD.0
  STA.0
  CALL sbfsReadBlock
  BNQ sbfsCreateFailed
  SETD.1 SbfsBuffer
  CALL sbfsBufferOut
  SETD.0 SbfsBuffer
  DPUP.0 0d12
  SETD.2 SbfsWantBlocks
  CALL sbfsSubWord
  SETD.1 SbfsBuffer
  CALL sbfsBufferIn
  CALL sbfsWriteBlock
  RET

sbfsCreateFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Writes a file that sbfsCreate made, from Data Memory at DP1. Q is zero if it worked.
;
; Whole blocks go out whole, so whatever follows the file in Data Memory ends up in the
; unused tail of its last block. That is harmless, since the tail in the entry says where
; the file stops, but it does mean a block can hold a little of whatever was next to it.
sbfsWriteFile:
  PSHD.1
  POPD.3
  SETD.0 SbfsBlock
  SETD.2 SbfsFileStart
  CALL sbfsSetWord
  CALL sbfsFileExtent
  SETD.0 SbfsWantBlocks
  DPUP.0 0d01
  LDA.0
  SETD.1 SbfsLeft
  STA.1
  BRA sbfsWriteDone     ; A file of nothing has nothing to write.

sbfsWriteLoop:
  PSHD.3
  POPD.1
  CALL sbfsBufferIn
  CALL sbfsWriteBlock
  BNQ sbfsWriteFailed
  DPUP.3 0xFF
  DPUP.3 0x01
  SETD.0 SbfsBlock
  CALL sbfsStepWord
  SETD.0 SbfsLeft
  LDA.0
  DECA
  STA.0
  BNA sbfsWriteLoop

sbfsWriteDone:
  RSTA
  RSTB
  CCF
  ADD
  RET

sbfsWriteFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; Copies a whole block from Data Memory at DP1 into the disk's buffer, which is the other
; way round from sbfsBufferOut.
sbfsBufferIn:
  INIA 0d1
  OUTA 0xE0
  PSHD.1
  POPA
  POPB
  OUTB 0xE1
  OUTA 0xE2
  INIA 0d3
  OUTA 0xE3
  RSTA
  OUTA 0xE4
  OUTA 0xE5
  INIA 0x01
  OUTA 0xE6
  RSTA
  OUTA 0xE7
  INIA 0x01
  OUTA 0xE8
  RET

; Puts the disk's buffer down as the block named by SbfsBlock. Q is zero if it worked.
sbfsWriteBlock:
  SETD.0 SbfsBlock
  LDA.0
  OUTA 0x20
  INCD.0
  LDA.0
  OUTA 0x21
  INIA 0x02
  OUTA 0x22
  INA 0x23
  INIB 0x02
  AND
  RET

; Reads the block named by SbfsBlock into the disk's buffer. Q is zero if it worked.
sbfsReadBlock:
  SETD.0 SbfsBlock
  LDA.0
  OUTA 0x20
  INCD.0
  LDA.0
  OUTA 0x21
  INIA 0x01
  OUTA 0x22
  INA 0x23
  INIB 0x02
  AND                   ; Q is the error bit, so zero means it worked.
  RET

; Copies the disk's buffer, a whole block of it, to Data Memory at DP1.
sbfsBufferOut:
  INIA 0d3
  OUTA 0xE0
  RSTA
  OUTA 0xE1
  OUTA 0xE2
  INIA 0d1
  OUTA 0xE3
  PSHD.1
  POPA
  POPB
  OUTB 0xE4
  OUTA 0xE5
  INIA 0x01
  OUTA 0xE6
  RSTA
  OUTA 0xE7             ; A whole block.
  INIA 0x01
  OUTA 0xE8
  RET

; Two bytes from DP0 to DP1, most significant first, the way every number on a SplitBit
; disk is stored.
sbfsCopyWord:
  LDA.0
  STA.1
  INCD.0
  INCD.1
  LDA.0
  STA.1
  RET

; Adds one to the two byte number at DP0.
sbfsStepWord:
  DPUP.0 0d01
  LDA.0
  INCA
  STA.0
  BNC sbfsStepDone      ; It did not wrap, so the high byte is untouched.
  DPDN.0 0d01
  LDA.0
  INCA
  STA.0
sbfsStepDone:
  RET

; The two byte number at DP0 becomes itself plus the one at DP2. Only memory changes, so
; it survives the return: a routine cannot hand back a pointer or a register.
sbfsAddWord:
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
  ADD                   ; Carries in from the low half. Nothing between the two touches it.
  MVQA
  STA.0
  RET

; Compares the two byte number at DP0 with the one at DP2. Q is zero if they are equal,
; and the Carry Flag is set if the one at DP0 is the smaller. Both come back, because
; neither Q nor the Status register is put back by a return.
sbfsCompareWord:
  LDA.0
  LDB.2
  CCF
  SUB                   ; The high bytes settle it unless they are the same.
  BNQ sbfsCompareDone
  INCD.0
  INCD.2
  LDA.0
  LDB.2
  CCF
  SUB
sbfsCompareDone:
  RET

; The byte at DP0 against the byte at DP2. Q is zero if they are the same.
sbfsSameByte:
  LDA.0
  LDB.2
  XOR
  RET

#Data

SbfsMagic:
"SBFS"

SbfsDirStart:
  0x00 0x00
SbfsDirBlocks:
  0x00 0x00
SbfsFileStart:
  0x00 0x00
SbfsFileBlocks:
  0x00 0x00
SbfsFileTail:
  0x00
SbfsBlock:
  0x00 0x00
SbfsDiskBlocks:
  0x00 0x00
SbfsWantBlocks:
  0x00 0x00
SbfsCandidate:
  0x00 0x00
SbfsCandEnd:
  0x00 0x00
SbfsEntryStart:
  0x00 0x00
SbfsEntryEnd:
  0x00 0x00
SbfsScratch:
  0x00 0x00
SbfsOne:
  0x00 0x01
SbfsCount:
  0x00
SbfsLeft:
  0x00

SbfsWanted:
  #Reserve 0d22

SbfsBuffer:
  #Reserve 0d256
