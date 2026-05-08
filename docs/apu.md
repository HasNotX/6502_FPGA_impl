# Audio Processing Unit (APU)

## Overview

The APU is derived from Ludvig Strigaeus's open-source FPGA NES implementation (GPL licensed). It implements all five NES audio channels and outputs via the WM8731 audio codec on the DE10-Lite board.

## Module Hierarchy

```
APU / nes_apu
├── SquareChan (SQ1)       ─── Pulse wave with sweep
├── SquareChan (SQ2)       ─── Pulse wave with sweep  
├── TriangleChan (TRI)     ─── Triangle wave
├── NoiseChan (NOI)        ─── Pseudo-random noise
├── DmcChan (DMC)          ─── Delta Modulation Channel (DPCM samples)
├── LenCtr_Lookup          ─── Length counter lookup table
└── ApuLookupTable         ─── Mixer lookup table (non-linear mixing)

SoundDriver
└── WM8731 Audio Codec Interface
    └── I2C_AV_Config / I2C_Controller  (I2C bus configuration)
```

## Audio Channels

### Square Channels (SQ1, SQ2)

Two configurable pulse wave channels with:

- **Duty cycle**: Selectable 12.5%, 25%, 50%, 75% (75% is inverted 25%)
- **Envelope**: Volume envelope with looping/decay control
- **Sweep unit**: Frequency sweep with period, direction, and shift control
- **Length counter**: Automatic note duration timer
- **Frequency**: 11-bit period register

The sweep unit calculates new frequency:
```verilog
wire [10:0] ShiftedPeriod = (Period >> SweepShift);
wire [10:0] PeriodRhs = SweepNegate ? (~ShiftedPeriod) : ShiftedPeriod;
wire [11:0] NewSweepPeriod = Period + PeriodRhs;
```

### Triangle Channel (TRI)

A fixed-amplitude triangle wave with:
- **Linear counter**: Controlled by a 7-bit reload value
- **Length counter**: Standard length counter
- **Sequencer**: 5-bit counter generating 32-step triangle wave
- **No sweep unit**: Unlike square channels

### Noise Channel (NOI)

Pseudo-random noise generator with:
- **LFSR**: 15-bit shift register with configurable feedback tap (bit 1 or bit 6)
- **16 prescaler rates**: From 4 to 4,084 CPU cycles
- **Envelope**: Same envelope generator as square channels
- **Short/ long mode**: Selects between two different LFSR feedback configurations

```verilog
Shift <= {Shift[0] ^ (ShortMode ? Shift[6] : Shift[1]), Shift[14:1]};
```

### DMC Channel (DMC)

Delta Modulation Channel for DPCM samples:
- **DMA interface**: Requests bus control to read sample data from memory
- **16 frequency rates**: From 54 to 428 CPU cycles per output bit
- **1-bit DAC**: Steps output up/down based on sample bits
- **IRQ**: Generates interrupt when sample completes
- **Looping**: Supports one-shot and looping samples

## Frame Sequencer

The frame sequencer generates the envelope (ClkE) and length counter (ClkL) clock signals:

| Mode | Steps | Rates |
|------|-------|-------|
| 4-step (mode 0) | 29829 CPU cycles | ClkE at ~240 Hz, ClkL at ~120 Hz, IRQ at ~60 Hz |
| 5-step (mode 1) | 37282 CPU cycles | ClkE at ~192 Hz, ClkL at ~96 Hz, no IRQ |

Sequencer tick points:
- Cycle 7457: ClkE
- Cycle 14913: ClkE+ClkL
- Cycle 22371: ClkE
- Cycle 29829: ClkE+ClkL + IRQ (mode 0) or continue (mode 1)
- Cycle 37281: ClkE+ClkL, reset (mode 1 only)

## Audio Mixing

Channel outputs are combined using a non-linear mixing lookup table (ApuLookupTable) that approximates the original NES analog mixing:

```verilog
ApuLookupTable lookup(clk, 
    // SQ1 + SQ2
    (audio_channels[0] ? Sq1Sample : 0) + (audio_channels[1] ? Sq2Sample : 0),
    // TRI (×1.5 for extra gain) + NOI (×2 for gain) + DMC
    (audio_channels[2] ? TriSample*1.5 : 0) + 
    (audio_channels[3] ? NoiSample*2 : 0) +
    (audio_channels[4] ? DmcSample : 0),
    Sample);
```

The lookup table maps 8-bit combined values to 16-bit linear output samples (0-65535).

## APU Registers

| Address | Register | Description |
|---------|----------|-------------|
| $4000-$4003 | SQ1_VOL/SWEEP/LO/HI | Square 1 control registers |
| $4004-$4007 | SQ2_VOL/SWEEP/LO/HI | Square 2 control registers |
| $4008-$400B | TRI_LINEAR/LO/HI | Triangle control registers |
| $400C-$400F | NOI_VOL/LO/HI | Noise control registers |
| $4010-$4013 | DMC_CTRL/DAC/ADDR/LEN | DMC control registers |
| $4015 | APU_STATUS | Read: channel status; Write: channel enables |
| $4017 | APU_FRAME | Frame sequencer control |

## Audio Output Path

```
APU (digital, CPU clock domain)
    │
    ▼
16-bit sample (unsigned, 0-65535)
    │
    ▼
DC offset removal: sample - 16'h8000  (→ signed)
    │
    ▼
SoundDriver (WM8731 via I2S)
    │
    ├── AUD_MCLK  (12.5 MHz master clock)
    ├── AUD_SCK   (~1.5 MHz serial clock)  
    ├── AUD_LRCK  (~32 kHz left/right frame clock)
    └── AUD_SDIN  (serial data, 24-bit I2S format)
    │
    ▼
WM8731 Audio DAC → 3.5mm audio jack
```

The WM8731 is configured via I2C at boot with 51 configuration registers (audio path, sample rate, power management, volume control).
