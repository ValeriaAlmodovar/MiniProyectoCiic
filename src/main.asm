.include "constants.inc"
.include "header.inc"

; ============================================================
; ZEROPAGE
; Variables importantes que se usan mucho.
; Se guardan aquí porque accederlas es más rápido.
; ============================================================
.segment "ZEROPAGE"

player_tile:        .res 1     ; tile base (top-left) del player actual
player_posx:        .res 1     ; posición X del player
player_posy:        .res 1     ; posición Y del player
player_oam:         .res 1     ; offset de OAM donde empieza el player
player_frame:       .res 1     ; frame actual de animación del player (0,1,2)
anim_timer:         .res 1     ; timer para decidir cuándo cambiar de frame
player_dir:         .res 1     ; dirección del player: 0=right, 1=down, 2=left, 3=up
player_timer:       .res 1     ; timer para decidir cuándo mover el player
player_speed:       .res 1     ; controla la velocidad del player

buttons:            .res 1     ; botones leídos en este frame
pressed_buttons:    .res 1     ; botones del frame anterior
paused:             .res 1     ; 0 = jugando, 1 = pausa
pause_x:            .res 1     ; posición X de la pausa
pause_y:            .res 1     ; posición Y de la pausa
pause_oam:          .res 1     ; offset de OAM donde empieza la pausa

enemy_x:            .res 1     ; posición X del enemigo
enemy_y:            .res 1     ; posición Y del enemigo
enemy_tile:         .res 1     ; tile base del enemigo
enemy_oam:          .res 1     ; offset de OAM donde empieza el enemigo
enemy_timer:        .res 1     ; timer de movimiento del enemigo
enemy_frame:        .res 1     ; frame actual de animación del enemigo
enemy_anim_timer:   .res 1     ; timer para cambiar el frame del enemigo
enemy_dir:          .res 1     ; dirección actual del enemigo
enemy_speed:        .res 1     ; velocidad del enemy


map_ptr_lo:         .res 1
map_ptr_hi:         .res 1
nt_addr_lo:         .res 1
nt_addr_hi:         .res 1
row_count:          .res 1
packed_byte:        .res 1

game_over:          .res 1     ; 0 = juego sigue, 1 = juego terminado

heart_oam:          .res 1     ; offset de OAM donde empiezan los corazones
heart_tile:         .res 1     ; tile base del HUD de vidas
player_lives:       .res 1     ; vidas del jugador
score_ones:         .res 1
score_tens:         .res 1
score_oam:          .res 1
score_x:            .res 1
score_y:            .res 1

coin_x:             .res 1     ; posición X de la moneda
coin_y:             .res 1     ; posición Y de la moneda
coin_tile:          .res 1     ; tile base de la moneda
coin_oam:           .res 1     ; offset de OAM donde empieza la moneda
coin_active:        .res 1     ; 1 = la moneda se dibuja, 0 = no se dibuja
coin_state:         .res 1     ; estado para alternar entre varias posiciones de moneda

next_player_x:      .res 1
next_player_y:      .res 1
next_enemy_x:       .res 1
next_enemy_y:       .res 1
test_col:           .res 1
test_row:           .res 1
tile_kind:          .res 1
can_move:           .res 1

box_base_x:         .res 1
box_base_y:         .res 1

player_wanted_dir:  .res 1
enemy_try_dir:      .res 1

rand_seed:          .res 1

; ============================================================
; CODE
; Rutinas del gameplay
; ============================================================
.segment "CODE"
.proc check_pause_toggle
  ; detectar Start recien presionado
  LDA buttons
  AND #%00010000             ; start actual
  BEQ done

  LDA pressed_buttons
  AND #%00010000             ; start frame anterior
  BNE done                   ; si ya estaba apretado, no togglear otra vez

  ; alternar pausa
  LDA paused
  EOR #$01
  STA paused

done:
  RTS
.endproc

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
  JSR check_pause_toggle     ; verificar pausa

  ; LDA #$00
  ; STA paused

  ; si game_over = 1, se frisa el juego
  LDA game_over
  BEQ continue_game

  ; ocultar player
  LDA #$F8
  STA $0200
  STA $0204
  STA $0208
  STA $020C

  ; ocultar coin
  STA $0210
  STA $0214
  STA $0218
  STA $021C

  ; ocultar enemy
  STA $0220
  STA $0224
  STA $0228
  STA $022C

  ; ocultar HUD normal
  JSR hide_hearts
  JSR hide_pause_symbol

  ; dibujar GAME OVER
  JSR draw_game_over
  JMP hud_done

continue_game:

  ; si pausa = 1, se frisa el juego
  LDA paused
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
  JSR draw_score

  LDA paused
  BEQ draw_lives_hud

  JSR hide_hearts
  JSR draw_pause_symbol
  JMP hud_done
  
draw_lives_hud:
  JSR hide_pause_symbol
  JSR draw_hearts

hud_done:
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
  ; Right
  LDA buttons
  AND #%00000001
  BEQ check_down
  LDA #$00
  STA player_wanted_dir
  RTS

check_down:
  ; Down
  LDA buttons
  AND #%00000100
  BEQ check_left
  LDA #$01
  STA player_wanted_dir
  RTS

check_left:
  ; Left
  LDA buttons
  AND #%00000010
  BEQ check_up
  LDA #$02
  STA player_wanted_dir
  RTS

check_up:
  ; Up
  LDA buttons
  AND #%00001000
  BEQ done
  LDA #$03
  STA player_wanted_dir

done:
  RTS
.endproc

.proc build_next_pos_from_dir
  ; usa:
  ;   A = direccion
  ;   next_player_x / next_player_y = posicion actual
  ; devuelve:
  ;   next_player_x / next_player_y = posicion siguiente (saltando 16 px)

  CMP #$00
  BNE dir_down
  ; right
  LDA next_player_x
  CLC
  ADC #$10
  STA next_player_x
  RTS

dir_down:
  CMP #$01
  BNE dir_left
  LDA next_player_y
  CLC
  ADC #$10
  STA next_player_y
  RTS

dir_left:
  CMP #$02
  BNE dir_up
  LDA next_player_x
  SEC
  SBC #$10
  STA next_player_x
  RTS

dir_up:
  LDA next_player_y
  SEC
  SBC #$10
  STA next_player_y
  RTS
.endproc
; ------------------------------------------------------------
; Mueve al player.
; Solo se mueve si alguna flecha está apretada.
; player_speed controla qué tan rápido camina.
; ------------------------------------------------------------
.proc update_player_movement
  ; timer de velocidad
  INC player_timer
  LDA player_timer
  CMP player_speed
  BNE done

  LDA #$00
  STA player_timer

  ; ---------------------------------
  ; intento 1: virar a wanted_dir
  ; ---------------------------------
  LDA player_posx
  STA next_player_x
  LDA player_posy
  STA next_player_y

  LDA player_wanted_dir
  JSR build_next_pos_from_dir

  JSR check_walkable_box
  LDA can_move
  BEQ hit_wall_wanted

  ; si puede virar, cambia dir y mueve
  LDA player_wanted_dir
  STA player_dir

  LDA next_player_x
  STA player_posx
  LDA next_player_y
  STA player_posy
  RTS

hit_wall_wanted:
  ; ---------------------------------
  ; intento 2: seguir en dir actual
  ; ---------------------------------
  LDA player_posx
  STA next_player_x
  LDA player_posy
  STA next_player_y

  LDA player_dir
  JSR build_next_pos_from_dir

  JSR check_walkable_box
  LDA can_move
  BEQ hit_wall_current

  LDA next_player_x
  STA player_posx
  LDA next_player_y
  STA player_posy

hit_wall_current:
  JSR player_hit
done:
  RTS
.endproc

; ------------------------------------------------------------
; Cambia el frame del player para dar animación.
; Si no se está moviendo, vuelve al frame 0.
; ------------------------------------------------------------
.proc update_player_animation

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

.proc choose_random_coin_pos
random_retry:
  ; mezclar varios valores que cambian durante el juego
  LDA player_timer
  CLC
  ADC enemy_timer
  CLC
  ADC anim_timer
  CLC
  ADC buttons
  CLC
  ADC rand_seed
  STA rand_seed

  ; sacar numero 0..7
  LDA rand_seed
  AND #$07

  ; solo queremos 0..5 porque tienes 6 posiciones
  CMP #$06
  BCS random_retry

  STA coin_state
  TAX

  LDA coin_x_positions,X
  STA coin_x

  LDA coin_y_positions,X
  STA coin_y

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
  BEQ no_coin_collision

  ; no colision si right del player < left del coin
  LDA player_posx
  CLC
  ADC #$0F
  CMP coin_x
  BCC no_coin_collision

  ; no colision si right del coin < left del player
  LDA coin_x
  CLC
  ADC #$0F
  CMP player_posx
  BCC no_coin_collision

  ; no colision si bottom del player < top del coin
  LDA player_posy
  CLC
  ADC #$0F
  CMP coin_y
  BCC no_coin_collision

  ; no colision si bottom del coin < top del player
  LDA coin_y
  CLC
  ADC #$0F
  CMP player_posy
  BCC no_coin_collision

  JMP coin_hit

no_coin_collision:
  RTS

coin_hit:
  ; sumar 1 al score
  INC score_ones
  LDA score_ones
  CMP #$0A
  BNE score_done

  LDA #$00
  STA score_ones
  INC score_tens

  LDA score_tens
  CMP #$0A
  BNE score_done

  LDA #$00
  STA score_tens

score_done:
  ; acelera player, pero no demasiado
  LDA player_speed
  CMP #$02
  BEQ speed_enemy
  BCC speed_enemy
  DEC player_speed

speed_enemy:
  ; acelera enemy tambien, pero que siga mas lento que el player
  LDA enemy_speed
  CMP #$04
  BEQ change_coin_pos
  BCC change_coin_pos
  DEC enemy_speed

change_coin_pos:
  JSR choose_random_coin_pos
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

JSR player_hit
done:
  RTS
.endproc

.proc player_hit
  ; si ya no tiene vidas, no hagas nada
  LDA player_lives
  BEQ done

  ; resta una vida
  DEC player_lives

  ; reset del player
  LDA #$80
  STA player_posx
  LDA #$70
  STA player_posy
  LDA #$18
  STA player_speed
  LDA #$00
  STA player_frame
  STA anim_timer
  STA player_dir
  STA player_timer
  STA player_wanted_dir

  ; reset del enemy
  LDA #$40
  STA enemy_x
  LDA #$50
  STA enemy_y
  LDA #$00
  STA enemy_timer
  LDA #$1C
  STA enemy_speed
  LDA #$00
  STA enemy_frame
  LDA #$00
  STA enemy_anim_timer
  LDA #$00
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
  CMP enemy_speed
  BEQ enemy_move_ready
  RTS

enemy_move_ready:
  LDA #$00
  STA enemy_timer

  ; ==================================================
  ; intento 1: acercarse en X
  ; ==================================================
  LDA player_posx
  CMP enemy_x
  BEQ try_y_axis
  BCC try_left

  ; try right
  LDA #$00
  STA enemy_try_dir
  JMP test_enemy_move

try_left:
  LDA #$02
  STA enemy_try_dir
  JMP test_enemy_move

try_y_axis:
  LDA player_posy
  CMP enemy_y
  BNE enemy_y_not_equal
  JMP done
enemy_y_not_equal:
  BCC try_up

  ; try down
  LDA #$01
  STA enemy_try_dir
  JMP test_enemy_move

try_up:
  LDA #$03
  STA enemy_try_dir

test_enemy_move:
  ; copiar enemy actual a temporales compartidos
  LDA enemy_x
  STA next_player_x
  LDA enemy_y
  STA next_player_y

  LDA enemy_try_dir
  JSR build_next_pos_from_dir

  JSR check_walkable_box
  LDA can_move
  BEQ try_fallback_axis

  ; mover enemy
  LDA next_player_x
  STA enemy_x
  LDA next_player_y
  STA enemy_y
  LDA enemy_try_dir
  STA enemy_dir
  RTS

try_fallback_axis:
  ; ==================================================
  ; si X falló, intenta Y
  ; si Y falló, intenta X
  ; ==================================================
  LDA enemy_try_dir
  CMP #$00
  BEQ fallback_y_from_right
  CMP #$02
  BEQ fallback_y_from_left
  CMP #$01
  BEQ fallback_x_from_down
  ; si era up
  JMP fallback_x_from_up

fallback_y_from_right:
fallback_y_from_left:
  LDA player_posy
  CMP enemy_y
  BNE fallback_y_not_equal
  JMP done
fallback_y_not_equal:
  BCC fallback_up

  LDA #$01
  STA enemy_try_dir
  JMP test_enemy_fallback

fallback_up:
  LDA #$03
  STA enemy_try_dir
  JMP test_enemy_fallback

fallback_x_from_down:
fallback_x_from_up:
  LDA player_posx
  CMP enemy_x
  BNE fallback_x_not_equal
  JMP done
fallback_x_not_equal:
  BCC fallback_left

fallback_left:
  LDA #$02
  STA enemy_try_dir

test_enemy_fallback:
  LDA enemy_x
  STA next_player_x
  LDA enemy_y
  STA next_player_y

  LDA enemy_try_dir
  JSR build_next_pos_from_dir

  JSR check_walkable_box
  LDA can_move
  BEQ done

  LDA next_player_x
  STA enemy_x
  LDA next_player_y
  STA enemy_y
  LDA enemy_try_dir
  STA enemy_dir

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

  ; esconder el bloque completo primero
  LDA #$FF
  STA $0200,X
  STA $0204,X
  STA $0208,X
  STA $020C,X

  ; si no quedan vidas, no dibuja nada
  LDA player_lives
  BEQ done

  ; escoge el tile base segun vidas
  CMP #$03
  BEQ lives3
  CMP #$02
  BEQ lives2

  ; si no es 3 ni 2, asumimos 1
  LDA #$0E
  STA heart_tile
  JMP draw_meta

lives3:
  LDA #$2C
  STA heart_tile
  JMP draw_meta

lives2:
  LDA #$2E
  STA heart_tile

draw_meta:

  ; top left
  LDA #$00
  STA $0200,X
  LDA heart_tile
  STA $0201,X
  LDA #$00
  STA $0202,X
  LDA #$00
  STA $0203,X

  ; top right
  LDA #$00
  STA $0204,X
  LDA heart_tile
  CLC
  ADC #$01
  STA $0205,X
  LDA #$00
  STA $0206,X
  LDA #$08
  STA $0207,X

  ; bottom left
  LDA #$08
  STA $0208,X
  LDA heart_tile
  CLC
  ADC #$10
  STA $0209,X
  LDA #$00
  STA $020A,X
  LDA #$00
  STA $020B,X

  ; bottom right
  LDA #$08
  STA $020C,X
  LDA heart_tile
  CLC
  ADC #$11
  STA $020D,X
  LDA #$00
  STA $020E,X
  LDA #$08
  STA $020F,X

done:
  RTS
.endproc

; ------------------------------------------------------------
; Oculta los corazones del HUD
; ------------------------------------------------------------
.proc hide_hearts
  LDX heart_oam
  LDA #$F8

  ; corazon 1
  STA $0200,X
  STA $0204,X
  STA $0208,X
  STA $020C,X

  ; corazon 2
  STA $0210,X
  STA $0214,X
  STA $0218,X
  STA $021C,X

  ; corazon 3
  STA $0220,X
  STA $0224,X
  STA $0228,X
  STA $022C,X

  RTS
.endproc

; ------------------------------------------------------------
; Dibuja la pausa en el HUD
; ------------------------------------------------------------
.proc draw_pause_symbol
  LDX pause_oam

  ; posicion en pantalla
  LDA #$00
  STA pause_y
  LDA #$78
  STA pause_x

  LDA #PAUSE_TILE
  STA packed_byte

  ; top-left
  LDA pause_y
  STA $0200,X
  LDA packed_byte
  STA $0201,X
  LDA #$03
  STA $0202,X
  LDA pause_x
  STA $0203,X

  ; top-right
  LDA pause_y
  STA $0204,X
  LDA packed_byte
  CLC
  ADC #$01
  STA $0205,X
  LDA #$03
  STA $0206,X
  LDA pause_x
  CLC
  ADC #$08
  STA $0207,X

  ; bottom-left
  LDA pause_y
  CLC
  ADC #$08
  STA $0208,X
  LDA packed_byte
  CLC
  ADC #$10
  STA $0209,X
  LDA #$03
  STA $020A,X
  LDA pause_x
  STA $020B,X

  ; bottom-right
  LDA pause_y
  CLC
  ADC #$08
  STA $020C,X
  LDA packed_byte
  CLC
  ADC #$11
  STA $020D,X
  LDA #$03
  STA $020E,X
  LDA pause_x
  CLC
  ADC #$08
  STA $020F,X

  RTS
.endproc

PAUSE_TILE = $AE
; ------------------------------------------------------------
; Oculta el simbolo de pausa
; ------------------------------------------------------------
.proc hide_pause_symbol
  LDX pause_oam
  LDA #$F8

  STA $0200,X
  STA $0204,X
  STA $0208,X
  STA $020C,X

  RTS
.endproc

; ------------------------------------------------------------
; Dibuja un digito del score
; ------------------------------------------------------------
.proc draw_score_digit
  STA packed_byte

  ; top-left
  LDA score_y
  STA $0200,X
  LDA packed_byte
  STA $0201,X
  LDA #$00
  STA $0202,X
  LDA score_x
  STA $0203,X

  ; top-right
  LDA score_y
  STA $0204,X
  LDA packed_byte
  CLC
  ADC #$01
  STA $0205,X
  LDA #$00
  STA $0206,X
  LDA score_x
  CLC
  ADC #$08
  STA $0207,X

  ; bottom-left
  LDA score_y
  CLC
  ADC #$08
  STA $0208,X
  LDA packed_byte
  CLC
  ADC #$10
  STA $0209,X
  LDA #$00
  STA $020A,X
  LDA score_x
  STA $020B,X

  ; bottom-right
  LDA score_y
  CLC
  ADC #$08
  STA $020C,X
  LDA packed_byte
  CLC
  ADC #$11
  STA $020D,X
  LDA #$00
  STA $020E,X
  LDA score_x
  CLC
  ADC #$08
  STA $020F,X

  RTS
.endproc

; ------------------------------------------------------------
; Dibuja el score
; ------------------------------------------------------------
.proc draw_score
  LDA #$00
  STA score_y

  ; decenas
  LDA #$D0
  STA score_x
  LDA score_tens
  TAX
  LDA digit_tiles,X
  LDX score_oam
  JSR draw_score_digit

  ; unidades
  LDA #$E0
  STA score_x

  LDY score_ones
  LDX score_oam
  TXA
  CLC
  ADC #$10
  TAX
  LDA digit_tiles,Y
  JSR draw_score_digit

  RTS
.endproc

.proc draw_game_over
  LDX #$60   ; usa OAM desde $0280 hasta $02FF

  ; ==================================================
  ; LINEA 1: GAME
  ; ==================================================

  ; G  base tile = $8C
  ; x = $60, y = $60
  LDA #$60
  STA $0200,X
  LDA #$8C
  STA $0201,X
  LDA #$03
  STA $0202,X
  LDA #$60
  STA $0203,X

  LDA #$60
  STA $0204,X
  LDA #$8D
  STA $0205,X
  LDA #$03
  STA $0206,X
  LDA #$68
  STA $0207,X

  LDA #$68
  STA $0208,X
  LDA #$9C
  STA $0209,X
  LDA #$03
  STA $020A,X
  LDA #$60
  STA $020B,X

  LDA #$68
  STA $020C,X
  LDA #$9D
  STA $020D,X
  LDA #$03
  STA $020E,X
  LDA #$68
  STA $020F,X

  ; A  base tile = $8E
  ; x = $70, y = $60
  LDA #$60
  STA $0210,X
  LDA #$8E
  STA $0211,X
  LDA #$03
  STA $0212,X
  LDA #$70
  STA $0213,X

  LDA #$60
  STA $0214,X
  LDA #$8F
  STA $0215,X
  LDA #$03
  STA $0216,X
  LDA #$78
  STA $0217,X

  LDA #$68
  STA $0218,X
  LDA #$9E
  STA $0219,X
  LDA #$03
  STA $021A,X
  LDA #$70
  STA $021B,X

  LDA #$68
  STA $021C,X
  LDA #$9F
  STA $021D,X
  LDA #$03
  STA $021E,X
  LDA #$78
  STA $021F,X

  ; M  base tile = $A0
  ; x = $80, y = $60
  LDA #$60
  STA $0220,X
  LDA #$A0
  STA $0221,X
  LDA #$03
  STA $0222,X
  LDA #$80
  STA $0223,X

  LDA #$60
  STA $0224,X
  LDA #$A1
  STA $0225,X
  LDA #$03
  STA $0226,X
  LDA #$88
  STA $0227,X

  LDA #$68
  STA $0228,X
  LDA #$B0
  STA $0229,X
  LDA #$03
  STA $022A,X
  LDA #$80
  STA $022B,X

  LDA #$68
  STA $022C,X
  LDA #$B1
  STA $022D,X
  LDA #$03
  STA $022E,X
  LDA #$88
  STA $022F,X

  ; E  base tile = $A2
  ; x = $90, y = $60
  LDA #$60
  STA $0230,X
  LDA #$A2
  STA $0231,X
  LDA #$03
  STA $0232,X
  LDA #$90
  STA $0233,X

  LDA #$60
  STA $0234,X
  LDA #$A3
  STA $0235,X
  LDA #$03
  STA $0236,X
  LDA #$98
  STA $0237,X

  LDA #$68
  STA $0238,X
  LDA #$B2
  STA $0239,X
  LDA #$03
  STA $023A,X
  LDA #$90
  STA $023B,X

  LDA #$68
  STA $023C,X
  LDA #$B3
  STA $023D,X
  LDA #$03
  STA $023E,X
  LDA #$98
  STA $023F,X

  ; ==================================================
  ; LINEA 2: OVER
  ; ==================================================

  ; O  base tile = $A4
  ; x = $60, y = $78
  LDA #$78
  STA $0240,X
  LDA #$A4
  STA $0241,X
  LDA #$03
  STA $0242,X
  LDA #$60
  STA $0243,X

  LDA #$78
  STA $0244,X
  LDA #$A5
  STA $0245,X
  LDA #$03
  STA $0246,X
  LDA #$68
  STA $0247,X

  LDA #$80
  STA $0248,X
  LDA #$B4
  STA $0249,X
  LDA #$03
  STA $024A,X
  LDA #$60
  STA $024B,X

  LDA #$80
  STA $024C,X
  LDA #$B5
  STA $024D,X
  LDA #$03
  STA $024E,X
  LDA #$68
  STA $024F,X

  ; V  base tile = $A6
  ; x = $70, y = $78
  LDA #$78
  STA $0250,X
  LDA #$A6
  STA $0251,X
  LDA #$03
  STA $0252,X
  LDA #$70
  STA $0253,X

  LDA #$78
  STA $0254,X
  LDA #$A7
  STA $0255,X
  LDA #$03
  STA $0256,X
  LDA #$78
  STA $0257,X

  LDA #$80
  STA $0258,X
  LDA #$B6
  STA $0259,X
  LDA #$03
  STA $025A,X
  LDA #$70
  STA $025B,X

  LDA #$80
  STA $025C,X
  LDA #$B7
  STA $025D,X
  LDA #$03
  STA $025E,X
  LDA #$78
  STA $025F,X

  ; E  base tile = $A2
  ; x = $80, y = $78
  LDA #$78
  STA $0260,X
  LDA #$A2
  STA $0261,X
  LDA #$03
  STA $0262,X
  LDA #$80
  STA $0263,X

  LDA #$78
  STA $0264,X
  LDA #$A3
  STA $0265,X
  LDA #$03
  STA $0266,X
  LDA #$88
  STA $0267,X

  LDA #$80
  STA $0268,X
  LDA #$B2
  STA $0269,X
  LDA #$03
  STA $026A,X
  LDA #$80
  STA $026B,X

  LDA #$80
  STA $026C,X
  LDA #$B3
  STA $026D,X
  LDA #$03
  STA $026E,X
  LDA #$88
  STA $026F,X

  ; R  base tile = $A8
  ; x = $90, y = $78
  LDA #$78
  STA $0270,X
  LDA #$A8
  STA $0271,X
  LDA #$03
  STA $0272,X
  LDA #$90
  STA $0273,X

  LDA #$78
  STA $0274,X
  LDA #$A9
  STA $0275,X
  LDA #$03
  STA $0276,X
  LDA #$98
  STA $0277,X

  LDA #$80
  STA $0278,X
  LDA #$B8
  STA $0279,X
  LDA #$03
  STA $027A,X
  LDA #$90
  STA $027B,X

  LDA #$80
  STA $027C,X
  LDA #$B9
  STA $027D,X
  LDA #$03
  STA $027E,X
  LDA #$98
  STA $027F,X

  RTS
.endproc
; ------------------------------------------------------------
; BACKGROUND
; Crea background
; ------------------------------------------------------------

.proc emit_four_tops
  STA packed_byte

  LDA packed_byte
  AND #%00000011
  TAX
  LDA background_metatile_tl,X
  STA PPUDATA
  LDA background_metatile_tr,X
  STA PPUDATA

  LDA packed_byte
  LSR A
  LSR A
  AND #%00000011
  TAX
  LDA background_metatile_tl,X
  STA PPUDATA
  LDA background_metatile_tr,X
  STA PPUDATA

  LDA packed_byte
  LSR A
  LSR A
  LSR A
  LSR A
  AND #%00000011
  TAX
  LDA background_metatile_tl,X
  STA PPUDATA
  LDA background_metatile_tr,X
  STA PPUDATA

  LDA packed_byte
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  TAX
  LDA background_metatile_tl,X
  STA PPUDATA
  LDA background_metatile_tr,X
  STA PPUDATA

  RTS
.endproc

.proc emit_four_bottoms
  STA packed_byte

  LDA packed_byte
  AND #%00000011
  TAX
  LDA background_metatile_bl,X
  STA PPUDATA
  LDA background_metatile_br,X
  STA PPUDATA

  LDA packed_byte
  LSR A
  LSR A
  AND #%00000011
  TAX
  LDA background_metatile_bl,X
  STA PPUDATA
  LDA background_metatile_br,X
  STA PPUDATA

  LDA packed_byte
  LSR A
  LSR A
  LSR A
  LSR A
  AND #%00000011
  TAX
  LDA background_metatile_bl,X
  STA PPUDATA
  LDA background_metatile_br,X
  STA PPUDATA

  LDA packed_byte
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  TAX
  LDA background_metatile_bl,X
  STA PPUDATA
  LDA background_metatile_br,X
  STA PPUDATA

  RTS
.endproc

.proc load_background
  ; Packed map pointer
  LDA #<background_packed_map
  STA map_ptr_lo
  LDA #>background_packed_map
  STA map_ptr_hi

  ; Start at nametable $2000
  LDA #$00
  STA nt_addr_lo
  LDA #$20
  STA nt_addr_hi

  ; 15 metatile rows total
  LDA #15
  STA row_count

metatile_row_loop:
  LDA PPUSTATUS
  LDA nt_addr_hi
  STA PPUADDR
  LDA nt_addr_lo
  STA PPUADDR

  LDY #$00
top_loop:
  LDA (map_ptr_lo),Y
  JSR emit_four_tops
  INY
  CPY #$04
  BNE top_loop

  LDA PPUSTATUS
  LDA nt_addr_hi
  STA PPUADDR
  LDA nt_addr_lo
  CLC
  ADC #$20
  STA PPUADDR

  LDY #$00
bottom_loop:
  LDA (map_ptr_lo),Y
  JSR emit_four_bottoms
  INY
  CPY #$04
  BNE bottom_loop

  ; Advance packed map pointer by 4 bytes
  CLC
  LDA map_ptr_lo
  ADC #$04
  STA map_ptr_lo
  LDA map_ptr_hi
  ADC #$00
  STA map_ptr_hi

  ; Advance nametable address by 2 tile rows = $40 bytes
  CLC
  LDA nt_addr_lo
  ADC #$40
  STA nt_addr_lo
  LDA nt_addr_hi
  ADC #$00
  STA nt_addr_hi

  DEC row_count
  BNE metatile_row_loop

  LDA PPUSTATUS
  LDA #$23
  STA PPUADDR
  LDA #$C0
  STA PPUADDR

  LDY #$00
attr_loop:
  LDA background_attributes,Y
  STA PPUDATA
  INY
  CPY #$40
  BNE attr_loop

  RTS
.endproc

.proc check_walkable
  ; usa next_player_x / next_player_y como posicion a probar

  LDA next_player_x
  LSR
  LSR
  LSR
  LSR
  STA test_col

  LDA next_player_y
  LSR
  LSR
  LSR
  LSR
  STA test_row

  ; index = row * 16 + col
  LDA test_row
  ASL
  ASL
  ASL
  ASL
  CLC
  ADC test_col
  TAX

  ; byte_index = index / 4
  TXA
  LSR
  LSR
  TAY

  ; offset dentro del byte = index % 4
  TXA
  AND #$03
  STA tile_kind

  ; leer byte del mapa comprimido
  LDA background_packed_map,Y

  ; acomodar al metatile correcto
  LDX tile_kind
shift_loop:
  CPX #$00
  BEQ done_shift
  LSR
  LSR
  DEX
  JMP shift_loop

done_shift:
  AND #$03

  ; solo metatile 0 = fondo verde = caminable
  CMP #$00
  BEQ walk_ok

blocked:
  LDA #$00
  STA can_move
  RTS

walk_ok:
  LDA #$01
  STA can_move
  RTS
.endproc

.proc check_walkable_box
  ; guarda la posicion base del cuadro 16x16
  LDA next_player_x
  STA box_base_x
  LDA next_player_y
  STA box_base_y

  ; esquina 1: top-left
  LDA box_base_x
  STA next_player_x
  LDA box_base_y
  STA next_player_y
  JSR check_walkable
  LDA can_move
  BEQ blocked

  ; esquina 2: top-right
  LDA box_base_x
  CLC
  ADC #$0F
  STA next_player_x
  LDA box_base_y
  STA next_player_y
  JSR check_walkable
  LDA can_move
  BEQ blocked

  ; esquina 3: bottom-left
  LDA box_base_x
  STA next_player_x
  LDA box_base_y
  CLC
  ADC #$0F
  STA next_player_y
  JSR check_walkable
  LDA can_move
  BEQ blocked

  ; esquina 4: bottom-right
  LDA box_base_x
  CLC
  ADC #$0F
  STA next_player_x
  LDA box_base_y
  CLC
  ADC #$0F
  STA next_player_y
  JSR check_walkable
  LDA can_move
  BEQ blocked

walk_ok:
  ; restaurar posicion base original
  LDA box_base_x
  STA next_player_x
  LDA box_base_y
  STA next_player_y

  LDA #$01
  STA can_move
  RTS

blocked:
  ; tambien restaurar posicion base original
  LDA box_base_x
  STA next_player_x
  LDA box_base_y
  STA next_player_y

  LDA #$00
  STA can_move
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

  JSR load_background

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
  STA player_oam
  LDA #$18
  STA player_speed
  LDA #$00
  STA player_wanted_dir
  LDA #$00
  STA buttons
  LDA #$00
  STA pressed_buttons
  LDA #$00
  STA paused
  LDA #$60
  STA pause_oam

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

  ; --- inicializa score ---
  LDA #$00
  STA score_ones
  STA score_tens

  LDA #$E0
  STA score_oam

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
  LDA #$1C
  STA enemy_speed
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
  LDA #%10000000
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
.byte $0F, $30, $35, $09
.byte $0F, $30, $10, $09
.byte $0F, $30, $31, $09
.byte $0F, $2D, $00, $10

; sprite pallete
.byte $0F, $35, $25, $15 ; Kirby y Heart
.byte $0F, $2C, $23, $13 ; Coin
.byte $0F, $26, $16, $2A ; Link
.byte $0F, $30, $10, $00 ; Pause

; tabla de tiles base para animación
; 3 tiles por dirección:
; right, down, left, up
player_animation_tiles:
.byte $04, $08, $0A ; right
.byte $24, $20, $22 ; down
.byte $00, $02, $06 ; left
.byte $26, $28, $2A ; up

enemy_animation_tiles:
.byte $44, $46, $44 ; right
.byte $40, $42, $40 ; down
.byte $48, $4A, $48 ; left
.byte $4C, $4E, $4C ; up

coin_x_positions:
.byte $90, $50, $B0, $30, $C0, $70
coin_y_positions:
.byte $70, $90, $50, $40, $90, $40

digit_tiles:
.byte $68, $6A, $6C, $6E, $80
.byte $82, $84, $86, $88, $8A

.include "background.asm"
; ============================================================
; CHARS
; CHR ROM con los sprites/tiles
; ============================================================
.segment "CHR"
.incbin "tiles.chr"