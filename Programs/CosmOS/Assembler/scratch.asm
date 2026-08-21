; Where the assembler's big buffers live.
;
; A map rather than a set of declarations, and it has a file of its own because the reader
; and the label table both need addresses out of it while neither includes the other.
;
#Data

; NOT #Reserve, AND THAT IS THE WHOLE POINT. Reserved space in a segment is written into
; the file as zeroes and copied at load, so 22K of scratch made a 34K file - and a loaded
; program is staged at 0x8000 before being put in place, which leaves exactly 32,768 bytes
; for the whole of it. The assembler could not load itself.
;
; None of this is initialised data. It is scratch, wanted only while the assembler is
; running, and while it is running everything above its own data is free: the system keeps
; below 0x1000, the staging area is only in use during a load, and the Stack comes down
; from the top. So the addresses are written down here and the file carries none of it.
;
;   0x8000  3072   the label index, 768 entries of four
;   0x8C00  8192   the label names, packed end to end
;   0xAC00 13312   the output file being built
;   0xE000  1792   the vector names, 64 entries of twenty eight
;   0xE700  1758   the reader's stack, six levels of 293
;   0xEE00   368   which files have been included, sixteen names of 23
;
; That ends at 0xEF70, with the Stack coming down from 0xFFFF above it - about four
; kilobytes, against the tens of bytes of CALL frames this ever nests.
;
; THE TWO THINGS THAT DECIDE THESE SIZES are the largest program it will be asked to build
; and the largest one it will be asked to read. CosmOS is 475 labels and 9,564 bytes of
; output; the assembler itself is 555 labels, about 6,800 bytes of name and 11,648 of output. The
; second is bigger than the first, which is worth knowing: the hardest thing this assembles
; is not the operating system, it is itself.
ScratchLabIndex:
  0x80 0x00
ScratchLabArena:
  0x8C 0x00
ScratchImage:
  0xAC 0x00
ScratchVecNames:
  0xE0 0x00
ScratchSrcStack:
  0xE7 0x00
ScratchIncNames:
  0xEE 0x00
