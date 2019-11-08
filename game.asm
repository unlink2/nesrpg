; game related code

; inits game mode
; inputs:
;   level_data_ptr -> pointing to compressed level
;   attr_ptr -> pointing to attributes
;   palette_ptr -> pointing to palette
init_game:
    lda #GAME_MODE_PUZZLE
    sta game_mode

    lda #<update_game
    sta update_sub
    lda #>update_game
    sta update_sub+1

    ; copy palette
    lda #<level_palette 
    sta palette_ptr 
    lda #>level_palette
    sta palette_ptr+1
    jsr load_palette

    jsr find_start
    ; check if start was found
    cmp #$01 
    beq @no_error 
    ; error state
    lda #ERROR_NO_START_TILE
    sta errno
@no_error:

    lda player_x 
    sta player_x_bac
    lda player_y 
    sta player_y_bac

    ; player sprite
    lda #$32 
    sta sprite_data+1

    ; move other sprites offscreen
    lda #$00 
    sta sprite_data_1 
    sta sprite_data_1+3
    sta sprite_data_2 
    sta sprite_data_2+3

    rts 

; this routine is called every frame
; it updates the game state
update_game:
    ; check if player moved
    lda #$00 ; move flag
    ldx player_x 
    cpx player_x_bac 
    beq @player_not_moved_x 

    lda #$01 ; did move
@player_not_moved_x:
    ldx player_y 
    cpx player_y_bac 
    beq @player_not_moved_y 
    lda #$01 ; did move
@player_not_moved_y:
    cmp #$01 
    bne @player_not_moved

    ; test collision
    jsr collision_check
    ; if a = 1 collision occured
    cmp #$01
    beq @player_not_moved 

    ; test if the current tile
    ; is already marked if so, do not update the previous tile but rather unmark the current
    jsr get_tile 
    and #%10000000 
    beq @tile_update_not_marked
    jsr update_tile
    jmp @skip_tile_update
@tile_update_not_marked:
    ; update current tile if player did move
    ; game mode is puzzle
    ; therefore a tile update will update the tile to become
    ; a passed over tile by setting bit 7 to 1
    ; for that however we use the previous location rather than the current one
    ; to update the tile behind the player
    lda player_x 
    pha 
    lda player_y 
    pha 

    lda player_x_bac
    sta player_x
    lda player_y_bac
    sta player_y

    jsr update_tile

    ; restore position 
    pla 
    sta player_y
    pla 
    sta player_x
@skip_tile_update:
@player_not_moved:
    jsr update_player_animation

    ; store previous position
    lda player_x 
    sta player_x_bac 
    lda player_y 
    sta player_y_bac

    ; test victory condition
    ; if only one tile is left to clear the player must be on it
    lda tiles_to_clear+1
    cmp #$00 
    bne @done
    lda tiles_to_clear 
    cmp #$01
    bne @done

    ; if animation timer is already going do not prceed
    lda delay_timer
    ora delay_timer+1
    bne @done 

    ; only finish if movment finished as well
    lda smooth_up
    ora smooth_down
    ora smooth_left
    ora smooth_right
    ; bne @done

    ; set up win condition pointers
    sta delay_timer
    lda #$00 
    sta delay_timer+1 ; second byte, we only need first byte
    lda #<empty_sub 
    sta delay_update 
    lda #>empty_sub
    sta delay_update+1

    lda #<update_none 
    sta update_sub
    lda #>update_none 
    sta update_sub+1

    lda #<init_win_condition
    sta delay_done 
    lda #>init_win_condition
    sta delay_done+1
@done:
    jmp update_done

; this sub routine is called when win condition 
; animation finishes
init_win_condition:
    lda #$00
    sta $2001 ; no rendering

    lda #$01 
    sta nametable

    set_nmi_flag

    ldx #GAME_MODE_MESSAGE 
    stx game_mode
    jsr load_menu
    jsr init_message

    lda #$01 ; set flag to skip update
    rts 


; this sub routine updates the player's animation based on 
; the movement offset
; inputs:
;   smooth up, down, left, right
; side effects:
;   modifies registers, flags
;   modifies player sprite and attributes
update_player_animation:
    lda delay_timer ; do not update during delay timer
    bne @done

    lda last_inputs
    and #%11110000
    beq @idle

    ; TODO check for specific keys

@idle 
    lda #$32
    sta sprite_data+1
    lda #$00 
    sta sprite_data+2
@done:
    rts

; checks for player collision based on the currently occupied tile
; inputs:
;   player_x, y and respective _bac 
; side effects:
;   if tile does collide, player position is restored 
;   to values in _bac
;   overwrites src_ptr
; returns:
;   a = 0 -> if collision did not occur
;   a = 1 -> if collision occured
collision_check:
    jsr get_tile
    tax 
    ; get routine for current tile 
    lda tile_sub_lo, x 
    sta src_ptr 
    lda tile_sub_hi, x 
    sta src_ptr+1

    jsr jsr_indirect
    cmp #$01 
    bne @no_collision

    ; if collision, restore previous location
    ; and remove smooth movement
    ldx #$00 
    stx smooth_left 
    stx smooth_right 
    stx smooth_up 
    stx smooth_down

    ldx player_x_bac 
    stx player_x
    ldx player_y_bac
    stx player_y

    jsr convert_tile_location

@no_collision:
    rts 

; this sub routine updates the tiles to clear counter
; it does this based on the negative flag
; inputs:
;   N flag = 0 -> dec
;   N flag = 1 -> inc
; side effects:
;   tiles_to_clear is changed
;   flags may be changed
;   registers are preserved
update_tiles_to_clear:
    pha 
    ; eor sets the negative flag when bit 7 is set
    ; since that is exactly the bit we set we can use it to
    ; decide wheter to inc or dec
    bmi @negative_flag
    lda tiles_to_clear
    clc    
    adc #$01 
    sta tiles_to_clear
    lda tiles_to_clear+1
    adc #$00 
    sta tiles_to_clear+1
    jmp @done
@negative_flag:
    lda tiles_to_clear
    sec 
    sbc #$01 
    sta tiles_to_clear
    lda tiles_to_clear+1
    sbc #$00 
    sta tiles_to_clear+1
@done:
    pla 
    rts 

; this sub routine loads the win screen
; inputs:
;   none
; side effects:
;   inits a new game mode
init_message:
    lda #$00 ; move player offscreen
    sta sprite_data
    sta sprite_data+3
    sta player_x 
    sta player_y
    sta player_x_bac
    sta player_y_bac

    lda #<update_message 
    sta update_sub
    lda #>update_message
    sta update_sub+1

    rts 

; update routine for the win screen
update_message:
    jmp update_done