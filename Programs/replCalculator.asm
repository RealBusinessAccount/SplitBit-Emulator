; Interactive hexadecimal calculator for SplitBit.
;
; Enter expressions as:
;   HH operator HH
; Whitespace is optional. Supported operators are + - * & | and ^.
; Arithmetic wraps to eight bits. Enter Q to quit.

#Include Libraries/print.asm

#Program

start:
  SETD Welcome
  CALL printString

repl:
  SETD Prompt
  CALL printString

  CALL readNonSpace
  PSHQ
  POPA

  ; Q, q, or end-of-file exits.
  INIB 0xFF
  XOR
  BRQ quit
  INIB 0x51
  XOR
  BRQ quit
  INIB 0x71
  XOR
  BRQ quit

  CALL readHexByteFirst
  SETD LeftOperand
  STQ
  CALL parseIsInvalid
  BRQ inputError

  CALL readNonSpace
  PSHQ
  POPA
  SETD Operator
  STA

  CALL readNonSpace
  PSHQ
  POPA
  CALL readHexByteFirst
  SETD RightOperand
  STQ
  CALL parseIsInvalid
  BRQ inputError

  CALL discardLine
  CALL evaluate
  SETD Result
  STQ
  CALL operatorIsInvalid
  BRQ operatorError

  SETD Result
  LDA
  CALL printByteHex
  CALL lineFeed
  BRI repl

inputError:
  CALL discardLine
  SETD BadInput
  CALL printString
  BRI repl

operatorError:
  SETD BadOperator
  CALL printString
  BRI repl

quit:
  SETD Goodbye
  CALL printString
  HALT

; Read a character other than space, tab, CR, or LF. Return it in Q.
readNonSpace:
readNonSpaceLoop:
  INA 0x00
  INIB 0x20
  XOR
  BRQ readNonSpaceLoop
  INIB 0x09
  XOR
  BRQ readNonSpaceLoop
  INIB 0x0A
  XOR
  BRQ readNonSpaceLoop
  INIB 0x0D
  XOR
  BRQ readNonSpaceLoop
  INIB 0x00
  CCF
  ADD
  RET

; A contains the first hexadecimal digit. Read the second and return the byte
; in Q. Q is 0xFF on malformed input.
readHexByteFirst:
  CALL clearParseStatus
  CALL hexNibble
  PSHQ
  POPA
  INIB 0xFF
  XOR
  BRQ invalidByte
  INIB 0x00
  SHL
  SHL
  SHL
  SHL
  PSHA

  CALL readNonSpace
  PSHQ
  POPA
  CALL hexNibble
  PSHQ
  POPA
  INIB 0xFF
  XOR
  BRQ invalidLowNibble
  POPB
  OR
  RET

invalidLowNibble:
  POPB
invalidByte:
  PSHD
  SETD ParseStatus
  INIA 0x01
  STA
  POPD
  INIA 0xFF
  INIB 0x00
  CCF
  ADD
  RET

; Convert the ASCII hexadecimal digit in A to a value in Q.
; Uppercase and lowercase letters are accepted. Q=0xFF means invalid.
hexNibble:
  PSHA

  ; Try 0 through 9.
  INIB 0x30
  CCF
  SUB
  BRC tryUpperHex
  PSHQ
  POPA
  INIB 0d10
  CCF
  SUB
  BRC decimalNibble

tryUpperHex:
  POPA
  PSHA
  INIB 0x41
  CCF
  SUB
  BRC tryLowerHex
  PSHQ
  POPA
  INIB 0d06
  CCF
  SUB
  BRC upperNibble

tryLowerHex:
  POPA
  PSHA
  INIB 0x61
  CCF
  SUB
  BRC badNibble
  PSHQ
  POPA
  INIB 0d06
  CCF
  SUB
  BRC lowerNibble

badNibble:
  POPA
  INIA 0xFF
  INIB 0x00
  CCF
  ADD
  RET

decimalNibble:
  POPB
  INIB 0x00
  CCF
  ADD
  RET

upperNibble:
  POPB
  INIB 0d10
  CCF
  ADD
  RET

lowerNibble:
  POPB
  INIB 0d10
  CCF
  ADD
  RET

; Return Q=0 if Q was 0xFF, otherwise return a nonzero value.
resultIsInvalid:
  PSHQ
  POPA
  INIB 0xFF
  XOR
  RET

clearParseStatus:
  PSHD
  SETD ParseStatus
  RSTA
  STA
  POPD
  RET

parseIsInvalid:
  PSHD
  SETD ParseStatus
  LDA
  INIB 0x01
  XOR
  POPD
  RET

operatorIsInvalid:
  PSHD
  SETD OperatorStatus
  LDA
  INIB 0x01
  XOR
  POPD
  RET

; Evaluate the stored expression and return its result in Q.
evaluate:
  PSHD
  SETD OperatorStatus
  RSTA
  STA
  POPD
  SETD Operator
  LDA

  INIB 0x2B
  XOR
  BRQ evaluateAdd
  INIB 0x2D
  XOR
  BRQ evaluateSubtract
  INIB 0x2A
  XOR
  BRQ evaluateMultiply
  INIB 0x26
  XOR
  BRQ evaluateAnd
  INIB 0x7C
  XOR
  BRQ evaluateOr
  INIB 0x5E
  XOR
  BRQ evaluateXor

  SETD OperatorStatus
  INIA 0x01
  STA
  RSTA
  INIB 0x00
  CCF
  ADD
  RET

evaluateAdd:
  SETD LeftOperand
  LDA
  INCD
  LDB
  CCF
  ADD
  RET

evaluateSubtract:
  SETD LeftOperand
  LDA
  INCD
  LDB
  CCF
  SUB
  RET

evaluateAnd:
  SETD LeftOperand
  LDA
  INCD
  LDB
  AND
  RET

evaluateOr:
  SETD LeftOperand
  LDA
  INCD
  LDB
  OR
  RET

evaluateXor:
  SETD LeftOperand
  LDA
  INCD
  LDB
  XOR
  RET

evaluateMultiply:
  RSTA
  SETD Product
  STA

multiplyLoop:
  SETD RightOperand
  LDA
  BRA multiplyDone
  DECA
  STA

  SETD Product
  LDA
  SETD LeftOperand
  LDB
  CCF
  ADD
  SETD Product
  STQ
  BRI multiplyLoop

multiplyDone:
  SETD Product
  LDA
  INIB 0x00
  CCF
  ADD
  RET

; Consume the rest of the current input line.
discardLine:
discardLoop:
  INA 0x00
  INIB 0x0A
  XOR
  BRQ discardDone
  INIB 0xFF
  XOR
  BRQ discardDone
  BRI discardLoop
discardDone:
  RET

#Data

LeftOperand:
  0x00
RightOperand:
  0x00
Operator:
  0x00
Product:
  0x00
Result:
  0x00
ParseStatus:
  0x00
OperatorStatus:
  0x00

Welcome:
  "SplitBit calculator (+ - * & | ^), Q quits."
Prompt:
  0x0A
  "> "
BadInput:
  "Invalid hexadecimal input."
BadOperator:
  "Unknown operator."
Goodbye:
  "Goodbye!"
  0x0A
