# MOS 6502 CPU Implementation

## Overview

A cycle-accurate implementation of the MOS Technology 6502 microprocessor, the CPU used in the original NES. The design is split into three modules:

- **`MOS_6502_CPU.v`** - Top-level wrapper and address generation
- **`cpu_fsm.v`** - Main execution finite state machine
- **`cpu_decoder.v`** - Combinational opcode decoder

## Module Hierarchy

```
MOS_6502_CPU (Top)
├── cpu_fsm          (FSM + register file)
│   ├── 58+ states
│   ├── ALU (combinational)
│   ├── Register file: A, X, Y, S, SR, PC
│   └── NMI/IRQ edge detectors
└── cpu_decoder      (Combinational)
    ├── Addressing mode decode
    ├── ALU operation decode
    └── Destination register decode
```

## Opcode Decoder (`cpu_decoder.v`)

A purely combinational module that decodes the 8-bit instruction register into control signals:

| Output | Width | Description |
|--------|-------|-------------|
| `addr_mode` | 4 | One of 13 addressing modes |
| `alu_op` | 4 | ALU operation to perform |
| `dest_reg` | 2 | Destination register (A, X, Y, or none) |
| `extra_cycles` | 2 | Number of operand fetch cycles needed |

### Supported Instructions

**Load/Store**: LDA, LDX, LDY, STA, STX, STY  
**Arithmetic**: ADC, SBC, INC, DEC  
**Logic**: AND, ORA, EOR, BIT  
**Shifts**: ASL, LSR, ROL, ROR  
**Branches**: BCC, BCS, BEQ, BNE, BMI, BPL, BVC, BVS  
**Jumps**: JMP (absolute & indirect), JSR, RTS  
**Stack**: PHA, PHP, PLA, PLP  
**Transfers**: TAX, TAY, TXA, TYA, TSX, TXS  
**Flags**: CLC, SEC, CLI, SEI, CLD, SED, CLV  
**Other**: NOP, BRK, RTI, CMP, CPX, CPY  

### Addressing Modes

| Mode | Value | Description |
|------|-------|-------------|
| Implicit | 0 | No operand (e.g., NOP, CLC) |
| Immediate | 1 | Operand follows opcode |
| Zero Page | 2 | 8-bit address ($00-$FF) |
| Absolute | 3 | 16-bit address |
| Zero Page,X | 4 | ZP + X register |
| Absolute,X | 5 | Absolute + X |
| Absolute,Y | 6 | Absolute + Y |
| (Indirect,X) | 7 | Pre-indexed indirect |
| (Indirect),Y | 8 | Post-indexed indirect |
| Accumulator | 9 | Operand is accumulator |
| Relative | 10 | Branch offset |
| Zero Page,Y | 11 | ZP + Y |
| Indirect Abs | 12 | JMP indirect |

## FSM Execution (`cpu_fsm.v`)

The FSM implements the 6502 bus cycle model with 58+ states. The key pipeline stages are:

```
S_FETCH ──▶ S_OPERAND_LO ──▶ S_OPERAND_HI ──▶ S_EXECUTE ──▶ S_WRITEBACK ──▶ S_FETCH
   0             5                  6               3              4
```

### Key State Transitions

| State | Description |
|-------|-------------|
| `S_FETCH (0)` | Fetch opcode from PC, increment PC. Check for NMI/IRQ |
| `S_OPERAND_LO (5)` | Fetch low byte of operand |
| `S_OPERAND_HI (6)` | Fetch high byte (for absolute/indirect modes) |
| `S_EXECUTE (3)` | Execute ALU operation or initiate multi-cycle flow |
| `S_WRITEBACK (4)` | Write ALU result back to destination (memory-sourced ops) |
| `S_PTR_LO/HI (9,11)` | Fetch indirect pointer for (indirect),Y / (indirect,X) |
| `S_INDIRECT_EXEC (13)` | Execute after indirect pointer resolution |
| `S_RMW_READ/WRITE (20,21)` | Read-Modify-Write: read memory, modify, write back |
| `S_RESET_VEC_LO/HI (26,28)` | Read reset vector from $FFFC-$FFFD |
| `S_BRK_PUSH_* (50-52)` | BRK: push PCH, PCL, SR to stack |
| `S_BRK_VEC_LO/HI (54,56)` | BRK: read IRQ vector from $FFFE-$FFFF |
| `S_JSR_PUSH_* (31,32)` | JSR: push return address minus 1 |
| `S_RTS_PULL_* (35,37,39)` | RTS: pull return address, increment |
| `S_JMP_IND_LO/HI (41,43)` | JMP indirect: 16-bit pointer fetch |
| `S_RTI_PULL_* (45,47,49)` | RTI: pull SR, PCL, PCH |

### Reset Sequence

1. Reset sets state to `S_RESET_VEC_LO`
2. Reads vector at $FFFC → low byte of PC
3. Transitions to `S_RESET_VEC_HI`
4. Reads vector at $FFFD → high byte of PC
5. Begins fetch at the reset vector address

### NMI/IRQ Handling

The FSM implements edge-triggered NMI and level-sensitive IRQ:

- **NMI**: Latched on rising edge, serviced after current instruction completes
- **IRQ**: Sampled at fetch, serviced if I flag (bit 2 of SR) is clear
- Both push PC and SR to stack (same as BRK), then read their respective vectors
- NMI vector: $FFFA-$FFFB; IRQ/BRK vector: $FFFE-$FFFF

### ALU Operations

The ALU is implemented as combinational logic within the FSM, supporting:

| ALU Op | Value | Operation |
|--------|-------|-----------|
| PASS | 0 | Pass-through (LDA, LDX, etc.) |
| ADD | 1 | Add with carry (ADC) |
| SUB | 2 | Subtract with borrow (SBC) |
| AND | 3 | Bitwise AND |
| ASL | 4 | Arithmetic shift left |
| BIT | 5 | Bit test |
| CMP | 6 | Compare (subtract, flags only) |
| INC | 7 | Increment by 1 |
| DEC | 8 | Decrement by 1 |
| ORA | 9 | Bitwise OR |
| EOR | 10 | Bitwise XOR |
| LSR | 11 | Logical shift right |
| ROL | 12 | Rotate left through carry |
| ROR | 13 | Rotate right through carry |

### Overflow Calculation

```verilog
function calc_v_add;
    input [7:0] a, b, result;
    calc_v_add = (~(a[7] ^ b[7])) & (a[7] ^ result[7]);
endfunction

function calc_v_sub;
    input [7:0] a, b, result;
    calc_v_sub = (a[7] ^ b[7]) & (a[7] ^ result[7]);
endfunction
```

### Architecture Notes

- **Single-byte opcodes** (implicit/accumulator): Skip operand fetch entirely, go straight to `S_EXECUTE`
- **Store instructions**: Identified by opcode, write register content to effective address
- **Branch instructions**: Use relative addressing, evaluate condition from status register
- **Indirect addressing**: Two-stage pointer fetch before executing (X + 1 cycle overhead vs. Y)
- **BRK vs IRQ distinction**: BRK sets SR push bits differently (B flag = 1), IRQ does not
- **Stack pointer**: Initialized to $FD during reset, decrements before push
