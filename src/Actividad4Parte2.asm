.include "constants.inc"
.include "header.inc"

; ============================================================
; ZEROPAGE
; Variables importantes que se usan mucho.
; Se guardan aquí porque accederlas es más rápido.
; ============================================================
.segment "ZEROPAGE"

player_tile:       .res 1     ; tile base (top-left) del player actual
player_posx:       .res 1     ; posición X del player
player_posy:       .res 1     ; posición Y del player
player_oam:        .res 1     ; offset de OAM donde empieza el player
player_frame:      .res 1     ; frame actual de animación del player (0,1,2)
anim_timer:        .res 1     ; timer para decidir cuándo cambiar de frame
player_dir:        .res 1     ; dirección del player: 0=right, 1=down, 2=left, 3=up
player_timer:      .res 1     ; timer para decidir cuándo mover el player
player_speed:       .res 1     ; controla la velocidad del player

buttons:           .res 1     ; botones leídos en este frame
pressed_buttons:   .res 1     ; botones del frame anterior

coin_x:            .res 1     ; posición X de la moneda
coin_y:            .res 1     ; posición Y de la moneda
coin_tile:         .res 1     ; tile base de la moneda
coin_oam:          .res 1     ; offset de OAM donde empieza la moneda
coin_active:       .res 1     ; 1 = la moneda se dibuja, 0 = no se dibuja
coin_state:        .res 1     ; estado para alternar entre varias posiciones de moneda

enemy_x:           .res 1     ; posición X del enemigo
enemy_y:           .res 1     ; posición Y del enemigo
enemy_tile:        .res 1     ; tile base del enemigo
enemy_oam:         .res 1     ; offset de OAM donde empieza el enemigo
enemy_timer:       .res 1     ; timer de movimiento del enemigo
enemy_frame:       .res 1     ; frame actual de animación del enemigo
enemy_anim_timer:  .res 1     ; timer para cambiar el frame del enemigo
enemy_dir:         .res 1     ; dirección actual del enemigo

player_lives:      .res 1     ; vidas del jugador

; ============================================================
; BSS
; Variables normales en RAM. No necesitan ser tan rápidas.
; Estan aqui por overflow del zeropage
; ============================================================
.segment "BSS"

game_over:         .res 1     ; 0 = juego sigue, 1 = juego terminado
heart_oam:         .res 1     ; offset de OAM donde empiezan los corazones
heart_y:           .res 1     ; Y temporal para dibujar corazones
heart_x:           .res 1     ; X temporal para dibujar corazones

; ============================================================
; CODE
; Rutinas del gameplay
; ============================================================
.segment "CODE"
; ------------------------------------------------------------
; IRQ handler
; ------------------------------------------------------------
.proc irq_handler
  RTI
.endproc

; ------------------------------------------------------------
; NMI handler
; Esta rutina corre una vez por frame, durante vblank.
; Donde se actualiza todo y dibuja todo.
; ------------------------------------------------------------
.proc nmi_handler
  JSR read_arrow_keys        ; leer control

  ; si game_over = 1, se frisa el juego
  LDA game_over
  BNE freeze_game

  ; --- actualizar player ---
  JSR update_player_direccion
  JSR update_player_movement
  JSR update_player_animation
  JSR update_player_sprite

  ; --- revisar colisiones ---
  JSR check_coin_collision
  JSR check_enemy_collision

  ; --- actualizar enemigo ---
  JSR update_enemy_direction
  JSR update_enemy_movement
  JSR update_enemy_animation
  JSR update_enemy_sprite

freeze_game:
  ; el player empieza en el bloque OAM 0x00
  LDA #$00
  STA player_oam

  ; dibujar todos los sprites
  JSR draw_player
  JSR draw_coin
  JSR draw_enemy
  JSR draw_hearts

  ; ----------------------------------------------------------
  ; DMA de sprites:
  ; copia el bloque $0200-$02FF a OAM del PPU
  ; ----------------------------------------------------------
  LDA #$00
  STA OAMADDR
  LDA #$02
  STA OAMDMA

  ; reset scrol(evita scrolling bug)
  LDA #$00
  STA $2005
  STA $2005

  RTI
.endproc

.import reset_handler

; ------------------------------------------------------------
; Lee el control del puerto $4016
; Al final:
; bit 0 = Right
; bit 1 = Left
; bit 2 = Down
; bit 3 = Up
; Los otros bits corresponden a otros botones del control.
; ------------------------------------------------------------
.proc read_arrow_keys
  ; guardar botones anteriores
  LDA buttons
  STA pressed_buttons

  ; limpiar buttons para volver a llenarlo con el presionado
  LDA #$00
  STA buttons

  ; strobe del control
  LDA #$01
  STA $4016
  LDA #$00
  STA $4016

  ; lee 8 bits del control
  LDX #$08
arrowkey_loop:
  LDA $4016
  LSR A
  ROL buttons
  DEX
  BNE arrowkey_loop

  RTS
.endproc

; ------------------------------------------------------------
; Decide la dirección del player según los arrow keys.
; Right -> Down -> Left -> Up
; ------------------------------------------------------------
.proc update_player_direccion
  ; si Right está apretado, mira a la derecha
  LDA buttons
  AND #%00000001
  BEQ down_arrow
  LDA #$00
  STA player_dir
  RTS

down_arrow:
  ; si Down está apretado, mira hacia abajo
  LDA buttons
  AND #%00000100
  BEQ left_arrow
  LDA #$01
  STA player_dir
  RTS

left_arrow:
  ; si Left está apretado, mira a la izquierda
  LDA buttons
  AND #%00000010
  BEQ up_arrow
  LDA #$02
  STA player_dir
  RTS

up_arrow:
  ; si Up está apretado, mira hacia arriba
  LDA buttons
  AND #%00001000
  BEQ dir_done
  LDA #$03
  STA player_dir

dir_done:
  RTS
.endproc

; ------------------------------------------------------------
; Mueve al player.
; Solo se mueve si alguna flecha está apretada.
; player_speed controla qué tan rápido camina.
; ------------------------------------------------------------
.proc update_player_movement
  ; si no hay flechas, no se anima/mueve
  LDA buttons
  AND #%00001111
  BEQ move_done

  ; timer para no moverlo todos los frames
  INC player_timer
  LDA player_timer
  CMP player_speed
  BNE move_done

  ; reset timer cuando toca moverse
  LDA #$00
  STA player_timer

  ; mover según dirección actual
  LDA player_dir
  CMP #$00
  BNE move_down
  INC player_posx
  RTS

move_down:
  CMP #$01
  BNE move_left
  INC player_posy
  RTS

move_left:
  CMP #$02
  BNE move_up
  DEC player_posx
  RTS

move_up:
  DEC player_posy

move_done:
  RTS
.endproc

; ------------------------------------------------------------
; Cambia el frame del player para dar animación.
; Si no se está moviendo, vuelve al frame 0.
; ------------------------------------------------------------
.proc update_player_animation
  ; si no hay movimiento, deja al player quieto
  LDA buttons
  AND #%00001111
  BNE anim_running

  LDA #$00
  STA player_frame
  STA anim_timer
  RTS

anim_running:
  ; suma timer de animación
  INC anim_timer
  LDA anim_timer
  CMP #$08
  BNE anim_done

  ; al llegar a 8, resetea timer
  LDA #$00
  STA anim_timer

  ; avanza al siguiente frame
  INC player_frame
  LDA player_frame
  CMP #$03
  BNE anim_done

  ; si pasó del frame 2, vuelve a 0
  LDA #$00
  STA player_frame

anim_done:
  RTS
.endproc

; ------------------------------------------------------------
; Escoge el tile base del player según:
; index = player_dir * 3 + player_frame
; Busca ese índice en player_animation_tiles.
; ------------------------------------------------------------
.proc update_player_sprite
  LDA player_dir
  ASL A              ; dir * 2
  CLC
  ADC player_dir     ; dir * 3
  CLC
  ADC player_frame   ; dir * 3 + frame
  TAX
  LDA player_animation_tiles,X
  STA player_tile
  RTS
.endproc

; ------------------------------------------------------------
; Dibuja al player como metasprite 2x2.
; Usa player_tile como tile top-left (tile de base para dibujar).
; ------------------------------------------------------------
.export draw_player
.proc draw_player
  LDX player_oam

  ; top-left
  LDA player_posy
  STA $0200,X
  LDA player_tile
  STA $0201,X
  LDA #$00
  STA $0202,X
  LDA player_posx
  STA $0203,X

  ; top right = tile base + 1
  LDA player_posy
  STA $0204,X
  LDA player_tile
  CLC
  ADC #$01
  STA $0205,X
  LDA #$00
  STA $0206,X
  LDA player_posx
  CLC
  ADC #$08
  STA $0207,X

  ; bottom left = tile base + $10
  LDA player_posy
  CLC
  ADC #$08
  STA $0208,X
  LDA player_tile
  CLC
  ADC #$10
  STA $0209,X
  LDA #$00
  STA $020A,X
  LDA player_posx
  STA $020B,X

  ; bottom right = tile base + $11
  LDA player_posy
  CLC
  ADC #$08
  STA $020C,X
  LDA player_tile
  CLC
  ADC #$11
  STA $020D,X
  LDA #$00
  STA $020E,X
  LDA player_posx
  CLC
  ADC #$08
  STA $020F,X

  RTS
.endproc

; ------------------------------------------------------------
; Dibuja la moneda como metasprite 2x2.
; Si coin_active = 0, no la dibuja.
; ------------------------------------------------------------
.proc draw_coin
  LDA coin_active
  BEQ done
  LDX coin_oam

  ; top left
  LDA coin_y
  STA $0200,X
  LDA coin_tile
  STA $0201,X
  LDA #$01
  STA $0202,X
  LDA coin_x
  STA $0203,X

  ; top right
  LDA coin_y
  STA $0204,X
  LDA coin_tile
  CLC
  ADC #$01
  STA $0205,X
  LDA #$01
  STA $0206,X
  LDA coin_x
  CLC
  ADC #$08
  STA $0207,X

  ; bottom left
  LDA coin_y
  CLC
  ADC #$08
  STA $0208,X
  LDA coin_tile
  CLC
  ADC #$10
  STA $0209,X
  LDA #$01
  STA $020A,X
  LDA coin_x
  STA $020B,X

  ; bottom right
  LDA coin_y
  CLC
  ADC #$08
  STA $020C,X
  LDA coin_tile
  CLC
  ADC #$11
  STA $020D,X
  LDA #$01
  STA $020E,X
  LDA coin_x
  CLC
  ADC #$08
  STA $020F,X

done:
  RTS
.endproc

; ------------------------------------------------------------
; Revisa colisión entre el player y el coin usando boxes 16x16.
; Si colisiona:
; - aumenta velocidad del player (disminuyendo player_speed)
; - cambia la moneda a otra posición
; ------------------------------------------------------------
.proc check_coin_collision
  LDA coin_active
  BEQ done

  ; no colisión si right del player < left del coin
  LDA player_posx
  CLC
  ADC #$0F
  CMP coin_x
  BCC done

  ; no colisión si right del coin < left del player
  LDA coin_x
  CLC
  ADC #$0F
  CMP player_posx
  BCC done

  ; no colisión si bottom del player < top del coin
  LDA player_posy
  CLC
  ADC #$0F
  CMP coin_y
  BCC done

  ; no colisión si bottom del coin < top del player
  LDA coin_y
  CLC
  ADC #$0F
  CMP player_posy
  BCC done

  ; si el player todavía puede acelerar, bajar player_speed
  LDA player_speed
  CMP #$02
  BEQ change_speed
  BCC change_speed
  DEC player_speed

change_speed:
  ; cambiar estado para mover moneda entre 3 lugares diferentes (for now)
  INC coin_state
  LDA coin_state
  CMP #$03
  BNE move_coin

  LDA #$00
  STA coin_state

move_coin:
  ; posición 0
  LDA coin_state
  CMP #$00
  BNE move_coin1
  LDA #$90
  STA coin_x
  LDA #$70
  STA coin_y
  RTS

move_coin1:
  ; posición 1
  CMP #$01
  BNE move_coin2
  LDA #$50
  STA coin_x
  LDA #$90
  STA coin_y
  RTS

move_coin2:
  ; posición 2
  LDA #$B0
  STA coin_x
  LDA #$50
  STA coin_y

done:
  RTS
.endproc

; ------------------------------------------------------------
; Dibuja al enemigo como metasprite 2x2.
; Usa otra paleta para diferenciarlo del player.
; ------------------------------------------------------------
.proc draw_enemy
  LDX enemy_oam

  ; top left
  LDA enemy_y
  STA $0200,X
  LDA enemy_tile
  STA $0201,X
  LDA #$02
  STA $0202,X
  LDA enemy_x
  STA $0203,X

  ; top right
  LDA enemy_y
  STA $0204,X
  LDA enemy_tile
  CLC
  ADC #$01
  STA $0205,X
  LDA #$02
  STA $0206,X
  LDA enemy_x
  CLC
  ADC #$08
  STA $0207,X

  ; bottom left
  LDA enemy_y
  CLC
  ADC #$08
  STA $0208,X
  LDA enemy_tile
  CLC
  ADC #$10
  STA $0209,X
  LDA #$02
  STA $020A,X
  LDA enemy_x
  STA $020B,X

  ; bottom right
  LDA enemy_y
  CLC
  ADC #$08
  STA $020C,X
  LDA enemy_tile
  CLC
  ADC #$11
  STA $020D,X
  LDA #$02
  STA $020E,X
  LDA enemy_x
  CLC
  ADC #$08
  STA $020F,X

  RTS
.endproc

; ------------------------------------------------------------
; Revisa colisión entre el player y el enemy usando boxes 16x16.
; Si colisiona:
; - resta una vida
; - resetea player
; - resetea enemy
; - pone game_over = 1 cuando vidas llegan a 0
; ------------------------------------------------------------
.proc check_enemy_collision
  ; check X
  LDA player_posx
  CLC
  ADC #$0F
  CMP enemy_x
  BCC done

  LDA enemy_x
  CLC
  ADC #$0F
  CMP player_posx
  BCC done

  ; check Y
  LDA player_posy
  CLC
  ADC #$0F
  CMP enemy_y
  BCC done

  LDA enemy_y
  CLC
  ADC #$0F
  CMP player_posy
  BCC done

  ; pierdes vida
  LDA player_lives
  BEQ done
  DEC player_lives

  ; reset del player
  LDA #$80
  STA player_posx
  LDA #$70
  STA player_posy
  LDA #$05
  STA player_speed
  LDA #$00
  STA player_frame
  STA anim_timer
  STA player_dir
  STA player_timer

  ; reset del enemy
  LDA #$40
  STA enemy_x
  LDA #$50
  STA enemy_y
  LDA #$00
  STA enemy_timer
  STA enemy_frame
  STA enemy_anim_timer
  STA enemy_dir

  ; si no quedan vidas, game over
  LDA player_lives
  BNE done

  LDA #$01
  STA game_over

done:
  RTS
.endproc

; ------------------------------------------------------------
; Movimiento del enemigo.
; Usa timer para que no se mueva tan rápido.
; ------------------------------------------------------------
.proc update_enemy_movement
  INC enemy_timer
  LDA enemy_timer
  CMP #$05
  BNE done

  ; reset timer
  LDA #$00
  STA enemy_timer

  ; mover en X primero
  LDA player_posx
  CMP enemy_x
  BEQ move_y
  BCC move_left

  INC enemy_x
  RTS

move_left:
  DEC enemy_x
  RTS

move_y:
  ; cuando ya está alineado en X, mover Y
  LDA player_posy
  CMP enemy_y
  BEQ done
  BCC move_up

  INC enemy_y
  RTS

move_up:
  DEC enemy_y

done:
  RTS
.endproc

; ------------------------------------------------------------
; Decide hacia dónde mira el enemigo.
; ------------------------------------------------------------
.proc update_enemy_direction
  LDA player_posx
  CMP enemy_x
  BEQ check_y
  BCC enemy_left

  LDA #$00      ; right
  STA enemy_dir
  RTS

enemy_left:
  LDA #$02      ; left
  STA enemy_dir
  RTS

check_y:
  LDA player_posy
  CMP enemy_y
  BEQ done
  BCC enemy_up

  LDA #$01      ; down
  STA enemy_dir
  RTS

enemy_up:
  LDA #$03      ; up
  STA enemy_dir

done:
  RTS
.endproc

; ------------------------------------------------------------
; Cambia el frame del enemigo para animarlo.
; ------------------------------------------------------------
.proc update_enemy_animation
  INC enemy_anim_timer
  LDA enemy_anim_timer
  CMP #$08
  BNE anim_done

  LDA #$00
  STA enemy_anim_timer

  INC enemy_frame
  LDA enemy_frame
  CMP #$03
  BNE anim_done

  LDA #$00
  STA enemy_frame

anim_done:
  RTS
.endproc

; ------------------------------------------------------------
; Escoge el tile base del enemigo según su dirección y frame.
; Usa la misma tabla player_animation_tiles que el player.
; ------------------------------------------------------------
.proc update_enemy_sprite
  LDA enemy_dir
  ASL A
  CLC
  ADC enemy_dir
  CLC
  ADC enemy_frame
  TAX
  LDA enemy_animation_tiles,X
  STA enemy_tile
  RTS
.endproc

; ------------------------------------------------------------
; Dibuja los corazones de vida en el HUD.
; ------------------------------------------------------------
.proc draw_hearts
  LDX heart_oam
  LDY #$00            ; contador de corazones

draw_loop:
  
  CPY player_lives
  BEQ clear_extra

  ; X = 16 + (Y * 16)
  TYA
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #$10
  STA heart_x

  ; Y fijo arriba del HUD
  LDA #$10
  STA heart_y

  ; top left
  LDA heart_y
  STA $0200,X
  LDA #$0E
  STA $0201,X
  LDA #$00
  STA $0202,X
  LDA heart_x
  STA $0203,X

  ; top right
  LDA heart_y
  STA $0204,X
  LDA #$0F
  STA $0205,X
  LDA #$00
  STA $0206,X
  LDA heart_x
  CLC
  ADC #$08
  STA $0207,X

  ; bottom left
  LDA heart_y
  CLC
  ADC #$08
  STA $0208,X
  LDA #$1E
  STA $0209,X
  LDA #$00
  STA $020A,X
  LDA heart_x
  STA $020B,X

  ; bottom right
  LDA heart_y
  CLC
  ADC #$08
  STA $020C,X
  LDA #$1F
  STA $020D,X
  LDA #$00
  STA $020E,X
  LDA heart_x
  CLC
  ADC #$08
  STA $020F,X

  ; avanza al siguiente corazón en OAM
  TXA
  CLC
  ADC #$10
  TAX

  INY
  JMP draw_loop

clear_extra:
  ; borra corazones sobrantes hasta 3
  CPY #$03
  BEQ done

  LDA #$FF
  STA $0200,X
  STA $0204,X
  STA $0208,X
  STA $020C,X

  TXA
  CLC
  ADC #$10
  TAX

  INY
  JMP clear_extra

done:
  RTS
.endproc

; ------------------------------------------------------------
; MAIN
; Inicializa paletas, variables y enciende PPU.
; Luego entra al loop infinito.
; ------------------------------------------------------------
.export main
.proc main
  ; cargar paletas en $3F00
  LDA PPUSTATUS
  LDA #$3F
  STA PPUADDR
  LDA #$00
  STA PPUADDR

  ; copiar 32 bytes de paleta
  LDX #$00
load_palettes:
  LDA palettes,X
  STA PPUDATA
  INX
  CPX #$20
  BNE load_palettes

  ; --- inicializa player ---
  LDA #$80
  STA player_posx
  LDA #$70
  STA player_posy
  LDA #$00
  STA player_frame
  LDA #$00
  STA anim_timer
  LDA #$00
  STA player_dir
  LDA #$00
  STA player_timer
  LDA #$00
  STA buttons
  LDA #$00
  STA pressed_buttons
  LDA #$00
  STA player_oam
  LDA #$05
  STA player_speed

  ; --- inicializa vidas y HUD ---
  LDA #$03
  STA player_lives
  LDA #$00
  STA game_over
  LDA #$30
  STA heart_oam

  ; --- inicializa coin ---
  LDA #$90
  STA coin_x
  LDA #$70
  STA coin_y
  LDA #$0C
  STA coin_tile
  LDA #$10
  STA coin_oam
  LDA #$01
  STA coin_active
  LDA #$00
  STA coin_state

  ; --- inicializa enemy ---
  LDA #$40
  STA enemy_x
  LDA #$50
  STA enemy_y
  LDA #$15
  STA enemy_tile
  LDA #$20
  STA enemy_oam
  LDA #$00
  STA enemy_timer
  LDA #$00
  STA enemy_anim_timer
  LDA #$00
  STA enemy_frame
  LDA #$00
  STA enemy_dir

  ; escoger tile inicial del player
  JSR update_player_sprite

vblankwait:
  ; esperar vblank antes de prender pantalla
  BIT PPUSTATUS
  BPL vblankwait

  ; prender NMI y pantalla
  LDA #%10010000
  STA PPUCTRL
  LDA #%00011110
  STA PPUMASK

forever:
  JMP forever
.endproc

.segment "VECTORS"
.addr nmi_handler, reset_handler, irq_handler

; ============================================================
; RODATA
; Paletas y tabla de animación
; ============================================================
.segment "RODATA"

palettes:
.byte $0F, $01, $11, $21
.byte $0F, $06, $16, $26
.byte $0F, $09, $19, $29
.byte $0F, $0C, $1C, $2C

; sprite pallete
.byte $0F, $35, $25, $15 ; kirby y heart
.byte $0F, $10, $00, $2D ; coin
.byte $0F, $26, $16, $2A ; link
.byte $0F, $35, $25, $15 ; 

; tabla de tiles base para animación
; 3 tiles por dirección:
; right, down, left, up
player_animation_tiles:
.byte $04, $08, $0A ; right
.byte $24, $20, $22 ; down
.byte $00, $02, $06 ; left
.byte $26, $28, $30 ; up

enemy_animation_tiles:
.byte $44, $46, $44 ; right
.byte $40, $42, $40 ; down
.byte $48, $4A, $48 ; left
.byte $4C, $4E, $4C ; up


; ============================================================
; CHARS
; CHR ROM con los sprites/tiles
; ============================================================
.segment "CHARS"
.incbin "player.chr"