; Compressed 2-bit metatile background generated from 3rd_background.asm
; 4 unique metatiles, 16x15 metatile map, 60 bytes packed + 64 bytes attributes

background_metatile_tl:
  .byte $60,$62,$64,$66
background_metatile_tr:
  .byte $61,$63,$65,$67
background_metatile_bl:
  .byte $70,$72,$74,$76
background_metatile_br:
  .byte $71,$73,$75,$77

background_packed_map:
  .byte $00,$00,$00,$00
  .byte $55,$55,$55,$55
  .byte $01,$00,$02,$40
  .byte $41,$0C,$10,$71
  .byte $01,$03,$0C,$40
  .byte $01,$30,$20,$4B
  .byte $01,$00,$C0,$70
  .byte $41,$50,$00,$40
  .byte $21,$00,$33,$40
  .byte $01,$00,$33,$40
  .byte $31,$02,$00,$42
  .byte $41,$0C,$38,$41
  .byte $01,$40,$00,$40
  .byte $01,$00,$00,$40
  .byte $55,$55,$55,$55

background_attributes:
  .byte $5F,$5F,$5F,$5F,$5F,$5F,$5F,$5F,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55,$55
  .byte $55,$55,$55,$55,$55,$55,$55,$55,$05,$05,$05,$05,$05,$05,$05,$05