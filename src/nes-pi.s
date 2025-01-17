; nes-pi.s - An NES game that computes the digits of pi.
; By NesHacker

;-------------------------------------------------------------------------------
;                                 Memory Map
;-------------------------------------------------------------------------------
; $00-$1F:      Pi-Spigot Compute / Scratch
;               Memory in this range is used by the Pi-Spigot routine as a
;               scratch pad when computing digits. As such, it should be left
;               alone when the routine is running.
;-------------------------------------------------------------------------------
; $20-$2F       General CPU Scratch
;               Scratch pad for general CPU tasks, e.g. game states, controller
;               input, etc.
;-------------------------------------------------------------------------------
; $30-$3F       NMI/Rendering Scratch
;               Scratch pad for PPU and rendering related tasks. Keeping this
;               Separate ensures that CPU memory isn't corrupted mid-computer
;               when the NMI fires.
;-------------------------------------------------------------------------------
; $40-$5F       Game State
;               Long term variables used for handling the overall game logic.
;-------------------------------------------------------------------------------
; $60-$7F       Rendering
;               Long term variables used for handling rendering routines.
;-------------------------------------------------------------------------------
; $80-$AF       Pi-Spigot State
;               Pi-spigot algorithm variables. For ease of debugging I chose to
;               group like sized variables together. $80-$8F holds all 8-bit
;               values, $90-$9F all 16-bit values, and $A0-$AF all pointers.
;-------------------------------------------------------------------------------
; $B0-$FF       Unassigned
;-------------------------------------------------------------------------------
; $100-$1FF     Stack
;-------------------------------------------------------------------------------
; $200-$2FF     OAM Sprite Memory
;               Holds the OAM sprite entires that are copied to VRAM each frame.
;-------------------------------------------------------------------------------
; $300-$700     Pi Digits
;               Each byte in this memory region stores a single digit of pi, as
;               computed by the Pi-Spigot routine.
;-------------------------------------------------------------------------------
; $700-$7FF     Unassigned
;-------------------------------------------------------------------------------
; $6000-$78FF   Pi-Spigot Compute Table
;               Holds a table of 16-bit entries used by the Pi-Spigot algorithm
;               to compute the digits of pi. This table is the main ledger used
;               by the algorithm and, as such, should be considered completely
;               off-limits to the rest of the program.
;-------------------------------------------------------------------------------

.scope Game
  FRAME_FLAG = %10000000
  state = $40
  flags = $41
.endscope

.macro SetGameFlag mask
  lda #mask
  ora Game::flags
  sta Game::flags
.endmacro

.macro ClearGameFlag mask
  lda #mask
  eor Game::flags
  sta Game::flags
.endmacro

.enum GameState
  pretitle      = 0
  title         = 1
  digit_select  = 2
  calculate     = 3
.endenum

.macro SetGameState value
.scope
  lda value
  sta Game::state
  DisableRendering
  jsr executeInitHandler
@vblank_wait:
  bit PPU_STATUS
  bpl @vblank_wait
  EnableRendering
.endscope
.endmacro

.include "lib/bcd.s"
.include "lib/ppu.s"
.include "lib/draw.s"
.include "lib/joypad.s"
.include "lib/math.s"
.include "lib/mmc1.s"

.include "pi_spigot.s"

.include "state/pretitle.s"
.include "state/title.s"
.include "state/digit_select.s"

.segment "HEADER"
  .byte $4E, $45, $53, $1A  ; iNES header identifier
  .byte 2                   ; 2x 16KB PRG-ROM Banks
  .byte 1                   ; 1x  8KB CHR-ROM
  .byte $10                 ; mapper 1 (MMC1)
  .byte $00                 ; System: NES

.segment "VECTORS"
  .addr nmi
  .addr reset
  .addr 0

.segment "STARTUP"

.segment "CHARS"
.incbin "./src/bin/CHR-ROM.bin"

.segment "CODE"

.proc reset
  sei
  cld
  ldx #%01000000
  stx $4017
  ldx #$ff
  txs
  ldx #0
  stx PPU_CTRL
  stx PPU_MASK
  stx $4010
  bit PPU_STATUS
: bit PPU_STATUS
  bpl :-
  ldx #0
: lda #0
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne :-
  lda #$EF
  ldy #0
: sta $0200, y
  iny
  iny
  iny
  iny
  bne :-
: bit PPU_STATUS
  bpl :-
  bit PPU_STATUS
  lda #$00
  sta $2003
  lda #$02
  sta $4014
  lda #$3F
  sta PPU_ADDR
  lda #$00
  sta PPU_ADDR
  lda #$0F
  ldx #$20
: sta PPU_DATA
  dex
  bne :-
  jsr mmc1_reset
  lda #%00000011
  jsr mmc1_write_control
  jmp main
.endproc

.proc main
  SetGameState #GameState::pretitle
@loop:
  lda Game::state
  cmp #GameState::calculate
  beq @calculate
  bit Game::flags
  bpl @loop
  ClearGameFlag Game::FRAME_FLAG
  ReadJoypad1
  jsr executeGameLoopHandler
  jmp @loop
@calculate:
  lda pi_spigot::calcOn
  beq @loop
  jsr pi_spigot::calculate
  jmp @loop
.endproc

.proc nmi
  php
  pha
  txa
  pha
  tya
  pha
  lda Game::state
  cmp #GameState::calculate
  bne @not_calculating
  jsr pi_spigot::draw
  jmp @return
@not_calculating:
  bit Game::flags
  bmi @return
  jsr executeDrawHandler
  SetGameFlag Game::FRAME_FLAG
@return:
  pla
  tay
  pla
  tax
  pla
  plp
  rti
.endproc

.macro JumpTable index, low, high
.scope
  ldx index
  lda low, x
  sta $20
  lda high, x
  sta $21
  jmp ($0020)
.endscope
.endmacro

.proc no_op_handler
  nop
  rts
.endproc

.proc executeInitHandler
  JumpTable Game::state, low, high
.define InitHandlers pretitle::init, title::init, digit_select::init, no_op_handler
low: .lobytes InitHandlers
high: .hibytes InitHandlers
.endproc

.proc executeDrawHandler
  JumpTable Game::state, low, high
.define DrawHandlers pretitle::draw, title::draw, digit_select::draw, no_op_handler
low: .lobytes DrawHandlers
high: .hibytes DrawHandlers
.endproc

.proc executeGameLoopHandler
  JumpTable Game::state, low, high
.define GameLoopHandlers pretitle::game_loop, title::game_loop, digit_select::game_loop, no_op_handler
low:  .lobytes GameLoopHandlers
high: .hibytes GameLoopHandlers
.endproc
