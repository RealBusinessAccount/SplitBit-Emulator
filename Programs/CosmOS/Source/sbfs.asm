; sbfs.asm
; Reading the SplitBit Filesystem.
;
; This belongs to CosmOS, which is the thing that needs it. Programs outside CosmOS may
; include it, and the test programs do, but when CosmOS becomes a repository of its own
; this file goes with it and anything left behind takes a copy.
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

; ---- Walking the directory ----
;
; sbfsFind answers a question about one name. Listing what is on a disk is a different
; job: it needs the directory walked rather than searched. sbfsFirst starts a walk and
; sbfsNext steps it, and each of them stops on an entry that is in use, skipping the free
; ones on the way past.
;
; Q is zero while there is an entry to look at. When it is, SbfsName holds the name with
; a zero byte after it, and SbfsFileStart, SbfsFileBlocks and SbfsFileTail describe the
; file exactly the way sbfsFind leaves them. Q is something else when the directory is
; finished, and also when a block could not be read, which are the same answer to the
; question "is there another one" and different answers to "why not".
;
; A walk keeps a directory block in SbfsBuffer between calls, so anything else that goes
; to the disk in the middle of one ends it. Take what is wanted out of an entry before
; asking the disk for anything else.

sbfsFirst:
  SETD.0 SbfsDirStart
  SETD.1 SbfsWalkBlock
  CALL sbfsCopyWord
  SETD.0 SbfsDirBlocks
  DPUP.0 0d01
  LDA.0
  SETD.1 SbfsWalkLeft
  STA.1                 ; Only the low byte, the same as sbfsFind.

  ; Nothing is loaded yet. Saying the block in hand is empty makes the scan fetch the
  ; first one, so there is one way into a block rather than two.
  RSTA
  SETD.0 SbfsWalkCount
  STA.0
  BRI sbfsWalkScan

sbfsNext:
  ; The pointer and the count were stepped when the last entry was handed out, so there
  ; is nothing to do here but carry on looking.
  BRI sbfsWalkScan

sbfsWalkScan:
  ; Anything left in the block in hand?
  SETD.0 SbfsWalkCount
  LDA.0
  BNA sbfsWalkEntry

  ; No. Take the next directory block, if the directory has one.
  SETD.0 SbfsWalkLeft
  LDA.0
  BRA sbfsWalkEnd
  DECA
  STA.0

  SETD.0 SbfsWalkBlock
  SETD.1 SbfsBlock
  CALL sbfsCopyWord
  CALL sbfsReadBlock
  BRQ sbfsWalkLoaded
  RET                   ; The read failed, and Q says so.
sbfsWalkLoaded:
  SETD.1 SbfsBuffer
  CALL sbfsBufferOut

  ; That one is in hand now, so the walk's block number moves on to the following one.
  SETD.0 SbfsWalkBlock
  CALL sbfsStepWord

  ; Eight entries to a block, starting at the top of the buffer.
  SETD.0 SbfsBuffer
  SETD.1 SbfsWalkPointer
  STD.0.1
  INIA 0d8
  SETD.0 SbfsWalkCount
  STA.0
  BRI sbfsWalkScan

sbfsWalkEntry:
  ; Where this entry is. Kept in memory rather than in DP3, so that a walk does not
  ; quietly take the one pointer a caller can carry things across a call in.
  SETD.1 SbfsWalkPointer
  LDD.2.1
  SETD.1 SbfsWalkAt
  STD.2.1

  ; Step past it now, so that the walk has moved on whether this one is taken or skipped.
  ; Getting that wrong in only one of the two paths is how a walk repeats an entry
  ; forever, and it repeats the interesting ones rather than the boring ones.
  SETD.0 SbfsWalkCount
  LDA.0
  DECA
  STA.0
  PSHD.2
  POPD.0
  DPUP.0 0d32
  SETD.1 SbfsWalkPointer
  STD.0.1

  ; Is it a file? A free entry is not one, and there can be free entries in the middle of
  ; a directory, so this is a skip rather than a stop.
  LDA.2
  INIB 0x01
  AND
  BRQ sbfsWalkScan

  CALL sbfsWalkTake
  RSTA
  RSTB
  CCF
  ADD                   ; Q is zero: here is an entry.
  RET

sbfsWalkEnd:
  RSTA
  INIB 0d1
  CCF
  ADD                   ; Q is one: the directory is finished.
  RET

; Takes the pieces out of the entry the walk stopped on. Everything lands in memory,
; because that is the only place a subroutine can leave anything.
sbfsWalkTake:
  SETD.1 SbfsWalkAt
  LDD.0.1
  DPUP.0 0d01
  SETD.1 SbfsFileStart
  CALL sbfsCopyWord

  SETD.1 SbfsWalkAt
  LDD.0.1
  DPUP.0 0d03
  SETD.1 SbfsFileBlocks
  CALL sbfsCopyWord

  SETD.1 SbfsWalkAt
  LDD.0.1
  DPUP.0 0d05
  LDA.0
  SETD.1 SbfsFileTail
  STA.1

  ; The name. Twenty two bytes of it, padded with zeroes rather than terminated, so it is
  ; copied into a buffer with a twenty third byte that nothing ever writes. That byte is
  ; what makes a name that fills the field into a string that can be printed.
  SETD.1 SbfsWalkAt
  LDD.0.1
  DPUP.0 0d06
  SETD.1 SbfsName
  INIA 0d22
  SETD.2 SbfsCount
  STA.2
sbfsWalkName:
  LDA.0
  STA.1
  INCD.0
  INCD.1
  SETD.2 SbfsCount
  LDA.2
  DECA
  STA.2
  BNA sbfsWalkName
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

; ---- Deleting ----
;
; Frees a file. DP0 names it, and Q is zero if it went.
;
; A deleted entry and one that was never used are the same thing, which is the whole of
; what deleting is here: the entry is zeroed and its blocks stop being spoken for. THE
; BLOCKS THEMSELVES ARE LEFT EXACTLY AS THEY WERE, so what was in a file is still on the
; disk until something is put over the top of it. Worth knowing if anything is ever meant
; to be private. The host tool does the same, so the two agree about what a deleted disk
; looks like.
;
; Nothing is compacted. Deleting leaves a hole, and because files are contiguous a hole is
; only usable by something that fits inside it. That is the price of the directory being
; the whole allocation map, and tidying it up is an ordinary program somebody can write
; rather than anything the format has to say.
sbfsDelete:
  CALL sbfsFind
  BNQ sbfsDeleteFailed

  ; How much room it was taking, worked out before the entry that says so is thrown away.
  CALL sbfsFileExtent

  ; sbfsFind leaves DP3 on the entry and SbfsBlock on the directory block it came out of,
  ; which is everything needed to change it and put it back.
  PSHD.3
  POPD.0
  INIB 0d32
sbfsDeleteWipe:
  RSTA
  STA.0
  INCD.0
  DECB
  BNB sbfsDeleteWipe

  SETD.1 SbfsBuffer
  CALL sbfsBufferIn
  CALL sbfsWriteBlock
  BNQ sbfsDeleteFailed

  ; And the free count goes back up. It is a note rather than the truth, but a note worth
  ; keeping right.
  RSTA
  SETD.0 SbfsBlock
  STA.0
  INCD.0
  STA.0
  CALL sbfsReadBlock
  BNQ sbfsDeleteFailed
  SETD.1 SbfsBuffer
  CALL sbfsBufferOut
  SETD.0 SbfsBuffer
  DPUP.0 0d12
  SETD.2 SbfsWantBlocks
  CALL sbfsAddWord
  SETD.1 SbfsBuffer
  CALL sbfsBufferIn
  CALL sbfsWriteBlock
  RET

sbfsDeleteFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; ---- Renaming ----
;
; DP0 is the name a file has, DP1 is the name it should have. Q is zero if it was renamed.
;
; Only the twenty two bytes of the name change, so no data moves and no block is touched
; but the one holding the entry. THAT IS WHAT MAKES A SAFE SAVE POSSIBLE. Writing a file
; that has grown means putting it somewhere else, and the obvious order - throw the old one
; away, then write the new one - loses the lot if there turns out to be nowhere to put it.
; Renaming is the cheapest thing this filesystem can do and the only one that can be left
; until last, so it is what the order is built around.
sbfsRename:
  ; Where the old name is, kept somewhere that finding things will not tread on.
  SETD.2 SbfsSavedName
  STD.0.2

  PSHD.1
  POPD.0
  SETD.1 SbfsNewName
  CALL sbfsKeepName     ; Twenty two bytes, padded, the way an entry holds one.

  ; Refused if something already answers to the new name. Two entries with one name is a
  ; disk that cannot be searched sensibly: a search answers with whichever it meets first,
  ; so the other becomes unreachable without ever having been deleted.
  SETD.0 SbfsNewName
  CALL sbfsFind
  BRQ sbfsRenameFailed

  SETD.2 SbfsSavedName
  LDD.0.2
  CALL sbfsFind
  BNQ sbfsRenameFailed

  PSHD.3
  POPD.1
  DPUP.1 0d06           ; Past the flags, the start, the block count and the tail.
  SETD.0 SbfsNewName
  INIA 0d22
  SETD.2 SbfsCount
  STA.2
sbfsRenameName:
  LDA.0
  STA.1
  INCD.0
  INCD.1
  LDA.2
  DECA
  STA.2
  BNA sbfsRenameName

  SETD.1 SbfsBuffer
  CALL sbfsBufferIn
  CALL sbfsWriteBlock
  RET

sbfsRenameFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
  RET

; ---- Saving over something that is already there ----
;
; DP0 names the file, DP1 is the data, and SbfsFileBlocks with SbfsFileTail say how big it
; now is. Q is zero if it was saved.
;
; This is the routine every tool that edits a document wants, and the reason it is here
; rather than in each of them is that the careful order is not obvious and getting it wrong
; destroys somebody's work:
;
;   make a temporary        nothing is lost if there is nowhere to put it
;   write it
;   delete the original     only once the new one is safely down
;   rename the temporary
;
; The obvious order - delete, create, write - looks fine and is a trap. Files here are
; contiguous, so a file that has grown may not fit where it was, and a create can be
; refused for want of a run long enough even on a disk with plenty of free blocks. Do it
; that way round and the original is already gone when that happens.
sbfsSaveFile:
  SETD.2 SbfsSaveName
  STD.0.2
  SETD.2 SbfsSaveData
  STD.1.2

  ; How big it is, kept aside: finding and deleting things both overwrite the place the
  ; size is normally said, because both of them describe whatever they last looked at.
  SETD.0 SbfsSaveBlocks
  SETD.2 SbfsFileBlocks
  CALL sbfsSetWord
  SETD.0 SbfsFileTail
  LDA.0
  SETD.1 SbfsSaveTail
  STA.1

  ; A temporary left behind by a save that did not finish would be in the way. Whether
  ; there was one is not worth asking about, since either answer leads here.
  SETD.0 SbfsTempName
  CALL sbfsDelete

  SETD.0 SbfsFileBlocks
  SETD.2 SbfsSaveBlocks
  CALL sbfsSetWord
  SETD.0 SbfsSaveTail
  LDA.0
  SETD.1 SbfsFileTail
  STA.1

  SETD.0 SbfsTempName
  CALL sbfsCreate
  BNQ sbfsSaveFailed

  SETD.2 SbfsSaveData
  LDD.1.2
  CALL sbfsWriteFile
  BNQ sbfsSaveFailed

  ; Now, and not before, the old one goes. It may not exist, which is what saving something
  ; for the first time looks like from here.
  SETD.2 SbfsSaveName
  LDD.0.2
  CALL sbfsDelete

  SETD.0 SbfsTempName
  SETD.2 SbfsSaveName
  LDD.1.2
  CALL sbfsRename
  RET

sbfsSaveFailed:
  RSTA
  INIB 0d1
  CCF
  ADD
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

; ---- What a walk through the directory keeps between calls ----

SbfsWalkBlock:
  0x00 0x00
SbfsWalkLeft:
  0x00
SbfsWalkCount:
  0x00
SbfsWalkPointer:
  0x00 0x00
SbfsWalkAt:
  0x00 0x00

; Twenty three bytes for a name of twenty two, so that the last one is a zero nothing
; ever writes over and the name is always a string.
SbfsName:
  #Reserve 0d23

SbfsWanted:
  #Reserve 0d22

; ---- What renaming and saving keep ----

; A name on its way into an entry, padded to the twenty two bytes an entry holds.
SbfsNewName:
  #Reserve 0d22

; Where a name lives, kept across a search, which needs the pointers for itself.
SbfsSavedName:
  0x00 0x00

SbfsSaveName:
  0x00 0x00
SbfsSaveData:
  0x00 0x00
SbfsSaveBlocks:
  0x00 0x00
SbfsSaveTail:
  0x00

; What a document is called while it is being written and is not yet the real thing. A
; name nothing else is likely to want, and short enough to leave room for a long one.
SbfsTempName:
"sbfs.part"

SbfsBuffer:
  #Reserve 0d256
