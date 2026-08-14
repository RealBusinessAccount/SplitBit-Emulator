; Copies a string from one place in Data Memory to another, reading through DP0
; and writing through DP1 at the same time.
;
; On a machine with one Data Pointer this loop needs a PSHD and a POPD on every
; pass to swap the pointer between the two regions. With two pointers it is just
; a load and a store.
;
; It also checks that a bare mnemonic still means DP0.

#Program

start:
  SETD.0 Source     ; DP0 walks the source.
  SETD.1 Dest       ; DP1 walks the destination.

copy:
  LDA.0             ; Read a byte through DP0.
  BRA copyDone      ; A zero byte is the end of the string.
  STA.1             ; Write it through DP1.
  INCD.0
  INCD.1
  BRI copy

copyDone:
  SETD Dest         ; No selector, so this is DP0.
print:
  LDA
  BRA end
  OUTA 0x00
  INCD
  BRI print

end:
  INIA 0x0A
  OUTA 0x00
  HALT

#Data

Source:
"Two pointers, no stack shenanigans."

Dest:
0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
