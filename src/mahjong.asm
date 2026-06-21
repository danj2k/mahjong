; mahjong.asm - BBC Micro Riichi Mahjong v2
; Multi-player: 1 Human (Player 0) + 3 AI opponents
; 
; Tile encoding:
;   0-8   = Man (Manzu) 1-9
;   9-17  = Pin (Pinzu) 1-9
;   18-26 = Sou (Souzu) 1-9
;   27-30 = Winds: East, South, West, North
;   31-33 = Dragons: Hatsu(Green), Haku(White), Chun(Red)
; 
; Display format (two-character stacked):
;   Top row:    1 2 3 4 5 6 7 8 9  (numbers for suited tiles)
;               E S W N T H C      (letters for honor tiles)
;   Bottom row: m m m p p p s s s  (suit letter for suited)
;               w w w w g b r      (w for winds, unique for dragons)
;               g=Hatsu(green) b=Haku(white) r=Chun(red)

oswrch = &FFEE
osnewl = &FFE7
oscli = &FFF7
osrdch = &FFE0
osbyte = &FFF4

TOTAL_TILES = 136
INITIAL_HAND = 13
NUM_PLAYERS = 4
HAND_SIZE = 14
MAX_DISC = 24
MAX_OPEN_MELDS = 4
MELD_SIZE = 5
DEAD_WALL_SIZE = 14
DORA_START = TOTAL_TILES - DEAD_WALL_SIZE

; Tile encoding ranges
TILE_TYPES = 34           ; total number of distinct tile types (0-33)
SUIT_BOUNDARY = 9         ; tiles 0-8 are man, 9-17 are pin, 18-26 are sou
PIN_BOUNDARY = 9          ; pin tiles start at index 9
SOU_BOUNDARY = 18         ; sou tiles start at index 18
HONOR_BOUNDARY = 27       ; tiles 27-33 are honor tiles (winds + dragons)
WIND_BASE = 27            ; wind tiles start at index 27
DRAGON_BASE = 31          ; dragon tiles start at index 31

; AI difficulty thresholds
AI_RIICHI_PAIRS = 3       ; minimum pairs for intermediate riichi
AI_DEFENSE_PENALTY = 20   ; extra value for safe tiles against riichi
AI_OPEN_CALL_MIN = 3      ; minimum tile importance to call open meld

; Zero page
ptr = &70
ptr2 = &72
tmp = &74
tmp2 = &75
tmp3 = &76
tmp4 = &77
tmp5 = &78
tmp6 = &79
tmp7 = &7A
tmp8 = &7B
tmp10 = &7C
tmp11 = &7D
tmp12 = &7E
tmp13 = &7F

; Open call flag - skip draw on next turn
skip_draw = &8E

; Last discarded tile info
disc_tile_val = &8F
; disc_tile_player is in data section (was at &90 Econet zone — unsafe)

; Flag set when human declines closed kan prompt
; kan_declined is in the data section (after player_kans)


; Meld decomposition result storage
; Temp variable for open call routines
tmp9 = &80
no_seq_flag = &81

; Per-player flags (moved from OS zero page &A0-&AB to safe zone)
riichi_declared = &82       ; per-player riichi flag (4 bytes: &82-&85)
ippatsu_flags = &86        ; per-player ippatsu flag (4 bytes: &86-&89)
furiten_flags = &8A        ; per-player furiten flags (4 bytes: &8A-&8D)
; Bit 0: temporary furiten (cleared on draw)
; Bit 1: permanent furiten (set when riichi + discard is winning tile)


; =============================================
ORG &3000
; =============================================

.start
    LDA #22: JSR oswrch
    LDA #7: JSR oswrch
    ; Disable keyboard autorepeat - OSBYTE &0B, X=0 (off), Y=0 (delay)
    LDA #&0B: LDX #0: LDY #0: JSR osbyte
    JSR show_splash
    JSR difficulty_select
    JSR practice_select
    ; Seed RNG from hardware System VIA timer (microsecond counter)
    LDA &FE44: STA rng_seed
    JSR game_init

; --- Main loop ---
.mainloop
    LDA #0: STA tsumo_flag: STA ron_flag
    LDA skip_draw
    BEQ ml_no_skip       ; skip if flag NOT set (forward branch, within range)
    JMP ml_do_skip
.ml_no_skip
    JSR player_draw
    BCC ml_draw_ok    ; if player_draw returned carry clear (OK/false)
    ; Wall exhausted - drawn game
    JSR game_display
    JSR osnewl
    LDY #0
.draw_msg
    LDA drawn_str, Y
    BEQ draw_msg_dn    ; end of string
    JSR oswrch: INY
    JMP draw_msg
.draw_msg_dn
    JSR osnewl
    ; Show "Press any key to continue"
    LDY #0
.pak_drawn
    LDA press_any_key_str, Y: BEQ pak_drawn_dn
    JSR oswrch: INY: JMP pak_drawn
.pak_drawn_dn
    ; Wait for keypress
    JSR osrdch
    ; Drawn game: dealer stays, honba++, hands_played++
    INC honba: INC hands_played
    ; Check game end
    LDA hands_played
    CMP #8    ; check if max hands reached
    BCC draw_new    ; under 8 hands - game continues
    SEC: JMP game_over
.draw_new
    JSR new_round
    BCC draw_ok    ; if new_round returned carry clear (OK/false)
    JMP game_over
.draw_ok
    ; After new round, go to mainloop to draw for the dealer
    JMP mainloop

.ml_draw_ok
    JSR check_tsumo
    BCC ml_not_tsumo    ; if check_tsumo returned carry clear (OK/false)
    ; Check for illegal tsumo (chombo)
    JSR check_chombo_win
    BCC ml_tsumo_valid    ; if check_chombo_win returned carry clear (OK/false)
    ; Invalid tsumo - apply chombo
    LDX current_player: JSR apply_chombo
    JSR advance_player
    JMP mainloop
.ml_tsumo_valid
    INC dbg_tsumo_wins
    LDX current_player
    JSR sort_hand
    JSR game_display
    JSR calculate_score
    ; Brief delay so player can see the game board before result screen
    JSR delay_display
    JSR display_score_result
    JSR award_tsumo
    JSR new_round
    BCC tsumo_ok    ; if new_round returned carry clear (OK/false)
    JMP game_over
.tsumo_ok
    ; After new round, go to mainloop to draw for the dealer
    JMP mainloop

.ml_do_skip
    JMP ml_skip_draw

.ml_not_tsumo
    LDX current_player
    JSR sort_hand
    JSR game_display
    JSR check_closed_kan
    BCS ml_kan_declared    ; if check_closed_kan returned carry set (error/true)
    JSR check_added_kan
    BCS ml_kan_declared    ; if check_added_kan returned carry set (error/true)
    JMP ml_no_kan
.ml_kan_declared
    ; Check for four kans abortive draw
    JSR check_four_kans
    BCC ml_no_abort_k    ; if check_four_kans returned carry clear (OK/false)
    JMP ml_abortive
.ml_no_abort_k
    ; Refresh screen after kan — hand has changed (4 tiles removed, 1 drawn)
    LDX current_player
    JSR sort_hand
    JSR game_display
    ; Check for tsumo after kan replacement draw — player may have won
    JSR check_tsumo
    BCS ml_tsumo_valid    ; win by tsumo after kan
    JMP ml_got_tile
.ml_no_kan
    ; Check riichi for human player
    LDX current_player
    CPX #0    ; check if human player
    BNE ml_got_tile    ; AI player - skip human riichi prompt
    JSR check_riichi_human
    BCC ml_got_tile    ; if check_riichi_human returned carry clear (OK/false)
    ; Riichi declared - check for illegal riichi (chombo)
    JSR check_chombo_riichi
    BCC ml_riichi_ok    ; if check_chombo_riichi returned carry clear (OK/false)
    ; Illegal riichi - apply chombo penalty
    LDX current_player: JSR apply_chombo
    JSR advance_player
    JMP mainloop
.ml_riichi_ok
    ; Riichi declared - auto-discard drawn tile (last in hand)
    LDX num_tiles
    DEX
    JSR player_discard
    JSR check_furiten_after_discard
    JSR check_ron
    BCC ml_no_ron_riichi    ; if check_ron returned carry clear (OK/false)
    JMP ml_ron
.ml_no_ron_riichi
    JSR advance_player
    JMP mainloop

.ml_skip_draw
    LDA #0: STA skip_draw

.ml_got_tile
    LDX current_player
    CPX #0    ; check if human player
    BEQ ml_human    ; human player - go to input handler

    ; AI turn
    JSR sort_hand
    JSR check_riichi_ai
    LDX current_player
    JSR ai_choose_discard
    JSR player_discard
    JSR check_furiten_after_discard
    ; Check for abortive draws after discard
    JSR check_four_winds
    BCC ml_no_abort_a    ; if check_four_winds returned carry clear (OK/false)
    JMP ml_abortive
.ml_no_abort_a
    JSR check_ron
    BCC ml_not_ron    ; if check_ron returned carry clear (OK/false)
    JMP ml_ron
.ml_not_ron
    JSR check_open_calls
    BCS ml_call_made    ; if check_open_calls returned carry set (error/true)
    JSR game_display
    JSR ai_delay
    JSR advance_player
    JMP mainloop

.ml_call_made
    JSR game_display
    JSR ai_delay
    JMP mainloop

.ml_human
    \ sort_hand + game_display moved to ml_not_tsumo so kan/riichi prompts print on fresh board
    JSR human_input
    JSR player_discard
    JSR check_furiten_after_discard
    ; Check for abortive draws after discard
    JSR check_four_winds
    BCC ml_no_abort_h    ; if check_four_winds returned carry clear (OK/false)
    JMP ml_abortive
.ml_no_abort_h
    JSR check_ron
    BCC ml_not_ron_h    ; if check_ron returned carry clear (OK/false)
    JMP ml_ron
.ml_not_ron_h
    JSR check_open_calls
    BCS ml_call_made_h    ; if check_open_calls returned carry set (error/true)
    JSR advance_player
    JMP mainloop

.ml_call_made_h
    JSR game_display
    JMP mainloop

; Abortive draw handler - check routines already display the message and wait for key
.ml_abortive
    INC honba: INC hands_played
    JSR new_round
    BCC abortive_ok    ; if new_round returned carry clear (OK/false)
    JMP game_over
.abortive_ok
    JSR game_display
    JMP mainloop

.ml_tsumo
    ; Check for nine gates before handling win
    JSR check_nine_gates
    BCC ml_not_nine_gates    ; if check_nine_gates returned carry clear (OK/false)
    ; Nine gates win - display special message
    JSR display_nine_gates
    JSR calculate_score
    JSR delay_display
    JSR display_score_result
    JSR award_tsumo
    JSR new_round
    BCC nine_gates_ok    ; if new_round returned carry clear (OK/false)
    JMP game_over
.nine_gates_ok
    JMP mainloop
.ml_not_nine_gates
    LDX current_player
    JSR sort_hand
    JSR game_display
    JSR calculate_score
    JSR delay_display
    JSR display_score_result
    JSR award_ron
    JSR new_round
    BCC ron_ok    ; if new_round returned carry clear (OK/false)
    JMP game_over
.ron_ok
    ; After new round, go to mainloop to draw for the dealer
    JMP mainloop

.ml_ron
    INC dbg_ron_wins
    ; Check for triple ron before handling
    JSR check_triple_ron
    BCC ml_not_triple_ron    ; if check_triple_ron returned carry clear (OK/false)
    ; Triple ron - abortive draw
    JMP ml_abortive
.ml_not_triple_ron
    LDX ron_player: STX current_player
    ; Check for illegal ron (chombo)
    JSR check_chombo_win
    BCC ml_ron_valid    ; if check_chombo_win returned carry clear (OK/false)
    ; Invalid ron - apply chombo
    LDX current_player: JSR apply_chombo
    JSR advance_player
    JMP mainloop
.ml_ron_valid
    LDX current_player
    JSR sort_hand
    JSR game_display
    JSR calculate_score
    JSR delay_display
    JSR display_score_result
    JSR award_ron
    JSR new_round
    BCC ron_continue    ; if new_round returned carry clear (OK/false)
    JMP game_over
.ron_continue
    JMP mainloop

.game_over
    LDA #12: JSR oswrch
    LDY #0
.go_lp
    LDA game_over_str, Y
    BEQ go_dn    ; end of string
    JSR oswrch: INY
    JMP go_lp
.go_dn
    JSR osnewl
    ; Show final scores
    JSR disp_points_line
    JSR osnewl
    ; Find and display the winner (highest points)
    LDX #0: STX tmp5          ; tmp5 = highest player index
    LDX #1                     ; start comparing from player 1
.go_find_lp
    CPX #NUM_PLAYERS    ; compare against NUM_PLAYERS
    BCS go_show_winner    ; all players checked - show winner
    STX tmp6
    TXA: ASL A: TAX         ; X = current player byte offset
    LDY tmp5: TYA: ASL A: TAY  ; Y = highest player byte offset
    LDA player_points+1, X  ; A = current player high byte
    CMP player_points+1, Y  ; compare high bytes
    BCC go_find_next        ; current high < highest high
    BNE go_new_high         ; current high > highest high
    LDA player_points, X    ; high bytes equal - compare low bytes
    CMP player_points, Y    ; compare low bytes
    BCC go_find_next        ; current low < highest low
.go_new_high
    LDX tmp6: STX tmp5      ; update highest to current player
.go_find_next
    LDX tmp6: INX           ; next player
    JMP go_find_lp
.go_show_winner
    LDY #0
.go_w_lp
    LDA winner_str, Y
    BEQ go_w_dn    ; end of string
    JSR oswrch: INY
    JMP go_w_lp
.go_w_dn
    LDX tmp5
    TXA: CLC: ADC #'1'
    JSR oswrch
    JSR osnewl
    JSR osnewl
    LDY #0
.go_pk
    LDA press_key_str, Y
    BEQ go_pk_dn    ; end of string
    JSR oswrch: INY
    JMP go_pk
.go_pk_dn
    JSR osrdch
    ; Reset game and restart
    JSR game_init
    JSR game_display
    JMP mainloop
.quit
    LDA #12: JSR oswrch    ; clear screen
    LDX #<quit_cmd         ; X = low byte of command string address
    LDY #>quit_cmd         ; Y = high byte of command string address
    JSR oscli              ; call OSCLI to return to BASIC
    RTS

; =============================================
; HUMAN INPUT
; Wait for a valid discard key or Q to quit
; Returns position (0-based) in X
; =============================================
.human_input
    ; Wait for a new keypress
    JSR osrdch
    CMP #'Q': BEQ quit
    CMP #'q': BEQ quit
    JSR parse_disc_key
    BCC human_input    ; if parse_disc_key returned carry clear (invalid key)
    ; Check position is within hand size (0-based: valid = 0..num_tiles-1)
    CPX num_tiles: BCC human_input_ok  ; position < num_tiles → valid
    ; Position out of range — beep and ask again
    LDA #7: JSR oswrch
    JMP human_input
.human_input_ok
    RTS

; Parse discard key. Returns C set + position in X, or C clear.
; Keys: Z=0 X=1 C=2 V=3 B=4 N=5 M=6 A=7 S=8 D=9 F=10 G=11 H=12 J=13
.parse_disc_key
    ; Convert lowercase a-z to uppercase A-Z
    CMP #'a': BCC pdck_upper
    CMP #'z'+1: BCS pdck_bad
    SEC: SBC #32               ; 'a'->'A', 'b'->'B', etc.
.pdck_upper
    CMP #'A': BCC pdck_bad    ; below 'A' - not valid
    CMP #'[': BCS pdck_bad    ; above 'Z' - not valid
    SEC: SBC #'A'              ; A=0, B=1, ... Z=25
    TAX
    LDA disc_key_table, X     ; look up discard position
    CMP #$FF: BEQ pdck_bad   ; $FF = not a discard key
    TAX: SEC: RTS             ; C set, position in X
.pdck_bad
    CLC: RTS

; Lookup table: A-Z mapped to discard positions (0-13) or $FF for invalid
.disc_key_table
    EQUB 7    ; A = position 7
    EQUB 4    ; B = position 4
    EQUB 2    ; C = position 2
    EQUB 9    ; D = position 9
    EQUB $FF  ; E = not used
    EQUB 10   ; F = position 10
    EQUB 11   ; G = position 11
    EQUB 12   ; H = position 12
    EQUB $FF  ; I = not used
    EQUB 13   ; J = position 13
    EQUB $FF  ; K = not used
    EQUB $FF  ; L = not used
    EQUB 6    ; M = position 6
    EQUB 5    ; N = position 5
    EQUB $FF  ; O = not used
    EQUB $FF  ; P = not used (used for pon prompt)
    EQUB $FF  ; Q = not used (used for quit)
    EQUB $FF  ; R = not used
    EQUB 8    ; S = position 8
    EQUB $FF  ; T = not used
    EQUB $FF  ; U = not used
    EQUB 3    ; V = position 3
    EQUB $FF  ; W = not used
    EQUB 1    ; X = position 1
    EQUB $FF  ; Y = not used (used for pon/chii prompt)
    EQUB 0    ; Z = position 0

; =============================================
; PRACTICE MODE HINT
; =============================================
; Shows the best discard option for the human player.
; For each tile in hand, counts how many unique wait tiles remain.
; Displays: "Best discard: X (wait for N tiles)"

.practice_hint
    TXA: PHA: TYA: PHA

    ; Find best discard: for each unique tile, count wait tiles after removing it
    LDA #0: STA tmp       ; best_wait_count
    LDA #0: STA tmp2      ; best_discard_index

    LDX #0
.ph_outer
    CPX num_tiles: BCS ph_done
    STX tmp3

    ; Build tile counts, then remove one copy of this tile
    JSR build_tile_counts
    LDY tmp3
    LDA hands, Y: TAX
    LDA tile_counts, X
    SEC: SBC #1
    STA tile_counts, X

    ; Count unique tile types still present (our wait candidates)
    LDY #0: STY tmp6
    LDX #0
.ph_inner
    CPX #TILE_TYPES: BCS ph_inner_dn
    LDA tile_counts, X
    BEQ ph_inner_next    ; no tiles of this type - skip
    INC tmp6
.ph_inner_next
    INX: JMP ph_inner
.ph_inner_dn

    ; Compare with best
    LDA tmp6
    CMP tmp: BCC ph_skip
    BEQ ph_skip    ; zero - condition met
    STA tmp
    LDA tmp3: STA tmp2
.ph_skip
    JSR build_tile_counts
    LDX tmp3
    INX: JMP ph_outer

.ph_done
    JSR osnewl
    LDY #0
.ph_hdr_lp
    LDA ph_hdr_str, Y
    BEQ ph_hdr_dn    ; end of string
    JSR oswrch: INY
    JMP ph_hdr_lp
.ph_hdr_dn
    LDX tmp2
    LDA hands, X
    JSR tile_num_char: JSR oswrch
    LDA hands, X
    JSR tile_suit_char: JSR oswrch
    LDY #0
.ph_mid_lp
    LDA ph_mid_str, Y
    BEQ ph_mid_dn    ; end of string
    JSR oswrch: INY
    JMP ph_mid_lp
.ph_mid_dn
    LDA tmp
    ; Print wait count as 1-2 digits
    CMP #10: BCS ph_two_digit
    CLC: ADC #'0': JSR oswrch
    LDY #0
    JMP ph_end_lp
.ph_two_digit
    ; Divide by 10 for tens digit
    LDY #0
.ph_div10
    SEC: SBC #10: INY: CMP #10: BCS ph_div10
    ; A = units, Y = tens
    PHA
    TYA: CLC: ADC #'0': JSR oswrch  ; tens digit
    PLA
    CLC: ADC #'0': JSR oswrch       ; units digit
    LDY #0
.ph_end_lp
    LDA ph_end_str, Y
    BEQ ph_end_dn    ; end of string
    JSR oswrch: INY
    JMP ph_end_lp
.ph_end_dn
    JSR osnewl
    PLA: TAY: PLA: TAX
    RTS

.ph_hdr_str
    EQUS "Best discard: ", 0
.ph_mid_str
    EQUS " (wait for ", 0
.ph_end_str
    EQUS " tiles)", 0

; =============================================
; TURN MANAGEMENT
; =============================================

.advance_player
    INC current_player
    LDA current_player
    CMP #NUM_PLAYERS    ; check if past last player
    BNE ap_dn    ; not zero - condition not met
    LDA #0: STA current_player
.ap_dn
    RTS

; AI delay - ~4M cycles per call (~2s at 2MHz)
; Triple-nested: 12 x 256 x 256 x 5 ~ 4M cycles
; Three AI turns x 4M ~ 12M total > 5M type_input hold
.ai_delay
    LDA #12
    STA tmp7
.adl1
    LDX #0
.adl2
    LDY #0
.adl3
    DEY
    BNE adl3    ; inner delay not done
    DEX
    BNE adl2    ; middle delay not done
    DEC tmp7
    BNE adl1    ; outer delay not done
    RTS

; =============================================
; DIFFICULTY SELECTION
; =============================================
; Display difficulty menu and read player choice.
; Stores result in ai_difficulty (0=novice, 1=intermediate, 2=expert).

.difficulty_select
    ; Clear screen
    LDA #12: JSR oswrch
    ; Display menu title
    LDY #0
.ds_title_lp
    LDA diff_title, Y
    BEQ ds_title_dn    ; end of string
    JSR oswrch: INY
    JMP ds_title_lp
.ds_title_dn
    JSR osnewl: JSR osnewl
    ; Display option 1: Novice
    LDY #0
.ds_opt1_lp
    LDA diff_novice, Y
    BEQ ds_opt1_dn    ; end of string
    JSR oswrch: INY
    JMP ds_opt1_lp
.ds_opt1_dn
    JSR osnewl
    ; Display option 2: Intermediate
    LDY #0
.ds_opt2_lp
    LDA diff_inter, Y
    BEQ ds_opt2_dn    ; end of string
    JSR oswrch: INY
    JMP ds_opt2_lp
.ds_opt2_dn
    JSR osnewl
    ; Display option 3: Expert
    LDY #0
.ds_opt3_lp
    LDA diff_expert, Y
    BEQ ds_opt3_dn    ; end of string
    JSR oswrch: INY
    JMP ds_opt3_lp
.ds_opt3_dn
    JSR osnewl: JSR osnewl
    ; Display prompt
    LDY #0
.ds_prompt_lp
    LDA diff_prompt, Y
    BEQ ds_prompt_dn    ; end of string
    JSR oswrch: INY
    JMP ds_prompt_lp
.ds_prompt_dn
    ; Wait for keypress
    JSR osrdch
    ; Check 1, 2, 3
    CMP #'1': BEQ ds_novice
    CMP #'2': BEQ ds_intermediate
    CMP #'3': BEQ ds_expert
    ; Invalid - try again
    JMP ds_prompt_dn
.ds_novice
    LDA #0: STA ai_difficulty
    JMP ds_done
.ds_intermediate
    LDA #1: STA ai_difficulty
    JMP ds_done
.ds_expert
    LDA #2: STA ai_difficulty
.ds_done
    RTS

; =============================================
; PRACTICE MODE SELECTION
; =============================================
; Display practice mode menu after difficulty selection.
; Stores result in practice_mode (0=off, 1=on).
; Shows hints about optimal discards when enabled.

.practice_select
    ; Clear screen
    LDA #12: JSR oswrch
    ; Display title
    LDY #0
.ps_title_lp
    LDA pract_title, Y
    BEQ ps_title_dn    ; end of string
    JSR oswrch: INY
    JMP ps_title_lp
.ps_title_dn
    JSR osnewl: JSR osnewl
    ; Display option 1: Off
    LDY #0
.ps_opt1_lp
    LDA pract_off, Y
    BEQ ps_opt1_dn    ; end of string
    JSR oswrch: INY
    JMP ps_opt1_lp
.ps_opt1_dn
    JSR osnewl
    ; Display option 2: On
    LDY #0
.ps_opt2_lp
    LDA pract_on, Y
    BEQ ps_opt2_dn    ; end of string
    JSR oswrch: INY
    JMP ps_opt2_lp
.ps_opt2_dn
    JSR osnewl: JSR osnewl
    ; Display prompt
    LDY #0
.ps_prompt_lp
    LDA pract_prompt, Y
    BEQ ps_prompt_dn    ; end of string
    JSR oswrch: INY
    JMP ps_prompt_lp
.ps_prompt_dn
    ; Wait for keypress
    JSR osrdch
    ; Check 1, 2
    CMP #'1': BEQ ps_off
    CMP #'2': BEQ ps_on
    ; Invalid - try again
    JMP ps_prompt_dn
.ps_off
    LDA #0: STA practice_mode
    RTS
.ps_on
    LDA #1: STA practice_mode
    RTS

; =============================================
; ADVANCE ROUND
; =============================================
; Called after each hand ends (tsumo/ron).
; Updates dealer, seat winds, hands_played.
; Returns: C set = game over, C clear = continue.
; 
; Rules:
; - Dealer won: dealer stays, hands_played++
; - Non-dealer won: dealer advances, hands_played++
; - Draw: dealer stays, hands_played++, honba++
; - Game ends after 8 hands (South 4) unless dealer won
;   (dealer repeat extends the game)

.advance_round
    ; Increment hands_played
    INC hands_played

    ; Determine if it was a draw (wall exhausted)
    LDA tsumo_flag
    ORA ron_flag
    BEQ ar_draw    ; no winner - it was a draw

    ; Was a win - check if dealer won
    LDA tsumo_flag
    BNE ar_tsumo    ; self-draw win - get winner
    ; Ron: winner = ron_player
    LDX ron_player
    JMP ar_got_winner
.ar_tsumo
    ; Tsumo: winner = current_player
    LDX current_player
.ar_got_winner
    ; Check if winner is dealer
    CPX dealer    ; compare against dealer
    BEQ ar_dealer_won    ; winner is dealer - stay as dealer

    ; Non-dealer won: advance dealer, reset honba
    LDA #0: STA honba
    LDX dealer
    INX
    CPX #NUM_PLAYERS    ; compare against NUM_PLAYERS
    BNE ar_no_wrap    ; no wrap needed
    LDX #0
.ar_no_wrap
    STX dealer
    JMP ar_update_seats

.ar_dealer_won
    ; Dealer won: stay as dealer, increment honba
    INC honba
    JMP ar_update_seats

.ar_draw
    ; Draw: dealer stays, honba++
    INC honba

.ar_update_seats
    ; Calculate seat winds: dealer=East, then clockwise
    LDX #0
.ar_seat_lp
    TXA: CLC: ADC dealer
    CMP #NUM_PLAYERS    ; check if all 4 players dealt
    BCC ar_no_wrap2    ; carry clear
    SEC: SBC #NUM_PLAYERS
.ar_no_wrap2
    TAY                         ; Y = position relative to dealer
    TXA: CLC: ADC #27          ; East + offset
    STA seat_winds, Y
    INX
    CPX #NUM_PLAYERS    ; compare against NUM_PLAYERS
    BNE ar_seat_lp    ; more players to assign seat winds

    ; Check for game end
    ; Game ends when hands_played >= 8 (completed South 4)
    ; unless the dealer just won (extends by one more hand)
    LDA hands_played
    CMP #8    ; check if max hands reached
    BCC ar_not_over            ; less than 8 hands: continue

    ; 8+ hands played - check if dealer won (extends game)
    LDA tsumo_flag
    ORA ron_flag
    BEQ ar_not_over           ; draw doesn't extend
    LDX #0
    LDA tsumo_flag
    BNE ar_chk_winner    ; tsumo win - check if dealer won
    LDX ron_player
    JMP ar_chk_dealer
.ar_chk_winner
    LDX current_player
.ar_chk_dealer
    CPX dealer    ; compare against dealer
    BEQ ar_not_over           ; dealer won: extend game

    ; Non-dealer won at 8+ hands: game over
    SEC
    RTS

.ar_not_over
    ; Safety: end game at 12 hands maximum (South All-Stars limit)
    LDA hands_played
    CMP #12    ; check absolute maximum hands
    BCC ar_continue    ; under the hard limit - continue game
    SEC
    RTS

.ar_continue
    CLC
    RTS

; =============================================
; GAME INITIALIZATION
; =============================================


; =============================================
; RIICHI DECLARATION
; =============================================
; Check if human player can declare riichi.
; Conditions: closed hand (no open melds), 1000+ points, not already declared.
; If eligible, prompts Y/N and deducts 1000 points + places riichi stick.
; Returns: C set = riichi declared, C clear = no riichi.

; =============================================
; CHOMBO CHECK ROUTINES
; =============================================
; Quick checks for illegal plays.
; Returns C set if chombo detected.

; Check for illegal riichi
; Returns C set if riichi declared with open hand
.check_chombo_riichi
    LDX current_player
    LDA riichi_declared, X
    BEQ ccri_not_riichi    ; player hasn't declared riichi
    LDA opn_count, X
    BEQ ccri_valid    ; hand is closed - riichi valid
    ; Riichi with open hand = chombo
    SEC: RTS
.ccri_not_riichi
    CLC: RTS
.ccri_valid
    CLC: RTS

; Check for illegal win (tsumo or ron)
; Returns C set if win declared on invalid hand
;
; For tsumo: the drawn tile is already in the hand, so check_win
;   rebuilds tile_counts correctly from the hand array.
; For ron: the discarded tile is NOT in the hand, so we must
;   temporarily add disc_tile_val to tile_counts before check_win,
;   then restore it afterwards.
.check_chombo_win
    ; Build tile counts from current player's hand first
    JSR build_tile_counts
    LDA tsumo_flag: BNE ccmw_tsumo
    ; Ron path — the discarded tile is NOT in the hand, so add it
    ; to tile_counts before checking for a winning decomposition
    LDY disc_tile_val: TYA: TAX
    LDA tile_counts, X: CLC: ADC #1: STA tile_counts, X
    JSR check_win_no_rebuild
    PHP                      ; save carry (win result) before restore
    ; Restore tile_counts
    LDY disc_tile_val: TYA: TAX
    LDA tile_counts, X: SEC: SBC #1: STA tile_counts, X
    PLP                      ; restore carry (win result)
    BCS ccmw_valid    ; if check_win_no_rebuild found a win
    ; Invalid win = chombo
    SEC: RTS
.ccmw_tsumo
    ; Tsumo path — drawn tile IS already in the hand, check_win works
    JSR check_win
    BCS ccmw_valid    ; if check_win found a win
    ; Invalid win = chombo
    SEC: RTS
.ccmw_valid
    CLC: RTS

.check_riichi_human
    ; Already declared?
    LDX current_player
    LDA riichi_declared, X
    BNE crh_no    ; already declared riichi

    ; Must have closed hand (no open melds)
    LDA opn_count, X
    BNE crh_open    ; hand is open - riichi not allowed

    ; Must have 1000+ points
    TXA: ASL A: TAX
    LDA player_points+1, X
    CMP #>1000    ; compare against >1000
    BCC crh_nopoints    ; not enough points for riichi
    BNE crh_enough    ; high byte larger - definitely enough
    LDA player_points, X
    CMP #<1000    ; compare against <1000
    BCC crh_nopoints    ; not enough points for riichi
.crh_enough

    ; Display riichi prompt
    JSR riichi_display_prompt

    ; Read Y/N key to declare riichi
    JSR osrdch
    CMP #'Y': BEQ crh_declare
    CMP #'y': BEQ crh_declare
    ; User said no — clear prompt immediately
    JSR clear_prompt_line

.crh_no
    CLC: RTS

.crh_open
    ; Could display "Must be closed!" but skip for now
    JMP crh_no

.crh_nopoints
    ; Could display "Need 1000+ pts!" but skip for now
    JMP crh_no

.crh_declare
    ; Deduct 1000 points from player
    LDX current_player
    TXA: ASL A: TAX
    LDA player_points, X
    SEC: SBC #<1000
    STA player_points, X
    LDA player_points+1, X
    SBC #>1000
    STA player_points+1, X

    ; Place riichi stick on table
    LDX current_player
    LDA #1
    STA riichi_declared, X
    LDA riichi_on_table
    CLC: ADC #1
    STA riichi_on_table

    ; Set ippatsu flag (bonus if win within one full rotation)
    LDX current_player
    LDA #1
    STA ippatsu_flags, X

    ; Check permanent furiten for riichi
    JSR check_furiten_for_player

    ; Display RIICHI message
    LDA #12: JSR oswrch
    LDY #0
.crh_msg
    LDA riichi_msg, Y
    BEQ crh_msg_dn    ; end of string
    JSR oswrch: INY
    JMP crh_msg
.crh_msg_dn
    JSR osnewl
    ; Brief pause
    LDX #0: LDY #0
.crh_pause
    DEY: BNE crh_pause
    DEX: BNE crh_pause

    SEC: RTS

; Check if AI player can declare riichi.
; AI always declares if eligible (closed hand + 1000+ pts).
.check_riichi_ai
    LDX current_player
    ; Already declared?
    LDA riichi_declared, X
    BEQ cra_check_open    ; not yet declared - check hand
    JMP cra_no            ; already declared: can't riichi again
.cra_check_open
    ; Must have closed hand
    LDA opn_count, X
    BEQ cra_open_ok       ; hand is closed: proceed
    JMP cra_no            ; open hand: can't riichi
.cra_open_ok
    ; Novice: never declare riichi
    LDA ai_difficulty
    BNE cra_not_novice
    JMP cra_no
.cra_not_novice

    ; Intermediate/Expert: evaluate hand strength before riichi
    STX tmp5
    JSR build_tile_counts
    LDY #0: STY tmp6    ; tmp6 = pair count
    LDY #0: STY tmp8    ; tmp8 = sequence count
.cra_count_lp
    CPY #TILE_TYPES: BCS cra_count_done
    LDA tile_counts, Y
    CMP #2
    BCC cra_count_next
    INC tmp6             ; pair or triplet found
    ; Check for potential sequence: Y, Y+1, Y+2 all present
    ; Must be same suit - exclude boundaries (7,8 / 16,17 / 25,26+)
    CPY #7: BEQ cra_count_next
    CPY #8: BEQ cra_count_next
    CPY #16: BEQ cra_count_next
    CPY #17: BEQ cra_count_next
    CPY #25: BCS cra_count_next
    LDA tile_counts+1, Y
    BEQ cra_count_next
    LDA tile_counts+2, Y
    BEQ cra_count_next
    INC tmp8
.cra_count_next
    INY
    JMP cra_count_lp
.cra_count_done
    LDX tmp5

    ; Hand strength = pairs*3 + sequences*5
    LDA tmp6
    ASL A: CLC: ADC tmp6  ; *3
    STA tmp10
    LDA tmp8
    ASL A: ASL A: CLC: ADC tmp8  ; *5
    CLC: ADC tmp10
    STA tmp10             ; tmp10 = total strength

    ; Expert: need strength >= 10
    LDA ai_difficulty
    CMP #2: BNE cra_inter_str
    LDA tmp10
    CMP #10
    BCC cra_no            ; hand too weak
    JMP cra_check_extra
.cra_inter_str
    ; Intermediate: need strength >= 8
    LDA tmp10
    CMP #8
    BCC cra_no            ; hand too weak

.cra_check_extra
    ; Skip riichi if any opponent has already declared (risky into riichi battle)
    LDY #0
.cra_opp_lp
    CPY #NUM_PLAYERS: BCS cra_opp_done
    CPY current_player: BEQ cra_opp_next
    LDA riichi_declared, Y
    BNE cra_no            ; opponent riichi: too risky
.cra_opp_next
    INY
    JMP cra_opp_lp
.cra_opp_done

    ; Skip if wall <= 15 tiles (too late in the game)
    LDA #DORA_START
    SEC: SBC wall_pos
    CMP #16
    BCC cra_no

    ; Intermediate/Expert need 3000+ points (cushion for the 1000 investment)
    LDX tmp5
    TXA: ASL A: TAX
    LDA player_points+1, X
    CMP #>3000
    BCC cra_no
    BNE cra_enough
    LDA player_points, X
    CMP #<3000
    BCC cra_no
    JMP cra_enough
.cra_enough

    ; Deduct 1000 points
    LDX current_player
    TXA: ASL A: TAX
    LDA player_points, X
    SEC: SBC #<1000
    STA player_points, X
    LDA player_points+1, X
    SBC #>1000
    STA player_points+1, X

    ; Set riichi flags
    LDX current_player
    LDA #1
    STA riichi_declared, X
    STA ippatsu_flags, X
    LDA riichi_on_table
    CLC: ADC #1
    STA riichi_on_table

    ; Check permanent furiten for riichi
    JSR check_furiten_for_player

.cra_no
    RTS

; Display riichi prompt for human player at fixed row
.riichi_display_prompt
    JSR clear_prompt_line
    LDY #0
.rdp_lp
    LDA riichi_ask, Y
    BEQ rdp_dn    ; end of string
    JSR oswrch: INY
    JMP rdp_lp
.rdp_dn
    RTS

; =============================================
; CLOSED KAN AND ADDED KAN
; =============================================
; Per Turn Sequence: CHECK CLOSED KAN, CHECK ADDED KAN
; Called after tsumo check, before riichi declaration.
; Returns: C set = kan declared (player needs to discard), C clear = no kan.

; Check if current player can declare a closed kan (4 of same tile in hand).
; For AI: always declares. For human: prompts Y/N.
; Returns C set if kan declared.
.check_closed_kan
    ; If human previously declined, don't re-prompt
    LDX current_player
    CPX #0    ; check if human player
    BNE cck_start    ; not human - always proceed
    LDA kan_declined
    BNE cck_no    ; declined earlier - skip
.cck_start
    LDX current_player
    JSR build_tile_counts
    LDY #0             ;\ Y = tile index to scan

.cck_scan
    CPY #TILE_TYPES: BCS cck_no
    LDA tile_counts, Y
    CMP #4    ; check if count is 4
    BCC cck_next    ; fewer than 4 - no kan possible

    ; Found 4 of tile Y! Check if this is a valid closed kan
    ; (tile must be in hand, not already part of open meld)
    ; Since we built tile_counts from the hand, all 4 are in hand

    ; For AI player: auto-declare
    LDX current_player
    CPX #0    ; check if human player
    BEQ cck_human_ask    ; zero - condition met
    JSR execute_closed_kan
    SEC: RTS

.cck_human_ask
    ; Y = tile index from scan loop. Save it first.
    STY tmp9
    ; Display "Declare Closed Kan" prompt at fixed row
    JSR clear_prompt_line
    LDY #0
.cck_prompt_lp
    LDA closed_kan_ask, Y
    BEQ cck_prompt_dn    ; end of string
    JSR oswrch: INY
    JMP cck_prompt_lp
.cck_prompt_dn
    ; Show which tile: " tile "
    LDA #' ': JSR oswrch
    LDA tmp9: JSR tile_num_char: JSR oswrch
    LDA tmp9: JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    ; Wait for Y/N key to declare kan
    JSR osrdch
    CMP #'Y': BEQ cck_do_it
    CMP #'y': BEQ cck_do_it
    ; User said no — clear prompt, set flag, continue scanning
    JSR clear_prompt_line
    LDA #1: STA kan_declined
    LDY tmp9
    JMP cck_next    ; Y = tmp9, then INY + JMP cck_scan

.cck_do_it
    LDY tmp9              ; restore tile index (Y was clobbered by prompt printing)
    JSR execute_closed_kan
    SEC: RTS

.cck_next
    INY
    JMP cck_scan

.cck_no
    CLC: RTS

; Execute closed kan: remove 4 tiles from hand, create meld, draw replacement.
; Y = tile index (0-33) of the 4-of-a-kind.
.execute_closed_kan
    STY tmp5             ;\ save tile index
    ; Create open meld record
    LDX current_player
    TXA: ASL A: ASL A
    STA tmp6
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp6: STA tmp6   ;\ tmp6 = player * 20
    LDY opn_count, X
    STY tmp7             ;\ save count for *5 calculation
    TYA: ASL A: ASL A    ;\ * 4
    CLC: ADC tmp7         ;\ + count = * 5
    CLC: ADC tmp6         ;\ + player * 20
    TAX                   ;\ X = offset into opn_melds
    ; Store meld: type 3 (closed kan), tile1, tile2, tile3, tile4
    LDA #3: STA opn_melds, X
    LDA tmp5
    STA opn_melds+1, X
    STA opn_melds+2, X
    STA opn_melds+3, X
    STA opn_melds+4, X
    ; Increment meld count
    LDX current_player
    INC opn_count, X

    ; Remove 4 copies of the kan tile from hand
    ; Note: ep_remove_at clobbers tmp6, so use tmp7 for tile value
    LDA tmp5: STA tmp7   ;\\ tmp7 = tile value (survives ep_remove_at)
    LDA #4: STA tmp8     ;\\ tmp8 = tiles remaining to remove
.cck_rm_lp
    LDX current_player
    JSR set_hand_ptr     ;\\ ptr = hand base (clobbers tmp5)
    LDY #0
.cck_rm_find
    LDA (ptr), Y
    CMP tmp7: BNE cck_rm_nxt
    JSR ep_remove_at     ;\\ remove tile at Y, shift hand left, DEC num_tiles
    DEC tmp8
    BNE cck_rm_lp        ;\\ more tiles to remove
    JMP cck_rm_done
.cck_rm_nxt
    INY
    ; Bounds check: if Y >= num_tiles, scan is complete
    STY tmp4
    LDX current_player
    LDA num_tiles, X
    CMP tmp4    ;\\ num_tiles - Y
    BCC cck_rm_dn   ;\\ if num_tiles < Y, past end of hand
    BEQ cck_rm_dn   ;\\ if num_tiles = Y, at end of hand
    JMP cck_rm_find ;\\ still within hand - keep searching
.cck_rm_dn
    ; Hand exhausted - check if all tiles were found
    LDA tmp8: BEQ cck_rm_done    ;\\ all 4 tiles removed, proceed
    ; Not enough tiles - proceed anyway (removals are irreversible)
.cck_rm_done

    ; Draw replacement from dead wall (rinshan draw)
    LDA dora_count
    CLC: ADC #DORA_START
    TAX
    LDA wall, X          ; draw from end of dead wall
    PHA
    LDX current_player
    JSR set_hand_ptr
    PLA
    LDY num_tiles, X
    CPY #HAND_SIZE
    BCS cck_no_draw      ; hand full, skip draw (safety)
    STA (ptr), Y
    INC num_tiles, X
.cck_no_draw

    ; Reveal new dora indicator
    JSR reveal_dora
    ; Increment per-player kans count and four kans counter
    LDX current_player
    INC player_kans, X
    INC four_kans_count
    RTS

; Check if current player can declare an added kan (4th tile for an open pon).
.check_added_kan
    LDX current_player
    LDA opn_count, X
    BEQ cak_no    ; no open melds to add kan to
    JMP cak_check
.cak_no
    CLC: RTS
.cak_check

    ; Build tile counts from hand
    JSR build_tile_counts

    ; For each open meld, check if it's a pon (type 1)
    ; and if player has a matching tile in hand
    LDX current_player
    TXA: ASL A: ASL A
    STA tmp6
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp6: STA tmp6   ;\ tmp6 = player * 20
    LDX current_player
    LDY opn_count, X
    BEQ cak_no    ; no open melds to add kan to
    STY tmp7            ;\ tmp7 = meld count

.cak_scan
    DEY
    STY tmp5
    TYA: ASL A: ASL A: CLC: ADC tmp5
    CLC: ADC tmp6: TAX
    LDA opn_melds, X    ;\ type byte at offset +0
    CMP #1: BNE cak_next ;\ only check pons (type 1)
    INX
    LDA opn_melds, X    ;\ tile value of pon
    TAY
    LDA tile_counts, Y
    BEQ cak_next        ;\ player doesn't have it
    ; Player has the 4th tile! Check if AI or human

    LDX current_player
    CPX #0    ; check if human player
    BEQ cak_human_ask    ; zero - condition met

    ; AI: auto-declare
    JSR execute_added_kan
    SEC: RTS

.cak_human_ask
    ; tmp8 = tile value from scan. Save it.
    ; Display "Declare Added Kan" prompt at fixed row
    JSR clear_prompt_line
    LDY #0
.cak_prompt_lp
    LDA added_kan_ask, Y
    BEQ cak_prompt_dn    ; end of string
    JSR oswrch: INY
    JMP cak_prompt_lp
.cak_prompt_dn
    ; Show which tile: " tile "
    LDA #' ': JSR oswrch
    LDA tmp8: JSR tile_num_char: JSR oswrch
    LDA tmp8: JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    ; Wait for Y/N key to declare kan
    JSR osrdch
    CMP #'Y': BEQ cak_do_it
    CMP #'y': BEQ cak_do_it
    ; User said no — clear prompt and continue scanning
    JSR clear_prompt_line
    JMP cak_next

.cak_do_it
    JSR execute_added_kan
    SEC: RTS

.cak_next
    LDY tmp5
    CPY #0: BNE cak_scan

    CLC: RTS

; Execute added kan: remove tile from hand, update pon to kan, draw replacement.
.execute_added_kan
    ; First, find the pon meld to update
    LDX current_player
    TXA: ASL A: ASL A
    STA tmp6
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp6: STA tmp6
    LDX current_player
    LDY opn_count, X
    STY tmp7
.eak_meld_lp
    DEY
    STY tmp5
    TYA: ASL A: ASL A: CLC: ADC tmp5
    CLC: ADC tmp6: TAX
    LDA opn_melds, X    ;\ type byte at offset +0
    CMP #1: BNE eak_meld_next  ;\ skip non-pons
    INX
    LDA opn_melds, X    ;\ tile value
    STA tmp8             ;\ save tile value

    ; Check if this pon's tile is in hand
    PHA
    LDX current_player
    JSR build_tile_counts
    PLA
    TAY
    LDA tile_counts, Y
    BEQ eak_meld_next   ;\ not in hand
    ; Found it! Update meld type to 4 (added kan)
    ; Recalculate offset
    LDX current_player
    TXA: ASL A: ASL A
    STA tmp6
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp6: STA tmp6
    LDY tmp5
    TYA: ASL A: ASL A: CLC: ADC tmp5
    CLC: ADC tmp6: TAX
    LDA #4: STA opn_melds, X  ;\ type 4 = added kan

    ; Remove one copy of tile from hand
    JSR set_hand_ptr
    LDY #0
.eak_rm_find
    LDA (ptr), Y
    CMP tmp8: BNE eak_rm_nxt
    JSR ep_remove_at
    JMP eak_draw
.eak_rm_nxt
    INY
    STY tmp4
    LDX current_player
    LDA num_tiles, X
    CMP tmp4    ; check if past end of hand
    BCS eak_rm_find    ; still within hand - keep scanning
    JMP eak_draw

.eak_meld_next
    LDY tmp5
    CPY #0: BNE eak_meld_lp
    CLC: RTS

.eak_draw
    ; Draw replacement from dead wall (rinshan draw)
    LDA dora_count
    CLC: ADC #DORA_START
    TAX
    LDA wall, X
    PHA
    LDX current_player
    JSR set_hand_ptr
    PLA
    LDY num_tiles, X
    CPY #HAND_SIZE
    BCS eak_no_draw      ; hand full, skip draw (safety)
    STA (ptr), Y
    INC num_tiles, X
.eak_no_draw

    ; Reveal new dora indicator
    JSR reveal_dora
    ; Increment per-player kans count and four kans counter
    LDX current_player
    INC player_kans, X
    INC four_kans_count
    SEC: RTS

; Reveal next dora indicator from dead wall.
.reveal_dora
    INC dora_count
    LDA dora_count
    CLC: ADC #DORA_START
    TAX
    LDA wall, X
    STA dora_indicator
    RTS


; =============================================
; FURITEN DETECTION
; =============================================
; Two forms of furiten:
; - Temporary: after discard, if your discard + your hand = winning hand,
;   you are in temporary furiten until you draw again.
; - Permanent: when declaring riichi, if any of your discards + your hand
;   = winning hand, you are permanently in furiten for the rest of the hand.
; A player in furiten cannot win by ron (only tsumo).

; check_furiten_for_player:
; Tests all discards of player in X against their hand.
; If any discard + hand = winning hand:
;   If player is in riichi -> set permanent furiten (bit 1)
;   Otherwise -> set temporary furiten (bit 0)
; Preserves X on entry.
.check_furiten_for_player
    STX tmp5                 ; save player index
    JSR build_tile_counts    ; build counts for this player hand
    ; Check each discard
    JSR set_disc_ptr
    LDY num_discards, X
    BEQ cff_done    ; no discards to test for furiten
    STY tmp8                 ; tmp8 = number of discards
.cff_loop
    DEY
    STY tmp4                 ; save discard index
    ; Temporarily add discard tile to counts
    LDA (ptr), Y
    TAX
    INC tile_counts, X
    ; Check if this forms a winning hand
    JSR check_win_no_rebuild
    ; Remove the temporary tile
    LDY tmp4
    LDA (ptr), Y
    TAX
    DEC tile_counts, X
    BCS cff_found    ; discard + hand forms winning hand - furiten!
    LDY tmp4
    CPY #0    ; compare against zero
    BNE cff_loop    ; more discards to test
    JMP cff_done
.cff_found
    ; Player is in furiten - set appropriate flag
    LDX tmp5
    LDA riichi_declared, X
    BNE cff_set_perm    ; player is in riichi - permanent furiten
    ; Set temporary furiten (bit 0)
    LDA furiten_flags, X
    ORA #1
    STA furiten_flags, X
    JMP cff_done
.cff_set_perm
    ; Set permanent furiten (bit 1)
    LDA furiten_flags, X
    ORA #2
    STA furiten_flags, X
.cff_done
    LDX tmp5                 ; restore player index
    RTS

; check_furiten_after_discard:
; Called after a discard to update furiten status for the discarder.
.check_furiten_after_discard
    LDX current_player
    JSR check_furiten_for_player
    RTS

.game_init
    JSR wall_build
    JSR wall_shuffle
    JSR deal_all
    ; Reveal initial dora indicator from dead wall
    LDA wall+DORA_START
    STA dora_indicator
    LDA #0: STA dora_count
    LDA #0: STA current_player
    LDA #0: STA dealer: STA hands_played
    ; Initialize seat winds - player 0 is East initially
    LDA #27: STA seat_winds
    LDA #28: STA seat_winds+1
    LDA #29: STA seat_winds+2
    LDA #30: STA seat_winds+3
    ; Initialize points to 25000 for each player
    LDX #0
.gi_pts
    TXA: ASL A: TAY
    LDA #<25000: STA player_points, Y
    LDA #>25000: STA player_points+1, Y
    INX: CPX #NUM_PLAYERS: BNE gi_pts
    LDA #0: STA honba
    LDX #0
.gi_rs
    STA riichi_sticks, X
    INX: CPX #NUM_PLAYERS: BNE gi_rs
    STA riichi_on_table
    LDX #0
.gi_ri
    STA riichi_declared, X
    STA ippatsu_flags, X
    STA furiten_flags, X
    INX: CPX #NUM_PLAYERS: BNE gi_ri
    LDA #0: STA skip_draw
    LDX #0
.gi_opn
    STA opn_count, X
    INX: CPX #NUM_PLAYERS: BNE gi_opn
    ; Initialize abortive draw counters
    LDA #0
    STA first_disc_winds
    STA first_disc_winds+1
    STA first_disc_winds+2
    STA first_disc_winds+3
    STA four_kans_count
    ; Reset chombo counts
    LDX #0
.gi_ch
    STA chombo_count, X
    INX: CPX #NUM_PLAYERS: BNE gi_ch
    ; Reset per-player kans count
    LDX #0
.gi_kans
    STA player_kans, X
    INX: CPX #NUM_PLAYERS: BNE gi_kans
    ; Reset yakuman flags
    STA yakuman_flags
    STA yakuman_flags2
    ; Reset first turn flag
    LDA #1: STA first_turn
    RTS
; =============================================
; WALL OPERATIONS
; =============================================

.wall_build
    LDX #0: LDY #0
.wb_lp
    TYA: STA wall, X
    INX
    TXA: AND #3: BNE wb_lp
    INY: CPY #TILE_TYPES: BNE wb_lp
    RTS

.wall_shuffle
    LDX #TOTAL_TILES-1
.ws_lp
    CPX #0: BEQ ws_dn
    JSR rng
    CMP #TOTAL_TILES: BCS ws_lp
    TAY
    LDA wall, X: PHA
    LDA wall, Y: STA wall, X
    PLA: STA wall, Y
    DEX: JMP ws_lp
.ws_dn
    RTS

.rng
    ; 8-bit LCG PRNG: seed = (seed * 5 + 7) mod 256
    ; Full period 256 (Hull-Dobell: gcd(7,256)=1, 5-1=4 div by 2 and 4)
    ; Previous xorshift had period only 15 - wall shuffles repeated every 4 hands
    LDA rng_seed
    STA tmp            ; save seed
    ASL A              ; A = 2*seed
    ASL A              ; A = 4*seed
    CLC
    ADC tmp            ; A = 5*seed
    CLC
    ADC #7             ; A = 5*seed + 7
    STA rng_seed
    RTS

; =============================================
; DEALING
; =============================================

.deal_all
    ; Deal 13 tiles per player using hand_bases table
    ; (old linear copy misaligned Player 3's hand)
    LDA #0: STA tmp            ;\ tmp = wall position
    LDX #0                     ;\ X = player counter
.da_player
    TXA: PHA                   ;\ save player counter (X) on stack
    JSR set_hand_ptr           ;\ ptr = hand_bases[X], preserves X
    LDY #0                     ;\ Y = tile position in hand
.da_tile
    STY tmp2                   ;\ save tile position
    LDY tmp                    ;\ Y = wall position
    LDA wall, Y                ;\ get tile from wall
    INC tmp                    ;\ advance wall position
    LDY tmp2                   ;\ restore tile position
    STA (ptr), Y               ;\ store tile in player's hand
    INY
    CPY #INITIAL_HAND          ;\ done 13 tiles?
    BNE da_tile    ; not zero - condition not met
    PLA: TAX                   ;\ restore player counter
    INX
    CPX #NUM_PLAYERS    ; compare against NUM_PLAYERS
    BNE da_player    ; not zero - condition not met
    LDA tmp: STA wall_pos
    LDX #0
.da_ct
    LDA #INITIAL_HAND: STA num_tiles, X
    INX: CPX #NUM_PLAYERS: BNE da_ct
    LDX #0: LDA #0
.da_cl
    STA num_discards, X
    INX: CPX #NUM_PLAYERS: BNE da_cl
    LDX #0
.da_sr
    STX tmp5
    JSR sort_hand
    LDX tmp5
    INX: CPX #NUM_PLAYERS: BNE da_sr
    RTS

; =============================================
; POINTER HELPERS
; =============================================

; Set ptr to player X's hand. Preserves X.
.set_hand_ptr
    STX tmp5
    TXA: ASL A: TAX
    LDA hand_bases, X: STA ptr
    LDA hand_bases+1, X: STA ptr+1
    LDX tmp5
    RTS

; Set ptr to player X's discards. Preserves X.
.set_disc_ptr
    STX tmp5
    TXA: ASL A: TAX
    LDA disc_bases, X: STA ptr
    LDA disc_bases+1, X: STA ptr+1
    LDX tmp5
    RTS

; =============================================
; PLAYER OPERATIONS
; =============================================

; Draw a tile for current player
.player_draw
    JSR check_wall_integrity   ; verify wall hasn't been corrupted
    LDX current_player
    LDA num_tiles, X
    CMP #HAND_SIZE: BCS pd_fail
    LDX wall_pos
    CPX #DORA_START: BCS pd_fail
    LDA wall, X
    INC wall_pos
    LDX current_player
    PHA
    JSR set_hand_ptr
    PLA
    LDY num_tiles, X
    STA (ptr), Y
    INC num_tiles, X
    CLC: RTS
.pd_fail
    SEC: RTS

; Verify wall integrity: count all tile types in wall[0..DORA_START-1]
; Each tile type must appear exactly 4 times. BRK if corruption detected.
; Destroys A, X, Y.
.check_wall_integrity
    ; Zero the count buffer
    LDX #0
    TXA
.cwi_zero
    STA wall_check_counts, X
    INX
    CPX #TILE_TYPES
    BNE cwi_zero
    ; Count each tile in the full wall array (Y = wall index)
    LDY #0
.cwi_count
    LDA wall, Y
    TAX                        ; tile type → X for count buffer index
    INC wall_check_counts, X
    LDA wall_check_counts, X
    CMP #5
    BEQ cwi_error
    INY
    CPY #DORA_START
    BNE cwi_count
    RTS
.cwi_error
    ; Corruption detected — BRK triggers BeebEm debugger
    BRK

; Discard tile at position X (0-based) for current player
.player_discard
    STX tmp
    ; Clear kan decline flag when human discards
    LDX current_player
    CPX #0: BNE pd_not_human
    LDA #0: STA kan_declined
.pd_not_human
    LDX current_player
    JSR set_hand_ptr
    LDY tmp
    LDA (ptr), Y
    ; Save discarded tile info for open call checking (pon/chii/kan prompts)
    STA disc_tile_val
    LDX current_player
    STX disc_tile_player
    PHA
    LDX current_player
    JSR set_disc_ptr
    LDY num_discards, X
    PLA
    STA (ptr), Y
    INC num_discards, X
    ; Shift hand left to remove tile
    LDX current_player
    JSR set_hand_ptr
    LDY num_tiles, X
    DEY
    STY tmp7
    LDY tmp
.pd_shift
    CPY tmp7: BCS pd_done
    INY
    LDA (ptr), Y
    DEY
    STA (ptr), Y
    INY
    JMP pd_shift
.pd_done
    DEC num_tiles, X
    ; Clear temporary furiten for this player
    LDX current_player
    LDA furiten_flags, X
    AND #&FE              ; clear bit 0 (temp furiten)
    STA furiten_flags, X
    ; Clear first_turn after first discard (prevents false tenhou/chiihou)
    LDA #0: STA first_turn
    RTS

; =============================================
; SORT HAND (bubble sort, player in X)
; =============================================

.sort_hand
    JSR set_hand_ptr
    LDA num_tiles, X
    BEQ sr_dn    ; end of string
    SEC: SBC #1
    STA tmp4
.sr_pass
    LDA #0: STA tmp2
    LDY #0
.sr_lp
    CPY tmp4: BEQ sr_chk
    LDA (ptr), Y
    STA tmp3
    INY
    LDA (ptr), Y
    CMP tmp3: BEQ sr_no
    BCC sr_no    ; carry clear
    ; Swap
    PHA
    LDA tmp3
    STA (ptr), Y
    DEY
    PLA
    STA (ptr), Y
    INY
    LDA #1: STA tmp2
.sr_no
    JMP sr_lp
.sr_chk
    LDA tmp2: BNE sr_pass
.sr_dn
    RTS

; =============================================
; AI LOGIC
; =============================================

; Choose best tile to discard for current player.
; Returns 0-based position in X.
.ai_choose_discard
    STX tmp5
    JSR set_hand_ptr
    LDA num_tiles, X
    STA tmp7
    LDA ai_difficulty
    CMP #2: BEQ ai_expert_discard
    CMP #1: BEQ ai_intermediate_discard
    ; Novice: use simple evaluation (pairs +3, adjacent +2, gap +1)
    LDA #$FF: STA tmp       ; best score so far (lowest = discard)
    LDA #0: STA tmp2        ; best tile index
    LDA #0: STA tmp3        ; current tile index
    JMP ai_outer

.ai_intermediate_discard
    ; Intermediate: count pairs AND sequences (3+ connected)
    ; Score: pairs +3, adjacent +2, gap +1, sequence +5
    LDA #$FF: STA tmp
    LDA #0: STA tmp2
    LDA #0: STA tmp3
    JMP ai_outer

.ai_expert_discard
    ; Expert: defensive play + better evaluation
    ; Check if any opponent has riichi
    LDX current_player
    LDA #0: STA tmp11       ; tmp11 = opponent_riichi flag
    LDY #0
.ai_check_riichi
    CPY #NUM_PLAYERS: BCS ai_expert_setup
    CPY current_player: BEQ ai_next_riichi
    LDA riichi_declared, Y
    BEQ ai_next_riichi
    LDA #1: STA tmp11       ; opponent has riichi
    JMP ai_expert_setup
.ai_next_riichi
    INY
    JMP ai_check_riichi

.ai_expert_setup
    LDA #$FF: STA tmp
    LDA #0: STA tmp2
    LDA #0: STA tmp3
    JMP ai_outer

.ai_outer
    LDY tmp3
    CPY tmp7: BNE ai_outer_go
    JMP ai_done              ; hand exhausted, return best tile
.ai_outer_go
    LDA (ptr), Y
    STA tmp4                ; tmp4 = current tile being evaluated
    LDA #0: STA tmp6        ; tmp6 = score (higher = more connected = keep)
    LDY #0

.ai_inner
    CPY tmp7: BCS ai_eval_done
    CPY tmp3: BEQ ai_next_j
    LDA (ptr), Y
    CMP tmp4: BNE ai_not_pair
    ; Pair found: same tile as current
    LDA tmp6: CLC: ADC #3
    STA tmp6
    JMP ai_next_j

.ai_not_pair
    ; Check if both tiles are suited (not honors)
    LDA tmp4
    CMP #HONOR_BOUNDARY: BCS ai_next_j
    LDA (ptr), Y
    CMP #HONOR_BOUNDARY: BCS ai_next_j
    JSR check_same_suit
    BCC ai_next_j            ; if check_same_suit returned carry clear (OK/false)
    ; Same suit - calculate distance
    LDA (ptr), Y
    SEC: SBC tmp4
    BPL ai_abs
    EOR #$FF: CLC: ADC #1
.ai_abs
    CMP #1: BNE ai_nadj1
    ; Adjacent tiles (distance 1): +2
    LDA tmp6: CLC: ADC #2
    STA tmp6
    JMP ai_next_j
.ai_nadj1
    CMP #2: BNE ai_next_j
    ; Gap tiles (distance 2): +1
    LDA tmp6: CLC: ADC #1
    STA tmp6

.ai_next_j
    INY
    JMP ai_inner

.ai_eval_done
    ; Defensive play for intermediate and expert
    LDA ai_difficulty
    CMP #1: BCC ai_no_defense    ; novice: skip defense
    LDA tmp11
    BEQ ai_no_defense             ; no opponent riichi
    ; Check if tile is safe (genbutsu - discarded by any player)
    LDA tmp4
    JSR check_tile_safe
    BCC ai_not_genbutsu
    ; Genbutsu: guaranteed safe discard
    LDA #0: STA tmp6
    JMP ai_no_defense
.ai_not_genbutsu
    ; Expert: additional safety checks
    LDA ai_difficulty
    CMP #2: BNE ai_no_defense
    ; Count how many copies of this tile are visible in discards
    LDA tmp4
    JSR count_visible_copies
    CMP #3: BCC ai_not_3visible
    ; 3+ copies visible: very safe (only 1 left in game)
    LDA #1: STA tmp6
    JMP ai_no_defense
.ai_not_3visible
    CMP #2: BCC ai_no_defense
    ; 2 copies visible: somewhat safe, reduce score by 2
    LDA tmp6
    SEC: SBC #2
    BCS ai_defense_save
    LDA #0                  ; clamp to 0
.ai_defense_save
    STA tmp6
.ai_no_defense

    ; Intermediate/Expert: bonus for sequence potential
    LDA ai_difficulty
    CMP #0: BEQ ai_score_update  ; novice: skip sequence check
    ; Check if current tile is part of a sequence (has neighbor+1 and neighbor+2)
    LDA tmp4
    CMP #HONOR_BOUNDARY: BCS ai_score_update  ; honors can't form sequences
    JSR check_sequence_potential
    BCC ai_score_update     ; if check_sequence_potential returned carry clear (not found)
    ; Part of a sequence: +5 bonus
    LDA tmp6: CLC: ADC #5
    STA tmp6

.ai_score_update
    LDA tmp6
    CMP tmp: BCS ai_skip    ; score >= best so far: don't update
    LDA tmp6: STA tmp       ; new best score (lower = discard)
    LDA tmp3: STA tmp2      ; save tile index
.ai_skip
    INC tmp3
    JMP ai_outer

.ai_done
    LDX tmp2
    RTS

; Check if tile in A has been discarded by any player.
; Returns carry set if safe, carry clear if not.
.check_tile_safe
    STA tmp13               ; save tile to check
    LDX #0
.cts_player_loop
    CPX #NUM_PLAYERS: BCS cts_not_safe
    ; Get discard count for player X
    STX tmp9                ; save player number
    LDA num_discards, X
    BEQ cts_next_player     ; no discards for this player
    STA tmp12               ; tmp12 = discard count
    ; Calculate base offset: X * MAX_DISC
    TXA: ASL A: ASL A: ASL A: ASL A: ASL A  ; X = player * MAX_DISC
    TAX
    LDY #0
.cts_disc_loop
    CPY tmp12: BCS cts_restore_player  ; no more discards
    LDA discards, X
    CMP tmp13: BEQ cts_safe   ; found matching discard - tile is safe
    INX
    INY
    JMP cts_disc_loop
.cts_restore_player
    LDX tmp9
.cts_next_player
    INX
    JMP cts_player_loop
.cts_safe
    SEC: RTS
.cts_not_safe
    CLC: RTS

; Check if tile in A is part of a sequence (A-2, A-1 in hand).
; Returns carry set if part of sequence, carry clear if not.
.check_sequence_potential
    STA tmp13               ; save tile
    ; Check if tile-2 exists in hand
    SEC: SBC #2
    BCC csp_check_mid       ; underflow
    JSR check_tile_in_hand
    BCS csp_found           ; found tile-2: part of sequence
.csp_check_mid
    LDA tmp13
    SEC: SBC #1
    BCC csp_not_found
    JSR check_tile_in_hand
    BCS csp_found           ; found tile-1: part of sequence
.csp_not_found
    CLC: RTS
.csp_found
    SEC: RTS

; Check if tile in A is in the current player's hand.
; Returns carry set if found, carry clear if not.
.check_tile_in_hand
    STA tmp13               ; save tile
    LDX current_player
    JSR set_hand_ptr
    LDA num_tiles, X
    STA tmp12               ; tmp12 = hand size
    LDY #0
.ctih_loop
    CPY tmp12: BCS ctih_not_found
    LDA (ptr), Y
    CMP tmp13: BEQ ctih_found
    INY
    JMP ctih_loop
.ctih_found
    SEC: RTS
.ctih_not_found
    CLC: RTS

; Count visible copies of a tile in all players' discards.
; A = tile to check. Returns count in A (0-12).
; Used by expert AI to assess tile safety when opponent has riichi.
.count_visible_copies
    STA tmp13               ; save tile
    LDA #0: STA tmp8        ; tmp8 = count
    LDX #0
.cvc_player_loop
    CPX #NUM_PLAYERS: BCS cvc_done
    STX tmp9                ; save player
    LDA num_discards, X
    BEQ cvc_next_player
    STA tmp12
    TXA: ASL A: ASL A: ASL A: ASL A: ASL A  ; X = player * MAX_DISC
    TAX
    LDY #0
.cvc_disc_loop
    CPY tmp12: BCS cvc_restore
    LDA discards, X
    CMP tmp13: BNE cvc_next
    INC tmp8                ; found a copy
.cvc_next
    INX: INY
    JMP cvc_disc_loop
.cvc_restore
    LDX tmp9
.cvc_next_player
    INX
    JMP cvc_player_loop
.cvc_done
    LDA tmp8                ; return count in A
    RTS

; Check same suit for tile in tmp4 and (ptr),Y. C set if same.
.check_same_suit
    LDA tmp4
    CMP #SUIT_BOUNDARY: BCC css_man
    CMP #SOU_BOUNDARY: BCC css_pin
    LDA (ptr), Y
    CMP #SOU_BOUNDARY: BCC css_no
    CMP #WIND_BASE: BCS css_no
    SEC: RTS
.css_man
    LDA (ptr), Y
    CMP #SUIT_BOUNDARY: BCS css_no
    SEC: RTS
.css_pin
    LDA (ptr), Y
    CMP #SUIT_BOUNDARY: BCC css_no
    CMP #SOU_BOUNDARY: BCS css_no
    SEC: RTS
.css_no
    CLC: RTS

; =============================================
; OPEN CALL DETECTION
; =============================================
; After a discard, check if any other player can claim it.
; Per Turn Sequence: check Pon, Chii, Kan.
; Returns: C set = call made (current_player changed), C clear = no call.

; Count tiles for player X into tile_counts.
.count_tiles_for_player
    JSR set_hand_ptr
    LDA #0: LDY #0
.ctfp_clear
    STA tile_counts, Y
    INY: CPY #TILE_TYPES: BNE ctfp_clear
    LDY num_tiles, X
    BEQ ctfp_done    ; player has no tiles
    DEY
.ctfp_loop
    LDA (ptr), Y
    TAX
    INC tile_counts, X
    DEY
    BPL ctfp_loop    ; Y not negative yet - keep counting
.ctfp_done
    RTS

; Main open call check.
.check_open_calls
    LDX disc_tile_player
    STX tmp7                 ; tmp7 = who discarded
    LDX #0
.soc_lp
    STX tmp5                 ;\ tmp5 = checking player
    CPX tmp7: BNE soc_not_skip
    JMP soc_skip
.soc_not_skip
    ; Skip if player already has max open melds (no room for more)
    LDA opn_count, X
    CMP #MAX_OPEN_MELDS: BCC soc_has_room
    JMP soc_skip
.soc_has_room
    JSR count_tiles_for_player

    ; Check Pon
    LDY disc_tile_val
    LDA tile_counts, Y
    CMP #2    ; check if enough for a pair
    BCC soc_try_chii    ; not enough for pon - try chii
    ; Human player: prompt first
    LDX tmp5
    CPX #0    ; check if human player
    BNE soc_pon_ai    ; AI player - auto-declare pon
    JSR soc_human_prompt_pon
    BCC soc_try_chii          ; N = skip pon, try chii
    JSR execute_pon
    SEC: RTS
.soc_pon_ai
    JSR execute_pon
    SEC: RTS

.soc_try_chii
    ; Chii only from left player (discarder+1 mod 4)
    LDA tmp7
    CLC: ADC #1: AND #3
    CMP tmp5: BNE soc_try_kan
    ; Only suited tiles
    LDA disc_tile_val
    CMP #27: BCS soc_try_kan
    ; Try 3 Chii patterns, record which one succeeded in tmp3
    LDA #0: STA tmp3          ; assume low chii (disc, disc+1, disc+2)
    JSR try_chii_low
    BCS soc_do_chii
    INC tmp3                   ; try mid chii (disc-1, disc, disc+1)
    JSR try_chii_mid
    BCS soc_do_chii
    INC tmp3                   ; try high chii (disc-2, disc-1, disc)
    JSR try_chii_high
    BCS soc_do_chii
    JMP soc_try_kan
.soc_do_chii
    ; Human player: prompt first
    LDX tmp5
    CPX #0    ; check if human player
    BNE soc_chii_ai    ; AI player - auto-declare chii
    JSR soc_human_prompt_chii
    BCC soc_try_kan          ; N = skip chii, try kan
    JSR execute_chii
    SEC: RTS
.soc_chii_ai
    JSR execute_chii
    SEC: RTS

.soc_try_kan
    LDY disc_tile_val
    LDA tile_counts, Y
    CMP #3    ; need 3+ copies for triplet
    BCC soc_skip    ; not enough for kan
    ; Human player: prompt first
    LDX tmp5
    CPX #0    ; check if human player
    BNE soc_kan_ai    ; AI player - auto-declare kan
    JSR soc_human_prompt_kan
    BCC soc_skip              ; N = skip kan
    JSR execute_kan
    SEC: RTS
.soc_kan_ai
    JSR execute_kan
    SEC: RTS

.soc_skip
    LDX tmp5
    INX
    CPX #NUM_PLAYERS    ; compare against NUM_PLAYERS
    BEQ soc_done    ; zero - condition met
    JMP soc_lp
.soc_done
    CLC
    RTS

; =============================================
; HUMAN OPEN CALL PROMPTS
; =============================================
; Display prompt and read Y/N for open calls.
; Returns C set if human said Y, C clear if N.

; Prompt for Pon
.soc_human_prompt_pon
    JSR clear_prompt_line
    LDY #0
.shp_lp
    LDA pon_ask_str, Y
    BEQ shp_dn    ; end of string
    JSR oswrch: INY
    JMP shp_lp
.shp_dn
    ; Show which tile was discarded
    LDA #' ': JSR oswrch
    LDA disc_tile_val: JSR tile_num_char: JSR oswrch
    LDA disc_tile_val: JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    JSR osrdch
    CMP #'Y': BEQ shp_yes
    CMP #'y': BEQ shp_yes
    ; User said no — clear prompt before returning
    JSR clear_prompt_line
    CLC: RTS
.shp_yes
    SEC: RTS

; Prompt for Chii
.soc_human_prompt_chii
    JSR clear_prompt_line
    LDY #0
.shc_lp
    LDA chii_ask_str, Y
    BEQ shc_dn    ; end of string
    JSR oswrch: INY
    JMP shc_lp
.shc_dn
    ; Show which tile was discarded
    LDA #' ': JSR oswrch
    LDA disc_tile_val: JSR tile_num_char: JSR oswrch
    LDA disc_tile_val: JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    JSR osrdch
    CMP #'Y': BEQ shc_yes
    CMP #'y': BEQ shc_yes
    ; User said no — clear prompt before returning
    JSR clear_prompt_line
    CLC: RTS
.shc_yes
    SEC: RTS

; Prompt for Kan from discard
.soc_human_prompt_kan
    JSR clear_prompt_line
    LDY #0
.shk_lp
    LDA kan_ask_str, Y
    BEQ shk_dn    ; end of string
    JSR oswrch: INY
    JMP shk_lp
.shk_dn
    ; Show which tile was discarded
    LDA #' ': JSR oswrch
    LDA disc_tile_val: JSR tile_num_char: JSR oswrch
    LDA disc_tile_val: JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    JSR osrdch
    CMP #'Y': BEQ shk_yes
    CMP #'y': BEQ shk_yes
    ; User said no — clear prompt before returning
    JSR clear_prompt_line
    CLC: RTS
.shk_yes
    SEC: RTS

; Chii: disc tile as low end (need X+1, X+2)
.try_chii_low
    LDA disc_tile_val
    CLC: ADC #1
    CMP #27: BCS tcl_no
    TAX: LDA tile_counts, X
    BEQ tcl_no    ; missing required tile - low chii impossible
    LDA disc_tile_val
    CLC: ADC #2
    CMP #27: BCS tcl_no
    TAX: LDA tile_counts, X
    BEQ tcl_no    ; missing required tile - low chii impossible
    SEC: RTS
.tcl_no
    CLC: RTS

; Chii: disc tile as middle (need X-1, X+1)
.try_chii_mid
    LDA disc_tile_val
    ; Check lower tile in same suit
    CMP #SUIT_BOUNDARY: BCC tcm_man
    CMP #SOU_BOUNDARY: BCC tcm_pin
    CMP #WIND_BASE: BCC tcm_sou
    CLC: RTS
.tcm_man
    CMP #2: BCC tcm_no     ; need tile >= 2
    JMP tcm_check
.tcm_pin
    CMP #11: BCC tcm_no    ; need tile >= 11
    JMP tcm_check
.tcm_sou
    CMP #20: BCC tcm_no    ; need tile >= 20
.tcm_check
    TAX: DEX
    LDA tile_counts, X
    BEQ tcm_no    ; missing required tile - mid chii impossible
    LDA disc_tile_val
    CLC: ADC #1
    TAX: LDA tile_counts, X
    BEQ tcm_no    ; missing required tile - mid chii impossible
    SEC: RTS
.tcm_no
    CLC: RTS

; Chii: disc tile as high end (need X-2, X-1)
.try_chii_high
    LDA disc_tile_val
    CMP #SUIT_BOUNDARY: BCC tch_man
    CMP #SOU_BOUNDARY: BCC tch_pin
    CMP #WIND_BASE: BCC tch_sou
    CLC: RTS
.tch_man
    CMP #2: BCC tch_no
    JMP tch_check
.tch_pin
    CMP #11: BCC tch_no
    JMP tch_check
.tch_sou
    CMP #20: BCC tch_no
.tch_check
    TAX: DEX: DEX
    LDA tile_counts, X
    BEQ tch_no    ; missing required tile - high chii impossible
    INX
    LDA tile_counts, X
    BEQ tch_no    ; missing required tile - high chii impossible
    SEC: RTS
.tch_no
    CLC: RTS

; Execute Pon: claim discarded tile with 2 from hand.
; Removes 2 tiles, adds open meld, sets current_player.
.execute_pon
    LDX tmp5
    STX current_player
    JSR set_hand_ptr
    ; Find and remove 2 copies of disc_tile_val
    LDA #0: STA tmp8          ; removal counter
    LDY #0
.ep_find
    STY tmp4
    LDA tmp4
    CMP num_tiles, X    ; check if past end of hand
    BCC skp_654    ; still within hand - continue search
    JMP ep_add
.skp_654
    LDA (ptr), Y
    CMP disc_tile_val: BNE ep_next
    INC tmp8
    LDA tmp8: CMP #2: BEQ ep_rm2
.ep_next
    INY: JMP ep_find
.ep_rm2
    ; Found 2nd copy at Y - remove it directly
    JSR ep_remove_at
    ; Re-find and remove first copy
    LDX current_player
    JSR set_hand_ptr
    LDY #0
.ep_find2
    LDA (ptr), Y
    CMP disc_tile_val: BNE ep_next2
    JSR ep_remove_at
    JMP ep_add
.ep_next2
    INY: JMP ep_find2

; Remove tile at position Y from hand (shift left)
.ep_remove_at
    LDX current_player
    STY tmp4
    LDY num_tiles, X
    DEY: STY tmp6
    LDY tmp4
.ep_rm_lp
    CPY tmp6: BCS ep_rm_dn
    INY: LDA (ptr), Y
    DEY: STA (ptr), Y
    INY: JMP ep_rm_lp
.ep_rm_dn
    DEC num_tiles, X
    RTS

; ep_add: record an open meld after pon or chii.
; Records type 1 (pon) with disc_tile_val x 3.
; Used by execute_pon after removing 2 tiles from hand.
.ep_add
    ; Calculate offset into opn_melds
    ; offset = player * 20 + opn_count * 5
    LDX current_player
    TXA: ASL A: ASL A       ; * 4
    STA tmp4
    TXA: ASL A: ASL A: ASL A: ASL A ; * 16
    CLC: ADC tmp4            ; = * 20
    STA tmp4                 ; tmp4 = player * 20
    ; Add opn_count * 5
    LDX current_player
    LDY opn_count, X
    BEQ ep_off_done    ; no existing melds - offset is just base
    LDA #0
.ep_mul5
    CLC: ADC #5
    DEY: BNE ep_mul5
    JMP ep_off_add
.ep_off_done
    LDA #0
.ep_off_add
    CLC: ADC tmp4            ; + player * 20
    TAX                      ; X = offset into opn_melds
    ; Store meld: type 1 (pon), disc_tile_val x 3
    LDA #1
    STA opn_melds, X
    INX
    LDA disc_tile_val
    STA opn_melds, X
    STA opn_melds+1, X
    STA opn_melds+2, X
    ; Increment meld count
    LDX current_player
    INC opn_count, X
    ; Remove last entry from discard pile (use discarder, not caller)
    LDX disc_tile_player
    JSR set_disc_ptr
    LDA num_discards, X
    SEC: SBC #1
    STA num_discards, X
    ; Set skip_draw
    LDA #1
    STA skip_draw
    RTS

; Execute Chii record: store type 2 meld with three sequential tiles.
; tmp8 holds the base (lowest) tile; +1 and +2 complete the sequence.
.ep_add_chii
    ; Calculate offset into opn_melds (same formula as ep_add)
    LDX current_player
    TXA: ASL A: ASL A       ; * 4
    STA tmp4
    TXA: ASL A: ASL A: ASL A: ASL A ; * 16
    CLC: ADC tmp4            ; = * 20
    STA tmp4                 ; tmp4 = player * 20
    ; Add opn_count * 5
    LDX current_player
    LDY opn_count, X
    BEQ ech_off_done
    LDA #0
.ech_mul5
    CLC: ADC #5
    DEY: BNE ech_mul5
    JMP ech_off_add
.ech_off_done
    LDA #0
.ech_off_add
    CLC: ADC tmp4
    TAX                      ; X = offset into opn_melds
    ; Store meld: type 2 (sequence), 3 sequential tiles from tmp8
    LDA #2
    STA opn_melds, X
    INX
    LDA tmp8
    STA opn_melds, X        ; lowest tile (base)
    CLC: ADC #1
    STA opn_melds+1, X      ; middle tile (base+1)
    CLC: ADC #1
    STA opn_melds+2, X      ; highest tile (base+2)
    ; Increment meld count
    LDX current_player
    INC opn_count, X
    ; Remove last entry from discard pile
    LDX disc_tile_player
    JSR set_disc_ptr
    LDA num_discards, X
    SEC: SBC #1
    STA num_discards, X
    ; Chii is always open - allow normal draw (don't set skip_draw)
    RTS

; Execute Chii: claim discarded tile with 2 from hand (sequence).
; tmp3 indicates which variant (0=low, 1=mid, 2=high).
; Compute the base tile (lowest of the three), then remove base+1 and base+2.
.execute_chii
    LDX tmp5
    STX current_player
    JSR set_hand_ptr
    ; Compute base tile based on chii variant
    LDA disc_tile_val
    LDY tmp3
    BEQ ec_low         ; variant 0: base = disc (low chii)
    DEY
    BEQ ec_mid         ; variant 1: base = disc-1 (mid chii)
    ; variant 2: base = disc-2 (high chii)
    SEC: SBC #2
    JMP ec_set_tiles
.ec_mid
    SEC: SBC #1
.ec_set_tiles
.ec_low
    STA tmp8            ; tmp8 = base tile
    CLC: ADC #1
    STA tmp9            ; tmp9 = base+1 (first tile to remove)
    LDA tmp8
    CLC: ADC #2
    STA tmp10           ; tmp10 = base+2 (second tile to remove)
    ; Remove first tile (tmp9 = base+1)
    LDX current_player
    JSR set_hand_ptr
    LDY #0
.ec_find1
    LDA (ptr), Y
    CMP tmp9: BNE ec_n1
    JSR ep_remove_at
    JMP ec_rm2
.ec_n1
    INY: JMP ec_find1
.ec_rm2
    ; Re-find hand pointer and remove second tile (tmp10 = base+2)
    LDX current_player
    JSR set_hand_ptr
    LDY #0
.ec_find2
    LDA (ptr), Y
    CMP tmp10: BNE ec_n2
    JSR ep_remove_at
    JMP ep_add_chii    ; record as type 2 (sequence)
.ec_n2
    INY: JMP ec_find2

; Execute Kan: claim discarded tile with 3 from hand (open kan / daiminkan).
; Records as type 4 meld, draws rinshan replacement from dead wall.
.execute_kan
    LDX tmp5
    STX current_player
    ; Remove 3 copies of disc_tile_val from hand
    LDA #3: STA tmp8          ; need to remove 3
.ek_rm_loop
    LDX current_player
    JSR set_hand_ptr
    LDY #0
.ek_rm_find
    LDA (ptr), Y
    CMP disc_tile_val: BNE ek_rm_nxt
    JSR ep_remove_at
    DEC tmp8
    BNE ek_rm_loop    ; more tiles to remove for kan
    JMP ek_rm_done
.ek_rm_nxt
    INY
    STY tmp4
    LDA num_tiles, X
    CMP tmp4    ; check if past end of hand
    BCS ek_rm_find    ; still within hand, keep scanning
    ; Hand exhausted - check if all tiles were found
    LDA tmp8
    BEQ ek_rm_done    ; all tiles found, proceed with kan
    JMP ek_kan_failed ; not enough tiles - abort kan
.ek_rm_done

    ; Record meld as type 4 (kan) with 4 tiles
    ; offset = player * 20 + opn_count * 5
    LDX current_player
    TXA: ASL A: ASL A       ; * 4
    STA tmp4
    TXA: ASL A: ASL A: ASL A: ASL A ; * 16
    CLC: ADC tmp4            ; = * 20
    STA tmp4                 ; tmp4 = player * 20
    ; Add opn_count * 5
    LDX current_player
    LDY opn_count, X
    BEQ ek_off_done    ; no existing melds - offset is just base
    LDA #0
.ek_mul5
    CLC: ADC #5
    DEY: BNE ek_mul5
    JMP ek_off_add
.ek_off_done
    LDA #0
.ek_off_add
    CLC: ADC tmp4            ; + player * 20
    TAX                      ; X = offset into opn_melds
    ; Store meld: type 4 (kan), tile x 4
    LDA #4
    STA opn_melds, X
    INX
    LDA disc_tile_val
    STA opn_melds, X
    STA opn_melds+1, X
    STA opn_melds+2, X
    STA opn_melds+3, X
    ; Increment meld count
    LDX current_player
    INC opn_count, X

    ; Rinshan draw: replacement from dead wall
    LDA dora_count
    CLC: ADC #DORA_START
    TAX
    LDA wall, X          ; draw from end of dead wall
    PHA
    LDX current_player
    JSR set_hand_ptr
    PLA
    LDY num_tiles, X
    CPY #HAND_SIZE
    BCS ek_no_draw       ; hand full, skip draw (safety)
    STA (ptr), Y
    INC num_tiles, X
.ek_no_draw

    ; Reveal new dora indicator
    JSR reveal_dora
    ; Increment per-player kans count
    LDX current_player
    INC player_kans, X
    INC four_kans_count
    ; Remove last entry from discard pile (use discarder, not caller)
    LDX disc_tile_player
    JSR set_disc_ptr
    LDA num_discards, X
    SEC: SBC #1
    STA num_discards, X
    ; Set skip_draw (player will discard after rinshan)
    LDA #1
    STA skip_draw
    RTS
.ek_kan_failed
    ; Not enough matching tiles found - abort kan attempt
    CLC
    RTS

; =============================================
; DISPLAY
; =============================================

.game_display
    LDA #12: JSR oswrch

    ; Title
    LDY #0
.gd_title
    LDA title_str, Y
    BEQ gd_title_dn    ; end of string
    JSR oswrch: INY
    JMP gd_title
.gd_title_dn
    JSR osnewl
    JSR disp_points_line
    JSR osnewl
    ; Blank line between score area and play area
    JSR osnewl

    ; Human hand header: "Your Hand (X)"
        LDY #0
    .gd_hh
        LDA hand_hdr_str, Y
        BEQ gd_hh_dn    ; end of string
        JSR oswrch: INY
        JMP gd_hh
    .gd_hh_dn
        LDA #' ': JSR oswrch
        LDA #'(': JSR oswrch
        LDX #0
        LDA seat_winds, X
        JSR tile_num_char: JSR oswrch
        LDA #')': JSR oswrch
        JSR osnewl

    ; Hand top row (numbers/symbols)
    LDX #0
.gd_ht
    CPX num_tiles: BCS gd_ht_dn
    LDA hands, X
    JSR tile_num_char: JSR oswrch
    LDA #' ': JSR oswrch
    INX: JMP gd_ht
.gd_ht_dn
    JSR osnewl

    ; Hand bottom row (suits)
    LDX #0
.gd_hb
    CPX num_tiles: BCS gd_hb_dn
    LDA hands, X
    JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    INX: JMP gd_hb
.gd_hb_dn
    JSR osnewl: JSR osnewl

    ; Practice mode hint
    LDA practice_mode
    BEQ gd_skip_hint    ; practice mode off - skip hint
    JSR practice_hint
.gd_skip_hint

    ; Human discards: "Your Disc (X): tiles"
    LDY #0
.gd_mydi
    LDA my_disc_str, Y
    BEQ gd_mydi_dn    ; end of string
    JSR oswrch: INY
    JMP gd_mydi
.gd_mydi_dn
    LDA #' ': JSR oswrch
    LDA #'(': JSR oswrch
    LDX #0
    LDA seat_winds, X
    JSR tile_num_char: JSR oswrch
    LDA #')': JSR oswrch
    LDA #':': JSR oswrch
    LDA #' ': JSR oswrch    ; space after colon to align tiles with CPU discards
    LDX #0
    JSR set_disc_ptr
    LDA num_discards, X
    BEQ gd_mydisc_nl    ; no discards yet
    JSR calc_disc_start  ; Y = start, tmp6 = end
.gd_my_lp
    LDA (ptr), Y: PHA
    JSR tile_num_char: JSR oswrch
    PLA
    JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    INY
    CPY tmp6: BNE gd_my_lp    ; more discards to print
    JMP gd_mydisc_nl          ; done
.gd_mydisc_nl
    JSR osnewl
    ; Show human open melds
    LDX #0
    JSR disp_open_melds

    ; Blank line between human and CPU sections
    JSR osnewl

    ; AI discards (players 1-3)
    LDX #1
.gd_disc_lp
    CPX #NUM_PLAYERS    ; compare against NUM_PLAYERS
    BNE gd_disc_body    ; not zero - condition not met
    JMP gd_disc_dn
.gd_disc_body
    STX tmp7
    ; Print 3 spaces indent + "CPU P" + player number + " (" + wind + "):"
    LDA #' ': JSR oswrch
    LDA #' ': JSR oswrch
    LDA #' ': JSR oswrch
    LDY #0
.gd_cpu_lp
    LDA gd_cpu_str, Y
    BEQ gd_cpu_dn    ; end of string
    JSR oswrch: INY
    JMP gd_cpu_lp
.gd_cpu_dn
    TXA: CLC: ADC #'1'  ; Internal player 1 = display P2
    JSR oswrch
    LDY #0
.gd_par_lp
    LDA gd_par_str, Y
    BEQ gd_par_dn    ; end of string
    JSR oswrch: INY
    JMP gd_par_lp
.gd_par_dn
    LDA seat_winds, X
    JSR tile_num_char: JSR oswrch
    LDY #0
.gd_par2_lp
    LDA gd_par2_str, Y
    BEQ gd_par2_dn    ; end of string
    JSR oswrch: INY
    JMP gd_par2_lp
.gd_par2_dn
    JSR set_disc_ptr
    LDX tmp7
    LDA num_discards, X
    BEQ gd_disc_nl    ; no discards for this player
    JSR calc_disc_start  ; Y = start, tmp6 = end
.gd_d_lp
    LDA (ptr), Y: PHA
    JSR tile_num_char: JSR oswrch
    PLA
    JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    INY
    CPY tmp6: BNE gd_d_lp    ; more discards to print
    JMP gd_disc_nl           ; done
.gd_disc_nl
    JSR osnewl
    ; Show open melds for this AI player
    LDA tmp7: PHA
    LDX tmp7
    JSR disp_open_melds
    PLA: STA tmp7
    LDX tmp7
    JSR osnewl    ; blank line between AI player sections
    INX
    JMP gd_disc_lp
.gd_disc_dn
    JSR osnewl

    ; Turn indicator: "YOUR MOVE" for human, "CPU P2/P3/P4" for AI
    LDA current_player
    BEQ gd_human_move
    ; CPU player — print "CPU P" then player number + 2 as ASCII digit
    LDY #0
.gd_cpu_move_lp
    LDA cpu_move_str, Y
    BEQ gd_cpu_num    ; end of "CPU P" prefix
    JSR oswrch: INY
    JMP gd_cpu_move_lp
.gd_cpu_num
    LDA current_player
    CLC: ADC #'0'+1  ; P2=1+1, P3=2+1, P4=3+1
    JSR oswrch
    JMP gd_move_dn
.gd_human_move
    LDY #0
.gd_move_lp
    LDA your_move_str, Y
    BEQ gd_move_dn    ; end of string
    JSR oswrch: INY
    JMP gd_move_lp
.gd_move_dn
    JSR osnewl

    ; Controls
    LDY #0
.gd_inst
    LDA inst_str, Y
    BEQ gd_done    ; end of instructions string
    JSR oswrch: INY
    JMP gd_inst
.gd_done
    ; Dora and wall count at bottom
    JSR osnewl
    LDY #0
.gd_dora_lp
    LDA gd_dora_str, Y
    BEQ gd_dora_dn    ; end of string
    JSR oswrch: INY
    JMP gd_dora_lp
.gd_dora_dn
    LDA dora_indicator
    JSR tile_num_char: JSR oswrch
    LDA dora_indicator
    JSR tile_suit_char: JSR oswrch
    LDY #0
.gd_wall_lp
    LDA gd_wall_str, Y
    BEQ gd_wall_dn    ; end of string
    JSR oswrch: INY
    JMP gd_wall_lp
.gd_wall_dn
    LDA #DORA_START
    SEC: SBC wall_pos
    ; Print as up to 3-digit decimal (max 122)
    ; Hundreds digit
    LDX #0
.wc100
    CMP #100: BCC wc100dn
    SEC: SBC #100: INX: JMP wc100
.wc100dn
    PHA
    TXA: BEQ wc_no_hun       ; skip leading zero
    CLC: ADC #'0': JSR oswrch
.wc_no_hun
    PLA
    ; Tens digit
    LDX #0
.wc10
    CMP #10: BCC wc10dn
    SEC: SBC #10: INX: JMP wc10
.wc10dn
    ; DEBUG: trap if wall count digits out of range (indicates data corruption)
    CPX #10: BCC wc_tens_ok: BRK  ; tens digit >= 10 = corruption
.wc_tens_ok
    PHA
    CMP #10: BCC wc_units_ok: BRK ; units digit >= 10 = corruption
.wc_units_ok
    TXA: CLC: ADC #'0': JSR oswrch
    PLA: CLC: ADC #'0': JSR oswrch
    ; Print dealer wind
    LDY #0
.gd_dealer_lp
    LDA gd_dealer_str, Y
    BEQ gd_dealer_dn    ; end of string
    JSR oswrch: INY
    JMP gd_dealer_lp
.gd_dealer_dn
    LDX dealer
    LDA seat_winds, X
    JSR tile_num_char: JSR oswrch
    ; Print riichi sticks and honba count
    LDA #' ': JSR oswrch
    LDA #'R': JSR oswrch
    LDA #':': JSR oswrch
    LDA riichi_on_table
    CLC: ADC #'0'
    JSR oswrch
    LDA #' ': JSR oswrch
    LDA #'H': JSR oswrch
    LDA #':': JSR oswrch
    LDA honba
    CLC: ADC #'0'
    JSR oswrch
    RTS

; Calculate start index for showing last 8 discards
; Input: A = num_discards
; Output: Y = start index, tmp6 = end index
.calc_disc_start
    CMP #8
    BCS cds_over8
    ; 8 or fewer discards - show all from index 0
    LDY #0
    STA tmp6
    RTS
.cds_over8
    ; More than 8 discards - show last 8
    SEC: SBC #8
    TAY            ; Y = start index (num_discards - 8)
    TYA: CLC: ADC #8
    STA tmp6       ; tmp6 = end index
    RTS

; =============================================
; POINT DISPLAY
; =============================================

; Display points for all 4 players + honba
; Format: N:XXXXX[F/R/C]   (3 spaces between players)
.disp_points_line
    LDX #0
.dpl_lp
    STX tmp5
    ; Print player number + ":"
    TXA: CLC: ADC #'1': JSR oswrch
    LDA #':': JSR oswrch
    ; Load player's points (16-bit, little-endian)
    TXA: ASL A: TAX
    LDA player_points+1, X
    PHA
    LDA player_points, X
    TAX
    PLA                     ; A=high, X=low
    JSR print_num16
    ; Indicator between players (F/R/C/space + 3 spaces)
    LDY tmp5
    LDA furiten_flags, Y
    BEQ dpl_no_furi    ; not furiten - check riichi
    LDA #'F': JSR oswrch
    JMP dpl_sp3
.dpl_no_furi
    LDA riichi_declared, Y
    BEQ dpl_no_riichi    ; not in riichi - check chombo
    LDA #'R': JSR oswrch
    JMP dpl_sp3
.dpl_no_riichi
    LDA chombo_count, Y
    BEQ dpl_no_chombo    ; no chombo - print space
    LDA #'C': JSR oswrch
    JMP dpl_sp3
.dpl_no_chombo
    LDA #' ': JSR oswrch
.dpl_sp3
    LDA #' ': JSR oswrch    ; extra space 1
    LDA #' ': JSR oswrch    ; extra space 2
    ; Advance to next player
    LDX tmp5
    INX
    CPX #NUM_PLAYERS
    BEQ dpl_done
    JMP dpl_lp
.dpl_done
    RTS

; Print 16-bit value as 5 decimal digits
; Input: A = high byte, X = low byte
.print_num16
    STA tmp2
    STX tmp3
    LDY #4
.pn_outer
    STY tmp4
    JSR pn_div10
    CLC: ADC #'0'
    PHA
    LDY tmp4
    DEY
    BPL pn_outer    ; more digits to extract
    LDY #0
.pn_print
    PLA: JSR oswrch
    INY: CPY #5: BNE pn_print
    RTS

; Divide tmp2:tmp3 by 10
; Quotient in tmp2:tmp3, remainder in A
.pn_div10
    LDA #0
    LDY #16
.pd_loop
    ASL tmp3
    ROL tmp2
    ROL A
    CMP #10    ; check if remainder >= 10 for division
    BCC pd_skip    ; remainder less than 10 - can't subtract
    SBC #10
    INC tmp3
.pd_skip
    DEY
    BNE pd_loop    ; 16 bits not done yet
    RTS

; =============================================
; TILE CHARACTER ROUTINES
; =============================================

; A = tile value (0-33). Returns display char in A.
; Preserves X and Y (used by caller's loop counters).
.tile_num_char
    CMP #WIND_BASE: BCS tnc_honor
    CMP #SOU_BOUNDARY: BCC tnc_cp
    SEC: SBC #SOU_BOUNDARY
    JMP tnc_dig
.tnc_cp
    CMP #SUIT_BOUNDARY: BCC tnc_dig
    SEC: SBC #SUIT_BOUNDARY
.tnc_dig
    CLC: ADC #'1'
    RTS
.tnc_honor
    ; Must preserve X and Y for caller's loop counters
    ; A = tile value on entry, must compute offset = A - 27
    STA tmp8                        ; save tile value
    TYA: PHA                        ; save Y
    LDA tmp8                        ; restore tile value
    SEC: SBC #WIND_BASE
    TAY                             ; Y = offset into honor_nums
    LDA honor_nums, Y              ; A = display character
    STA tmp8                        ; save result
    PLA: TAY                        ; restore Y
    LDA tmp8                        ; restore result to A
    RTS                             ; A = character, X/Y preserved

; A = tile value (0-33). Returns suit char in A.
; Winds (27-30): 'w' for all (top letter distinguishes them)
; Dragons (31-33): 'g'=green(Hatsu), 'b'=blank(Haku), 'r'=red(Chun)
; Must preserve X and Y for caller's loop counters.
.tile_suit_char
    CMP #SUIT_BOUNDARY: BCC tsc_m
    CMP #SOU_BOUNDARY: BCC tsc_p
    CMP #WIND_BASE: BCC tsc_s
    CMP #31: BEQ tsc_green
    CMP #32: BEQ tsc_white
    CMP #33: BEQ tsc_red
    LDA #'w': RTS
.tsc_green
    LDA #'g': RTS
.tsc_white
    LDA #'b': RTS
.tsc_red
    LDA #'r': RTS
.tsc_m
    LDA #'m': RTS
.tsc_p
    LDA #'p': RTS
.tsc_s
    LDA #'s': RTS

; =============================================
; MELD DECOMPOSITION ENGINE
; =============================================
; Core algorithm for win detection.
; Recursively decomposes a hand into melds (triplets/sequences) + pair.
; Based on the Mahjong overview [1] as the most important subsystem.

; Build tile_counts (34 bytes at &7C) from current player's hand.
; Counts how many of each tile type (0-33) are in the hand.
.build_tile_counts
    ; Clear tile_counts
    LDX #0
    LDA #0
.btc_clear
    STA tile_counts, X
    INX
    CPX #TILE_TYPES    ; check if all tile types scanned
    BNE btc_clear    ; more tile types to clear
    ; Count tiles from current player's hand
    LDX current_player
    JSR set_hand_ptr
    LDY num_tiles, X
    BEQ btc_done    ; no tiles to count
    DEY
.btc_count
    LDA (ptr), Y
    TAX
    INC tile_counts, X
    DEY
    BPL btc_count    ; more tiles to count
.btc_done
    RTS

; Recursive meld decomposition.
; Attempts to decompose all tiles with count > 0 into melds.
; Uses backtracking: tries triplet first, then sequence.
; Returns: C set = success (all tiles decomposed), C clear = failure.
; Preserves X on entry (caller's loop variable).
.decompose_melds
    ; Find first tile with count > 0
    LDX #0
.dm_find
    LDA tile_counts, X
    BNE dm_found    ; found a tile to decompose
    INX
    CPX #TILE_TYPES    ; check if all tile types scanned
    BNE dm_find    ; more tiles to scan
    ; All counts are zero - all tiles decomposed successfully!
    SEC
    RTS

.dm_found
    ; Save tile index on stack for backtracking
    TXA: PHA
    ; Reload count (TXA clobbered A which had the count from dm_find)
    LDA tile_counts, X

    ; Try triplet (count >= 3)
    CMP #3    ; need 3+ copies for triplet
    BCC dm_try_seq    ; not enough for triplet - try sequence

    ; Remove triplet
    SEC: SBC #3
    STA tile_counts, X
    ; Recurse
    JSR decompose_melds
    BCS dm_success    ; if decompose_melds returned carry set (error/true)
    ; Backtrack: restore triplet
    PLA: TAX            ; restore tile index
    PHA                 ; save again for potential sequence attempt
    LDA tile_counts, X
    CLC: ADC #3
    STA tile_counts, X

.dm_try_seq
    ; Skip sequences if no_seq_flag is set (for toitoi check)
    LDA no_seq_flag: BNE dm_fail

    ; Try sequence (only suited tiles 0-26)
    PLA: TAX            ; restore tile index
    PHA                 ; save again for potential backtrack
    CPX #27    ; check if tile is an honor
    BCS dm_fail    ; honor tile - can't form sequence
    ; Check sequence stays within same suit (X mod 9 <= 6)
    ; Without this, 9-man/1-pin/2-pin would be treated as a valid sequence
    TXA
.sq_mod9
    CMP #9: BCC sq_mod9_dn
    SEC: SBC #9
    JMP sq_mod9
.sq_mod9_dn
    CMP #7: BCS dm_fail    ; X mod 9 >= 7: sequence crosses suit boundary
    ; Check tiles X+1 and X+2 exist
    LDA tile_counts+1, X
    BEQ dm_fail    ; missing tile for sequence - not possible
    LDA tile_counts+2, X
    BEQ dm_fail    ; missing tile for sequence - not possible
    ; Remove sequence
    DEC tile_counts, X
    DEC tile_counts+1, X
    DEC tile_counts+2, X
    ; Recurse
    JSR decompose_melds
    BCS dm_success    ; if decompose_melds returned carry set (error/true)
    ; Backtrack: restore sequence
    PLA: TAX            ; restore tile index
    INC tile_counts, X
    INC tile_counts+1, X
    INC tile_counts+2, X
    CLC
    RTS

.dm_fail
    PLA                 ; clean up stack
    CLC
    RTS

.dm_success
    PLA                 ; clean up stack
    SEC
    RTS

; Check if a 14-tile hand (13 dealt + 1 drawn) is a winning hand.
; Standard win: 4 melds + 1 pair.
; Also checks seven pairs.
; Returns: C set = win, C clear = not a win.
; Calls build_tile_counts internally.
.check_win
    JSR build_tile_counts

    ; Try each possible pair (tile with count >= 2)
    LDX #0
.cw_try_pair
    LDA tile_counts, X
    CMP #2    ; check if enough for a pair
    BCC cw_next_pair    ; not enough for a pair - try next

    ; Remove pair from counts
    SEC: SBC #2
    STA tile_counts, X

    ; Save pair tile index on stack (tmp8 is used by decompose_melds)
    TXA: PHA

    ; Try to decompose remaining 12 tiles into 4 melds
    JSR decompose_melds
    BCS cw_win    ; if decompose_melds returned carry set (error/true)

    ; Backtrack: restore pair
    PLA: TAX            ; restore pair tile index
    PHA                 ; save it again for restore after
    LDA tile_counts, X
    CLC: ADC #2
    STA tile_counts, X
    PLA: TAX            ; restore X for the loop

.cw_next_pair
    INX
    CPX #TILE_TYPES    ; check if all tile types scanned
    BNE cw_try_pair    ; more tiles to try as pair

    ; Standard win failed - check seven pairs
    JSR check_seven_pairs
    BCS cw_win    ; if check_seven_pairs returned carry set (error/true)

    ; Not a winning hand
    CLC
    RTS

.cw_win
    PLA                 ; clean up saved X from stack
    SEC
    RTS

; Check for seven pairs win condition.
; Requires exactly 7 pairs (each tile count is 0 or 2).
; Returns: C set = seven pairs, C clear = not seven pairs.
.check_seven_pairs
    LDX #0
    LDY #0          ; pair counter
.csp_loop
    LDA tile_counts, X
    BEQ csp_next    ; no tiles here - not a pair
    CMP #2    ; check if count is exactly 2
    BNE csp_fail    ; count must be exactly 0 or 2
    INY             ; found a pair
.csp_next
    INX
    CPX #TILE_TYPES    ; check if all tile types scanned
    BNE csp_loop    ; more tiles to check
    ; Must have exactly 7 pairs
    CPY #7    ; check if exactly 7 pairs found
    BNE csp_fail    ; not 7 pairs - not seven pairs hand
    SEC
    RTS
.csp_fail
    CLC
    RTS

; Check for thirteen orphans (kokushi musou).
; Requires one of each 1-9 man, 1-9 pin, 1-9 sou, all 4 winds, all 3 dragons,
; plus one duplicate of any of these terminal/honor tiles.
; Returns: C set = thirteen orphans, C clear = not thirteen orphans.
.check_thirteen_orphans
    ; Clear tile counts
    LDX #0
    LDA #0
.cto_clear
    STA tile_counts, X
    INX
    CPX #TILE_TYPES    ; check if all tile types scanned
    BNE cto_clear    ; not zero - condition not met
    ; Count tiles from current player's hand
    LDX current_player
    JSR set_hand_ptr
    LDY num_tiles, X
    BEQ cto_fail    ; no tiles - can't be thirteen orphans
    DEY
.cto_count
    LDA (ptr), Y
    TAX
    INC tile_counts, X
    DEY
    BPL cto_count    ; more tiles to count

    ; Must have exactly 14 tiles
    LDX current_player
    LDA num_tiles, X
    CMP #HAND_SIZE    ; thirteen orphans requires exactly 14 tiles
    BNE cto_fail    ; wrong count - not kokushi

    ; Check all 13 terminal/honor tiles exist at least once
    LDY #0          ; pair found flag
    LDX #0          ; tile index
.cto_check
    LDA tile_counts, X
    BEQ cto_fail    ; missing a required tile
    CMP #1    ; check if exactly 1 copy (acceptable)
    BEQ cto_next    ; exactly 1 - acceptable
    CMP #2    ; check if enough for a pair
    BNE cto_fail    ; count > 2 not allowed
    INY             ; found pair
    CPY #2    ; check if pair count is 2
    BCS cto_fail    ; more than one pair
.cto_next
    INX
    CPX #TILE_TYPES    ; check if all tile types scanned
    BNE cto_check    ; more tiles to check
    ; Must have exactly one pair (Y = 1)
    CPY #1    ; check if exactly 1 pair found
    BNE cto_fail    ; wrong tile count - not kokushi
    SEC
    RTS
.cto_fail
    CLC
    RTS


; =============================================
; SCORING SYSTEM
; =============================================

; Main scoring entry point
.calculate_score
    LDA #0
    STA han_count: STA fu_count: STA yaku_flags: STA yaku_flags2: STA yaku_flags3
    JSR build_tile_counts

    ; Determine if hand is closed
    LDX current_player
    LDA opn_count, X
    CMP #1    ; check if exactly 1
    LDA #0
    BCS cs_set_open    ; hand is open
    LDA #1
.cs_set_open
    STA hand_closed

    ; --- TANYAO (1 han) ---
    JSR check_tanyao
    BCC cs_no_tanyao    ; if check_tanyao returned carry clear (OK/false)
    INC han_count
    LDA yaku_flags: ORA #&01: STA yaku_flags
.cs_no_tanyao

    ; --- YAKUHAI ---
    JSR check_yakuhai

    ; --- TOITOI (2 han) ---
    JSR check_toitoi
    BCC cs_no_toitoi    ; if check_toitoi returned carry clear (OK/false)
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags: ORA #&80: STA yaku_flags
.cs_no_toitoi

    ; --- CHINITSU (6 han) ---
    JSR check_chinitsu
    BCC cs_no_chi    ; if check_chinitsu returned carry clear (OK/false)
    LDA han_count: CLC: ADC #6: STA han_count
    LDA yaku_flags: ORA #&40: STA yaku_flags
    JMP cs_fu
.cs_no_chi

    ; --- HONITSU (3 han) ---
    JSR check_honitsu
    BCC cs_no_hon    ; if check_honitsu returned carry clear (OK/false)
    LDA han_count: CLC: ADC #3: STA han_count
    LDA yaku_flags: ORA #&20: STA yaku_flags
.cs_no_hon

    ; --- PINFU (1 han, closed only) ---
.cs_fu
    LDA hand_closed: BEQ cs_no_pin
    JSR check_pinfu
    BCC cs_no_pin    ; if check_pinfu returned carry clear (OK/false)
    INC han_count
    LDA yaku_flags: ORA #&02: STA yaku_flags
.cs_no_pin
    ; --- IPPATSU (1 han, closed, riichi + ippatsu flag) ---
    LDX current_player
    LDA hand_closed: BEQ cs_no_ipp
    LDA riichi_on_table, X
    AND #1: BEQ cs_no_ipp
    LDA ippatsu_flags, X
    BEQ cs_no_ipp    ; not in riichi - no ippatsu
    INC han_count
    LDA yaku_flags2: ORA #&01: STA yaku_flags2
.cs_no_ipp
    LDA hand_closed: BEQ cs_no_iip
    JSR check_iipeiko
    BCC cs_no_iip    ; if check_iipeiko returned carry clear (OK/false)
    INC han_count
    LDA yaku_flags2: ORA #&02: STA yaku_flags2
.cs_no_iip

    ; --- RYANPEIKOU (3 han, closed only) ---
    LDA hand_closed: BEQ cs_no_ryp
    JSR check_ryanpeikou
    BCC cs_no_ryp    ; if check_ryanpeikou returned carry clear (OK/false)
    LDA han_count: CLC: ADC #3: STA han_count
    LDA yaku_flags2: ORA #&80: STA yaku_flags2
.cs_no_ryp

    ; --- SANSHOKU (1 han) ---
    JSR check_sanshoku
    BCC cs_no_sans    ; if check_sanshoku returned carry clear (OK/false)
    INC han_count
    LDA yaku_flags2: ORA #&04: STA yaku_flags2
.cs_no_sans

    ; --- ITTSU (2 han) ---
    JSR check_ittsu
    BCC cs_no_itt    ; if check_ittsu returned carry clear (OK/false)
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags2: ORA #&08: STA yaku_flags2
.cs_no_itt

    ; --- CHANTA (2 han closed / 1 han open) ---
    JSR check_chanta
    BCC cs_no_cha    ; if check_chanta returned carry clear (OK/false)
    LDA hand_closed
    BEQ cs_cha_open    ; hand is open - only 1 han for chanta
    LDA han_count: CLC: ADC #2: STA han_count
    JMP cs_cha_set
.cs_cha_open
    INC han_count
.cs_cha_set
    LDA yaku_flags2: ORA #&10: STA yaku_flags2
.cs_no_cha

    ; --- SHOU SANGEN (2 han) ---
    JSR check_shousangen
    BCC cs_no_ss    ; if check_shousangen returned carry clear (OK/false)
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags2: ORA #&20: STA yaku_flags2
.cs_no_ss

    ; --- CHII TOITSU (2 han) ---
    JSR check_chitoitsu
    BCC cs_no_ct    ; if check_chitoitsu returned carry clear (OK/false)
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags2: ORA #&40: STA yaku_flags2
.cs_no_ct

    ; --- MENZEN TSUMO (1 han, closed only, self-draw) ---
    LDA hand_closed: BEQ cs_no_mt
    LDA tsumo_flag: BEQ cs_no_mt
    INC han_count
    LDA yaku_flags3: ORA #&80: STA yaku_flags3
.cs_no_mt

    ; --- SANANKOU (2 han) - three concealed triplets ---
    JSR check_sanankou
    BCC cs_no_sa    ; if check_sanankou returned carry clear (OK/false)
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags3: ORA #&01: STA yaku_flags3
.cs_no_sa

    ; --- HONROUTOU (2 han) - all terminals and honors ---
    JSR check_honroutou
    BCC cs_no_hr    ; if check_honroutou returned carry clear (OK/false)
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags3: ORA #&02: STA yaku_flags3
.cs_no_hr

    ; --- SANSHOKU DOUKOU (2 han) - same triplets across 3 suits ---
    JSR check_sanshoku_doukou
    BCC cs_no_sd    ; if check_sanshoku_doukou returned carry clear (OK/false)
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags3: ORA #&04: STA yaku_flags3
.cs_no_sd

    ; --- YAKUMAN CHECKS ---
    LDA #0: STA yakuman_flags
    STA yakuman_flags2

    ; Check Suukantsu (Four Kans)
    JSR check_suukantsu
    BCC cs_no_suuk    ; if check_suukantsu returned carry clear (OK/false)
    LDA yakuman_flags: ORA #&01: STA yakuman_flags
.cs_no_suuk

    ; Check Daisangen (Big Three Dragons)
    JSR check_daisangen
    BCC cs_no_dai    ; if check_daisangen returned carry clear (OK/false)
    LDA yakuman_flags: ORA #&02: STA yakuman_flags
.cs_no_dai

    ; Check Chinroutou (All Terminals)
    JSR check_chinroutou
    BCC cs_no_chi_rt    ; if check_chinroutou returned carry clear (OK/false)
    LDA yakuman_flags: ORA #&04: STA yakuman_flags
.cs_no_chi_rt

    ; Check Tsuuiisou (All Honors)
    JSR check_tsuuiisou
    BCC cs_no_tsui    ; if check_tsuuiisou returned carry clear (OK/false)
    LDA yakuman_flags: ORA #&08: STA yakuman_flags
.cs_no_tsui

    ; Check Daisuushii (Big Four Winds)
    JSR check_daisuushii
    BCC cs_no_daiw    ; if check_daisuushii returned carry clear (OK/false)
    LDA yakuman_flags: ORA #&20: STA yakuman_flags
.cs_no_daiw

    ; Check Shousuushii (Little Four Winds)
    JSR check_shousuushii
    BCC cs_no_shouw    ; if check_shousuushii returned carry clear (OK/false)
    LDA yakuman_flags: ORA #&10: STA yakuman_flags
.cs_no_shouw

    ; Check Tenhou (Heaven's Win)
    JSR check_tenhou
    BCC cs_no_ten    ; if check_tenhou returned carry clear (OK/false)
    LDA yakuman_flags: ORA #&40: STA yakuman_flags
.cs_no_ten

    ; Check Chiihou (Earth's Win)
    JSR check_chiihou
    BCC cs_no_chi_h    ; if check_chiihou returned carry clear (OK/false)
    LDA yakuman_flags: ORA #&80: STA yakuman_flags
.cs_no_chi_h

    ; Check Suuankou (Four Concealed Triplets)
    JSR check_suuankou
    BCC cs_no_suuank    ; if check_suuankou returned carry clear (OK/false)
    LDA yakuman_flags2
    ORA #&01
    STA yakuman_flags2
.cs_no_suuank

    ; Check Chuuren Poutou (Nine Gates)
    JSR check_chuuren
    BCC cs_no_chuuren    ; if check_chuuren returned carry clear (OK/false)
    LDA yakuman_flags2
    ORA #&02
    STA yakuman_flags2
.cs_no_chuuren

    ; Skip over subroutine definitions to reach score calculation
    JMP cs_post_yakuman

    ; TENHOU: dealer wins with initial 14 tiles (13 han yakuman)
.check_tenhou
    ; Only check if dealer's first turn
    LDX current_player
    CPX dealer: BNE cten_no
    LDA first_turn: BEQ cten_no
    JSR check_win
    BCS cten_yes    ; if check_win returned carry set (error/true)
.cten_no
    CLC: RTS
.cten_yes
    SEC: RTS

; CHIIHOU: non-dealer wins with initial 14 tiles (13 han yakuman)
.check_chiihou
    ; Only check if non-dealer's first turn
    LDX current_player
    CPX dealer: BEQ cchi_no
    LDA first_turn: BEQ cchi_no
    JSR check_win
    BCS cchi_yes    ; if check_win returned carry set (error/true)
.cchi_no
    CLC: RTS
.cchi_yes
    SEC: RTS

; SUUANKOU: four concealed triplets (13 han yakuman)
; Requires: no open melds, hand decomposes into 4 concealed triplets + 1 pair
.check_suuankou
    ; Must have no open melds
    LDX current_player
    LDA opn_count, X
    BNE suuank_no    ; open hand - can't be four concealed triplets
    ; Build tile counts from hand
    JSR build_tile_counts
    ; Try to decompose into all triplets
    JSR decompose_melds_all_triples
    BCC suuank_no    ; if decompose_melds_all_triples returned carry clear (OK/false)
    ; Verify exactly 2 tiles remain (a pair)
    LDX current_player
    JSR check_win
    BCC suuank_no    ; if check_win returned carry clear (OK/false)
    SEC: RTS
.suuank_no
    CLC: RTS

; Helper: Check if hand decomposes into only triplets
; Uses tile_counts, modifies temp storage
.decompose_melds_all_triples
    LDX #0
    STX tmp9
.suank_dm_scan
    CPX #TILE_TYPES    ; check if all tile types scanned
    BEQ suank_dm_check    ; all tiles scanned - verify result
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC suank_dm_next    ; not enough for triplet - skip
    ; Found a triplet - remove it
    SEC: SBC #3
    STA tile_counts, X
    INC tmp9
    LDA tmp9
    CMP #4    ; check if count is 4
    BEQ suank_dm_check    ; all tiles scanned - verify result
    JMP suank_dm_scan
.suank_dm_next
    INX
    JMP suank_dm_scan
.suank_dm_check
    LDX #0
    LDA #0
.suank_dm_sum
    CLC: ADC tile_counts, X
    INX: CPX #TILE_TYPES: BNE suank_dm_sum
    CMP #2    ; check if exactly 2 tiles remain (pair)
    BEQ suank_dm_yes    ; exactly a pair remaining - success
    CLC: RTS
.suank_dm_yes
    SEC: RTS

; CHUUREN POUTOU: Nine Gates (13 han yakuman)
; Exactly 1-1-1-2-3-4-5-6-7-8-9-9-9 of one suit + any 14th tile of same suit
.check_chuuren
    JSR build_tile_counts
    ; Try man tiles (0-8)
    LDY #0
    JSR cp_check_suit
    BCS cp_win    ; if cp_check_suit returned carry set (error/true)
    ; Try pin tiles (9-17)
    LDY #9
    JSR cp_check_suit
    BCS cp_win    ; if cp_check_suit returned carry set (error/true)
    ; Try sou tiles (18-26)
    LDY #18
    JSR cp_check_suit
    BCS cp_win    ; if cp_check_suit returned carry set (error/true)
    CLC: RTS
.cp_win
    SEC: RTS

; Check if suit starting at Y forms nine gates pattern
; Y = start tile index (0, 9, or 18)
; Returns C set if this suit is nine gates
.cp_check_suit
    STY tmp9
    ; Count total tiles in this suit
    LDX #0
    LDA #0
.cp_sum
    CLC: ADC tile_counts, Y
    INY
    INX: CPX #9: BNE cp_sum
    CMP #14    ; check if suit has exactly 14 tiles
    BNE cp_fail    ; wrong tile count for nine gates
    ; Check each tile count matches 9-gates pattern
    ; Pattern: 3,1,1,1,1,1,1,1,3 (+ one extra somewhere)
    LDY tmp9
    LDX #0
    LDA #0
    STA tmp8
.cp_pat
    LDA tile_counts, Y
    ; Positions 0 and 8 (first and last) must be 3 or 4
    CPX #0: BEQ cp_edge
    CPX #8: BEQ cp_edge
    ; Inner positions must be 1 or 2
    CMP #1: BCC cp_fail
    CMP #3: BCS cp_fail
    CMP #2: BNE cp_pat_nxt
    INC tmp8
    JMP cp_pat_nxt
.cp_edge
    CMP #3: BCC cp_fail
    CMP #5: BCS cp_fail
    CMP #4: BNE cp_pat_nxt
    INC tmp8
.cp_pat_nxt
    INY: INX: CPX #9: BNE cp_pat
    ; Exactly one tile position must have the extra tile
    LDA tmp8
    CMP #1    ; check if exactly 1
    BNE cp_fail    ; wrong tile count for nine gates
    SEC: RTS
.cp_fail
    CLC: RTS

.cs_post_yakuman
    ; If any yakuman detected, set han_count to 13 and skip fu calculation
    LDA yakuman_flags
    BNE cs_is_yakuman    ; yakuman detected - set han to 13
    LDA yakuman_flags2
    BEQ cs_no_yakuman    ; no yakuman - proceed to fu calculation
.cs_is_yakuman
    LDA #13: STA han_count
    JMP compute_points
.cs_no_yakuman

        JSR calculate_fu
        JSR compute_points
        RTS

; =============================================
; YAKU DETECTION
; =============================================

; TANYAO: all simples (no terminals/honors)
.check_tanyao
    LDX #0
.ct_loop
    LDA tile_counts, X
    BEQ ct_next    ; no tiles of this type - OK for tanyao
    CPX #0: BEQ ct_fail
    CPX #8: BEQ ct_fail
    CPX #9: BEQ ct_fail
    CPX #17: BEQ ct_fail
    CPX #18: BEQ ct_fail
    CPX #26: BEQ ct_fail
    CPX #27: BCS ct_fail
.ct_next
    INX: CPX #TILE_TYPES: BNE ct_loop
    SEC: RTS
.ct_fail
    CLC: RTS

; YAKUHAI: check pair and open melds for value tiles
.check_yakuhai
    LDX #0
.cy_pair
    LDA tile_counts, X
    CMP #2: BNE cy_pnext
    JSR is_yakuhai_tile
    BCC cy_pnext    ; if is_yakuhai_tile returned carry clear (OK/false)
    INC han_count
.cy_pnext
    INX: CPX #TILE_TYPES: BNE cy_pair

    ; Check open melds
    LDX current_player
    LDA opn_count, X
    BEQ cy_done    ; no open melds to check
    STA tmp8
    TXA: ASL A: ASL A: STA tmp9
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp9: STA tmp9
    LDY #0
.cy_omlp
    CPY tmp8: BCS cy_done
    STY tmp
    TYA: ASL A: ASL A: CLC: ADC tmp
    CLC: ADC tmp9: TAX
    INX
    LDA opn_melds, X
    TAX
    JSR is_yakuhai_tile
    BCC cy_onext    ; if is_yakuhai_tile returned carry clear (OK/false)
    INC han_count
.cy_onext
    LDY tmp: INY
    JMP cy_omlp
.cy_done
    RTS

; Check if tile X is yakuhai
.is_yakuhai_tile
    TXA: PHA
    CPX #31: BCS iy_yes
    CPX #27: BCC iy_not
    ; Wind tiles 27-30: check seat and round wind
    TXA: SEC: SBC #27
    CMP current_player: BEQ iy_yes
    TXA: CMP round_wind: BEQ iy_yes
.iy_not
    PLA: TAX
    CLC: RTS
.iy_yes
    PLA: TAX
    SEC: RTS

; TOITOI: all melds are triplets (no sequences)
.check_toitoi
    LDX current_player
    LDA opn_count, X
    BEQ ctt_check    ; no open melds - check hand for triplets

    TXA: ASL A: ASL A: STA tmp
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp: STA tmp
    LDY opn_count, X: DEY
.ctt_omlp
    STY tmp2
    TYA: ASL A: ASL A: CLC: ADC tmp2
    CLC: ADC tmp: TAX
    INX
    LDA opn_melds, X: STA tmp3
    INX: LDA opn_melds, X
    CMP tmp3: BNE ctt_no
    INX: LDA opn_melds, X
    CMP tmp3: BNE ctt_no
    LDY tmp2: DEY: BPL ctt_omlp

.ctt_check
    JSR build_tile_counts
    LDX #0
.ctt_try
    LDA tile_counts, X
    CMP #2: BCC ctt_next
    SEC: SBC #2: STA tile_counts, X
    TXA: PHA
    LDA #1: STA no_seq_flag
    JSR decompose_melds
    LDA #0: STA no_seq_flag
    BCS ctt_found    ; carry set
    PLA: TAX: PHA
    LDA tile_counts, X: CLC: ADC #2: STA tile_counts, X
    PLA: TAX
.ctt_next
    INX: CPX #TILE_TYPES: BNE ctt_try
    CLC: RTS
.ctt_found
    PLA
    SEC: RTS
.ctt_no
    CLC: RTS

; COUNT SUITS
.count_suits
    LDA #0: STA tmp
    LDX #0: JSR cs_has: BCC cs_mn
    INC tmp
.cs_mn
    LDX #9: JSR cs_has: BCC cs_pn
    INC tmp
.cs_pn
    LDX #18: JSR cs_has: BCC cs_dn
    INC tmp
.cs_dn
    LDA tmp
    RTS

.cs_has
    LDY #0
.csh_lp
    LDA tile_counts, X
    BNE csh_yes    ; this suit is present in the hand
    INX: INY: CPY #9: BNE csh_lp
    CLC: RTS
.csh_yes
    SEC: RTS

; HONITSU: one suit + honors
.check_honitsu
    JSR count_suits
    CMP #1: BNE ch_no
    LDX #27: LDA #0
.ch_hon
    ORA tile_counts, X: INX: CPX #TILE_TYPES: BNE ch_hon
    BEQ ch_no    ; no honor tiles - not honitsu
    SEC: RTS
.ch_no
    CLC: RTS

; CHINITSU: one suit, no honors
.check_chinitsu
    JSR count_suits
    CMP #1: BNE cc_no
    LDX #27: LDA #0
.cc_hon
    ORA tile_counts, X: INX: CPX #TILE_TYPES: BNE cc_hon
    BNE cc_no    ; honor tiles present - not chinitsu
    SEC: RTS
.cc_no
    CLC: RTS

; PINFU: closed hand, all sequences, pair not yakuhai
.check_pinfu
    LDA hand_closed: BEQ cp_no
    JSR build_tile_counts
    LDX #0
.cp_pair
    LDA tile_counts, X
    CMP #2: BNE cp_pnext
    JSR is_yakuhai_tile
    BCS cp_no    ; if is_yakuhai_tile returned carry set (error/true)
    LDA #0: STA tile_counts, X
    LDY #0
.cp_trip
    LDA tile_counts, Y
    CMP #3: BCS cp_no
    INY: CPY #TILE_TYPES: BNE cp_trip
    SEC: RTS
.cp_pnext
    INX: CPX #TILE_TYPES: BNE cp_pair
.cp_no
    CLC: RTS

; =============================================
; NEW YAKU DETECTION (7 additional yaku)
; =============================================

; IIPPEIKO: two identical sequences (closed only)
; Check: find a sequence (i, i+1, i+2), then check if the same sequence exists again
.check_iipeiko
    LDA hand_closed: BEQ ci_no
    JSR build_tile_counts
.ci_restart
    LDX #0
.ci_outer
    CPX #27: BCS ci_no
    LDA tile_counts, X
    CMP #2: BCC ci_next
    ; Check for sequence starting at X
    INX: LDA tile_counts, X
    CMP #2: BCC ci_next2
    INX: LDA tile_counts, X
    CMP #2: BCC ci_next3
    ; Found first sequence at X-2, X-1, X
    ; Check for second identical sequence
    TXA: SEC: SBC #2: TAY
    ; Remove first sequence temporarily
    LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    ; Now check if remaining tiles form valid hand (3 melds + 1 pair)
    JSR decompose_melds
    BCS ci_found    ; if decompose_melds returned carry set (error/true)
    ; Restore first sequence
    TXA: SEC: SBC #2: TAY
    LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
.ci_next3
    DEX
.ci_next2
    DEX
.ci_next
    INX: JMP ci_outer
.ci_found
    SEC: RTS
.ci_no
    CLC: RTS

; RYANPEIKOU: two pairs of identical sequences (closed only)
; Check: find two pairs of identical sequences, remaining must be exactly one pair
.check_ryanpeikou
    LDA hand_closed: BNE crp_have_closed
    JMP crp_no
.crp_have_closed
    JSR build_tile_counts
    ; Find first pair of identical sequences
    LDX #0
.crp_outer1
    CPX #27: BCC crp_try1
    JMP crp_no
.crp_try1
    LDA tile_counts, X
    CMP #2: BCS crp_have_a1
    JMP crp_next1
.crp_have_a1
    INX: LDA tile_counts, X
    CMP #2: BCS crp_have_b1
    JMP crp_next1b
.crp_have_b1
    INX: LDA tile_counts, X
    CMP #2: BCS crp_have_c1
    JMP crp_next1c
.crp_have_c1
    ; Found first pair at X-2, X-1, X - save X and remove pair
    STX tmp5
    TXA: SEC: SBC #2: TAY
    LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    ; Find second pair of identical sequences
    LDX #0
.crp_outer2
    CPX #27: BCC crp_try2
    JMP crp_restore1
.crp_try2
    LDA tile_counts, X
    CMP #2: BCS crp_have_a2
    JMP crp_next2
.crp_have_a2
    INX: LDA tile_counts, X
    CMP #2: BCS crp_have_b2
    JMP crp_next2b
.crp_have_b2
    INX: LDA tile_counts, X
    CMP #2: BCS crp_have_c2
    JMP crp_next2c
.crp_have_c2
    ; Found second pair at X-2, X-1, X - remove pair
    TXA: SEC: SBC #2: TAY
    LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    ; Check if remaining is exactly one pair
    JSR check_single_pair
    BCS crp_found    ; if check_single_pair returned carry set (error/true)
    ; Restore second pair
    TXA: SEC: SBC #2: TAY
    LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
.crp_next2c
    DEX
.crp_next2b
    DEX
.crp_next2
    INX: JMP crp_outer2
.crp_restore1
    ; Restore first pair
    LDX tmp5
    TXA: SEC: SBC #2: TAY
    LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: CLC: ADC #2: STA tile_counts, Y
.crp_next1c
    DEX
.crp_next1b
    DEX
.crp_next1
    INX: JMP crp_outer1
.crp_found
    SEC: RTS
.crp_no
    CLC: RTS


; Check if tile_counts has exactly one tile with count 2, rest zero
.check_single_pair
    LDX #0
    LDY #0
.crsp_loop
    CPX #TILE_TYPES: BCS crsp_done
    LDA tile_counts, X
    BEQ crsp_next    ; no tiles here - not the pair
    CMP #2: BNE crsp_fail
    INY
.crsp_next
    INX: JMP crsp_loop
.crsp_done
    CPY #1: BEQ crsp_yes
    CLC: RTS
.crsp_yes
    SEC: RTS
.crsp_fail
    CLC: RTS

; SANSHOKU: three identical sequences in different suits
; Check: for each sequence (1-9) in man suit, check if same exists in pin and sou
.check_sanshoku
    JSR build_tile_counts
    LDY #0
.cs_outer
    CPY #9: BCS cs_no
    LDA tile_counts, Y
    BEQ cs_next    ; no tiles at this sequence position
    INY: LDA tile_counts, Y
    BEQ cs_next2    ; no tiles at this sequence position
    INY: LDA tile_counts, Y
    BEQ cs_next3    ; no tiles at this sequence position
    ; Found sequence in man (Y-2, Y-1, Y)
    ; Check pin (Y+7, Y+8, Y+9)
    TYA: CLC: ADC #7: TAX
    LDA tile_counts, X: BEQ cs_next3
    INX: LDA tile_counts, X: BEQ cs_next3
    INX: LDA tile_counts, X: BEQ cs_next3
    ; Check sou (Y+16, Y+17, Y+18)
    TYA: CLC: ADC #16: TAX
    LDA tile_counts, X: BEQ cs_next3
    INX: LDA tile_counts, X: BEQ cs_next3
    INX: LDA tile_counts, X: BEQ cs_next3
    SEC: RTS
.cs_next3
    DEY
.cs_next2
    DEY
.cs_next
    INY: JMP cs_outer
.cs_no
    CLC: RTS

; ITTSU (Straight): sequences 123, 456, 789 in one suit
.check_ittsu
    JSR build_tile_counts
    ; Try man suit (0-8)
    LDX #0: JSR ci_check_straight: BCS ci_yes
    ; Try pin suit (9-17)
    LDX #9: JSR ci_check_straight: BCS ci_yes
    ; Try sou suit (18-26)
    LDX #18: JSR ci_check_straight
.ci_yes
    RTS

; Helper: check if suit starting at X has 123, 456, 789
.ci_check_straight
    STX tmp
    LDA tile_counts, X: BEQ ci_cs_no
    INX: LDA tile_counts, X: BEQ ci_cs_no
    INX: LDA tile_counts, X: BEQ ci_cs_no
    LDX tmp: TXA: CLC: ADC #3: TAX
    LDA tile_counts, X: BEQ ci_cs_no
    INX: LDA tile_counts, X: BEQ ci_cs_no
    INX: LDA tile_counts, X: BEQ ci_cs_no
    LDX tmp: TXA: CLC: ADC #6: TAX
    LDA tile_counts, X: BEQ ci_cs_no
    INX: LDA tile_counts, X: BEQ ci_cs_no
    INX: LDA tile_counts, X: BEQ ci_cs_no
    SEC: RTS
.ci_cs_no
    CLC: RTS

; CHANTA: all melds contain terminals/honors, pair is terminal/honor
.check_chanta
    JSR build_tile_counts
    ; Find the pair - must be terminal or honor
    LDX #0
.ct_pair
    LDA tile_counts, X
    CMP #2: BNE ct_pnext
    JSR is_terminal_or_honor
    BCC ct_pnext    ; if is_terminal_or_honor returned carry clear (OK/false)
    ; Pair is terminal/honor, now check all melds
    ; Temporarily remove pair
    TXA: PHA
    LDA tile_counts, X: SEC: SBC #2: STA tile_counts, X
    PLA: TAX
    ; Check all remaining melds contain terminals/honors
    LDY #0
.ct_mcheck
    CPY #TILE_TYPES: BCS ct_mcheck_done
    LDA tile_counts, Y
    BEQ ct_mcheck_next    ; no tiles here - skip
    JSR is_terminal_or_honor
    BCC ct_mcheck_fail    ; if is_terminal_or_honor returned carry clear (OK/false)
.ct_mcheck_next
    INY: JMP ct_mcheck
.ct_mcheck_done
    ; Restore pair
    LDX #0
.ct_restore
    LDA tile_counts, X
    CMP #2: BNE ct_rnext
    TXA: PHA
    LDA tile_counts, X: CLC: ADC #2: STA tile_counts, X
    PLA: TAX
    SEC: RTS
.ct_rnext
    INX: JMP ct_restore
.ct_pnext
    INX: CPX #TILE_TYPES: BNE ct_pair
    CLC: RTS
.ct_mcheck_fail
.ct_restore2
    LDA tile_counts, X
    CMP #2: BNE ct_r2next
    TXA: PHA
    LDA tile_counts, X: CLC: ADC #2: STA tile_counts, X
    PLA: TAX
    CLC: RTS
.ct_r2next
    INX: JMP ct_restore2

; SHOU SANGEN: two dragon triplets + dragon pair (or three dragon triplets)
.check_shousangen
    LDA #0: STA tmp
    JSR build_tile_counts
    ; Check dragons 31(Hatsu), 32(Haku), 33(Chun)
    LDX #31: LDA tile_counts, X: CMP #3: BCS cs_d3
    LDX #32: LDA tile_counts, X: CMP #3: BCS cs_d3
    CLC: RTS
.cs_d3
    ; Count dragon triplets and pairs
    LDX #31: LDA tile_counts, X: CMP #3: BCS cs_d3a
    CMP #2: BCC cs_d3a
    INC tmp
.cs_d3a
    LDX #32: LDA tile_counts, X: CMP #3: BCS cs_d3b
    CMP #2: BCC cs_d3b
    INC tmp
.cs_d3b
    LDX #33: LDA tile_counts, X: CMP #3: BCS cs_d3c
    CMP #2: BCC cs_d3c
    INC tmp
.cs_d3c
    ; Need at least 2 dragon groups (triplets or pairs)
    LDA tmp
    CMP #2: BCS cs_ss_yes
    CLC: RTS
.cs_ss_yes
    SEC: RTS

; CHII TOITSU: seven pairs (2 han)
.check_chitoitsu
    JSR build_tile_counts
    LDX #0: STX tmp
.ct_pair2
    LDA tile_counts, X
    CMP #2: BEQ ct_ppair
    CMP #4: BEQ ct_ppair
    CLC: RTS
.ct_ppair
    INC tmp
    INX: CPX #TILE_TYPES: BNE ct_pair2
    LDA tmp
    CMP #7: BNE ct_no7
    SEC: RTS
.ct_no7
    CLC: RTS


; =============================================
; NEW YAKU DETECTION (4 additional yaku)
; =============================================

; SANANKOU: three concealed triplets (2 han)
; A concealed triplet is a triplet of tiles held in hand (not from open melds).
; We check by finding tiles with count >= 3 in tile_counts.
; The pair tile (count 2) must be excluded from the count.
.check_sanankou
    JSR build_tile_counts
    ; Remove pair from tile_counts
    LDX #0
.csa_find_pair
    LDA tile_counts, X
    CMP #2: BEQ csa_found_pair
    INX: CPX #TILE_TYPES: BNE csa_find_pair
    JMP csa_count
.csa_found_pair
    LDA #0: STA tile_counts, X
.csa_count
    ; Count triplets (concealed = all 3 in hand)
    LDX #0: STX tmp
.csa_loop
    LDA tile_counts, X
    CMP #3: BCC csa_next
    INC tmp
.csa_next
    INX: CPX #TILE_TYPES: BNE csa_loop
    ; Restore the pair to 2 for later use
    LDX #0
.csa_restore
    LDA tile_counts, X: CMP #0: BEQ csa_rnext
    INX: CPX #TILE_TYPES: BNE csa_restore
.csa_rnext
    LDA #2: STA tile_counts, X
    ; Check if we have 3 or more concealed triplets
    LDA tmp
    CMP #3: BCS csa_yes
    CLC: RTS
.csa_yes
    SEC: RTS

; HONROUTOU: all terminals and honors (2 han)
; Every tile in the hand must be a terminal (1 or 9 of any suit) or honor tile
.check_honroutou
    JSR build_tile_counts
    LDX #0
.chr_loop
    LDA tile_counts, X
    BEQ chr_next    ; no tiles of this type - OK
    TXA: JSR is_terminal_or_honor_a
    BCC chr_fail    ; tile is not terminal/honor - fail
.chr_next
    INX: CPX #TILE_TYPES: BNE chr_loop
    SEC: RTS
.chr_fail
    CLC: RTS

; Helper: is tile value in A terminal or honor? Returns C set if yes.
.is_terminal_or_honor_a
    CMP #0: BEQ ita_yes
    CMP #8: BEQ ita_yes
    CMP #9: BEQ ita_yes
    CMP #17: BEQ ita_yes
    CMP #18: BEQ ita_yes
    CMP #26: BEQ ita_yes
    CMP #27: BCS ita_yes
    CLC: RTS
.ita_yes
    SEC: RTS

; SANSHOKU DOUKOU: same triplets across all 3 suits (2 han)
; For each number 1-9, check if there's a triplet in all 3 suits (man, pin, sou)
.check_sanshoku_doukou
    JSR build_tile_counts
    LDY #0
.csd_outer
    CPY #9: BCS csd_no
    ; Check man (Y), pin (Y+9), sou (Y+18)
    LDA tile_counts, Y
    CMP #3: BCC csd_next
    TYA: CLC: ADC #9: TAX
    LDA tile_counts, X
    CMP #3: BCC csd_next
    TYA: CLC: ADC #18: TAX
    LDA tile_counts, X
    CMP #3: BCC csd_next
    SEC: RTS
.csd_next
    INY: JMP csd_outer
.csd_no
    CLC: RTS


; =============================================
; YAKUMAN DETECTION
; =============================================

; SUUKANTSU: four kans (13 han yakuman)
; Check if current player has declared 4 kans
.check_suukantsu
    LDX current_player
    LDA player_kans, X
    CMP #4    ; check if count is 4
    BCS csu_yes    ; 4 or more kans - suukantsu!
    CLC
    RTS
.csu_yes
    SEC
    RTS

; Daisangen: big three dragons (13 han yakuman)
; All three dragon triplets (Hatsu=31, Haku=32, Chun=33) must exist
; Checks both hand tiles and open melds
.check_daisangen
    JSR build_tile_counts
    ; Add open meld dragon tiles to counts
    LDX current_player
    LDA opn_count, X
    BEQ cd_check_hand    ; no open melds - check hand only
    STA tmp8
    TXA: ASL A: ASL A: STA tmp9
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp9: STA tmp9
    LDY #0
.cd_open_lp
    CPY tmp8: BCS cd_check_hand
    STY tmp
    TYA: ASL A: ASL A: CLC: ADC tmp
    CLC: ADC tmp9: TAX
    INX
    LDA opn_melds, X
    ; Check if it's a dragon tile
    CMP #31: BCC cd_open_next
    CMP #TILE_TYPES: BCS cd_open_next
    ; It's a dragon - add 3 to count (triplet in open meld)
    TAX
    LDA tile_counts, X: CLC: ADC #3: STA tile_counts, X
.cd_open_next
    LDY tmp: INY
    JMP cd_open_lp
.cd_check_hand
    ; Check all three dragons have count >= 3
    LDX #31
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cd_no    ; triplet missing
    LDX #32
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cd_no    ; triplet missing
    LDX #33
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cd_no    ; triplet missing
    SEC
    RTS
.cd_no
    CLC
    RTS

; Chinroutou: all terminals (13 han yakuman)
; Every tile must be a terminal (1 or 9 of any suit)
; No honor tiles or simple tiles allowed
.check_chinroutou
    JSR build_tile_counts
    LDX #0
.ccr_loop
    LDA tile_counts, X
    BEQ ccr_next    ; no tiles of this type - OK
    ; Check if tile is a terminal (0, 8, 9, 17, 18, 26)
    CPX #0: BEQ ccr_next
    CPX #8: BEQ ccr_next
    CPX #9: BEQ ccr_next
    CPX #17: BEQ ccr_next
    CPX #18: BEQ ccr_next
    CPX #26: BEQ ccr_next
    ; Not a terminal - fail
    CLC
    RTS
.ccr_next
    INX
    CPX #TILE_TYPES    ; check if all tile types scanned
    BNE ccr_loop    ; more tile types to check
    SEC
    RTS

; Tsuuiisou: all honors (13 han yakuman)
; Every tile must be an honor tile (values 27-33)
; No suit tiles allowed
.check_tsuuiisou
    JSR build_tile_counts
    LDX #0
.ctu_loop
    LDA tile_counts, X
    BEQ ctu_next    ; no tiles here - OK for all honors
    ; Check if tile is an honor (27-33)
    CPX #27    ; check if tile is an honor
    BCS ctu_next    ; it's an honor tile - OK
    ; Not an honor - fail
    CLC
    RTS
.ctu_next
    INX
    CPX #TILE_TYPES    ; check if all tile types scanned
    BNE ctu_loop    ; more tiles to check
    SEC
    RTS

; Daisuushii: big four winds (13 han yakuman)
; All four wind triplets (East=27, South=28, West=29, North=30)
; Checks both hand tiles and open melds
.check_daisuushii
    JSR build_tile_counts
    ; Add open meld wind tiles to counts
    LDX current_player
    LDA opn_count, X
    BEQ cds_check_hand    ; no open melds - check hand only
    STA tmp8
    TXA: ASL A: ASL A: STA tmp9
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp9: STA tmp9
    LDY #0
.cds_open_lp
    CPY tmp8: BCS cds_check_hand
    STY tmp
    TYA: ASL A: ASL A: CLC: ADC tmp
    CLC: ADC tmp9: TAX
    INX
    LDA opn_melds, X
    ; Check if it's a wind tile (27-30)
    CMP #27: BCC cds_open_next
    CMP #31: BCS cds_open_next
    ; It's a wind - add 3 to count (triplet in open meld)
    TAX
    LDA tile_counts, X: CLC: ADC #3: STA tile_counts, X
.cds_open_next
    LDY tmp: INY
    JMP cds_open_lp
.cds_check_hand
    ; Check all four winds have count >= 3
    LDX #27
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cds_no    ; triplet missing
    LDX #28
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cds_no    ; triplet missing
    LDX #29
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cds_no    ; triplet missing
    LDX #30
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cds_no    ; triplet missing
    SEC
    RTS
.cds_no
    CLC
    RTS

; Shousuushii: little four winds (13 han yakuman)
; Three wind triplets + one wind pair
; Checks both hand tiles and open melds
.check_shousuushii
    JSR build_tile_counts
    ; Add open meld wind tiles to counts
    LDX current_player
    LDA opn_count, X
    BEQ csss_check_hand    ; no open melds - check hand only
    STA tmp8
    TXA: ASL A: ASL A: STA tmp9
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp9: STA tmp9
    LDY #0
.csss_open_lp
    CPY tmp8: BCS csss_check_hand
    STY tmp
    TYA: ASL A: ASL A: CLC: ADC tmp
    CLC: ADC tmp9: TAX
    INX
    LDA opn_melds, X
    ; Check if it's a wind tile (27-30)
    CMP #27: BCC csss_open_next
    CMP #31: BCS csss_open_next
    ; It's a wind - add 3 to count (triplet in open meld)
    TAX
    LDA tile_counts, X: CLC: ADC #3: STA tile_counts, X
.csss_open_next
    LDY tmp: INY
    JMP csss_open_lp
.csss_check_hand
    ; Count wind triplets and wind pairs
    LDX #27
    LDA #0: STA tmp8  ;\ triplet count
    LDA #0: STA tmp9  ;\ pair count
    LDX #27
.csss_count_lp
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC csss_not_triplet    ; not a triplet
    ; Count as triplet
    INC tmp8
    JMP csss_next_tile
.csss_not_triplet
    CMP #2    ; check if count >= 2 (pair)
    BCC csss_next_tile    ; not a pair either - skip
    ; Count as pair
    INC tmp9
.csss_next_tile
    INX
    CPX #31    ; check if all 4 wind tiles checked
    BNE csss_count_lp    ; more wind tiles to check
    ; Need exactly 3 triplets and 1 pair
    LDA tmp8
    CMP #3    ; need 3+ copies for triplet
    BNE csss_no    ; wrong triplet or pair count
    LDA tmp9
    CMP #1    ; check if exactly 1
    BNE csss_no    ; wrong triplet or pair count
    SEC
    RTS
.csss_no
    CLC
    RTS


; =============================================
; FU CALCULATION
; =============================================

.calculate_fu
    LDA #30: STA fu_count

    LDX #0
.cf_pair
    LDA tile_counts, X
    CMP #2: BNE cf_pnext
    JSR is_yakuhai_tile
    BCC cf_pnext    ; if is_yakuhai_tile returned carry clear (OK/false)
    LDA fu_count: CLC: ADC #2: STA fu_count
    JMP cf_melds
.cf_pnext
    INX: CPX #TILE_TYPES: BNE cf_pair

.cf_melds
    LDX current_player
    LDA opn_count, X
    BEQ cf_closed    ; hand is closed - use closed meld fu values

    TXA: ASL A: ASL A: STA tmp
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp: STA tmp
    LDY opn_count, X: DEY
.cf_open_lp
    STY tmp2
    TYA: ASL A: ASL A: CLC: ADC tmp2
    CLC: ADC tmp: TAX
    INX
    LDA opn_melds, X
    JSR is_terminal_or_honor
    BCC cf_open_s    ; if is_terminal_or_honor returned carry clear (OK/false)
    LDA fu_count: CLC: ADC #4: STA fu_count
    JMP cf_open_next
.cf_open_s
    LDA fu_count: CLC: ADC #2: STA fu_count
.cf_open_next
    LDY tmp2: DEY: BPL cf_open_lp
    JMP cf_win_bonus

.cf_closed
    LDX #0
.cf_clp
    LDA tile_counts, X
    CMP #3: BNE cf_cnext
    JSR is_terminal_or_honor
    BCC cf_csimp    ; if is_terminal_or_honor returned carry clear (OK/false)
    LDA fu_count: CLC: ADC #8: STA fu_count
    JMP cf_cnext
.cf_csimp
    LDA fu_count: CLC: ADC #4: STA fu_count
.cf_cnext
    INX: CPX #TILE_TYPES: BNE cf_clp

.cf_win_bonus
    LDA ron_flag: BEQ cf_no_ron
    LDA fu_count: CLC: ADC #2: STA fu_count
.cf_no_ron

    LDA yaku_flags: AND #&02: BEQ cf_not_pin
    LDA tsumo_flag: BEQ cf_not_pin
    LDA #20: STA fu_count
    JMP cf_round
.cf_not_pin

.cf_round
    LDA fu_count: CLC: ADC #9
    LDY #0
.cf_div
    CMP #10: BCC cf_divdn
    SEC: SBC #10: INY: JMP cf_div
.cf_divdn
    TYA: STA tmp
    LDA #0
.cf_mul
    CLC: ADC #10: DEC tmp: BNE cf_mul
    STA fu_count
    CMP #30: BCS cf_done
    LDA #30: STA fu_count
.cf_done
    RTS

; Check if tile A is terminal or honor
.is_terminal_or_honor
    CMP #0: BEQ itoh_y
    CMP #8: BEQ itoh_y
    CMP #9: BEQ itoh_y
    CMP #17: BEQ itoh_y
    CMP #18: BEQ itoh_y
    CMP #26: BEQ itoh_y
    CMP #27: BCS itoh_y
    CLC: RTS
.itoh_y
    SEC: RTS

; =============================================
; SCORE FORMULA
; =============================================

.compute_points
    LDA fu_count: ASL A: ASL A
    STA score_lo
    LDA #0: STA score_hi

    LDX han_count: BEQ cp_lim
.cp_mul
    ASL score_lo: ROL score_hi
    DEX: BNE cp_mul

.cp_lim
    LDA score_hi
    CMP #>(2000): BCC cp_chk_han
    BNE cp_limit_chk    ; score exceeds 2000 base
    LDA score_lo: CMP #<(2000): BCC cp_chk_han

.cp_limit_chk
    LDA han_count
    CMP #6: BCC cp_set_mangan
    CMP #8: BCS cp_baiman
    LDA #<(3000): STA score_lo
    LDA #>(3000): STA score_hi
    JMP cp_done
.cp_baiman
    CMP #11: BCS cp_sanbaiman
    LDA #<(4000): STA score_lo
    LDA #>(4000): STA score_hi
    JMP cp_done
.cp_sanbaiman
    CMP #13: BCS cp_yakuman
    LDA #<(6000): STA score_lo
    LDA #>(6000): STA score_hi
    JMP cp_done
.cp_yakuman
    LDA #<(8000): STA score_lo
    LDA #>(8000): STA score_hi
    JMP cp_done

.cp_chk_han
    LDA han_count: CMP #5: BCC cp_done

.cp_set_mangan
    LDA #<(2000): STA score_lo
    LDA #>(2000): STA score_hi
.cp_done
    RTS

; =============================================
; WIN DETECTION (Tsumo/Ron)
; =============================================

.check_tsumo
    INC dbg_tsumo_calls
    JSR check_win
    BCS cts_win    ; if check_win returned carry set (error/true)
    CLC: RTS
.cts_win
    LDA #1: STA tsumo_flag
    LDA #0: STA ron_flag
    SEC: RTS

.check_ron
    INC dbg_ron_calls
    LDX #0
.cr_loop
    STX tmp5
    CPX disc_tile_player: BEQ cr_next
    JSR count_tiles_for_player
    LDY disc_tile_val
    LDA tile_counts, Y: CLC: ADC #1: STA tile_counts, Y
    JSR check_win_no_rebuild
    BCS cr_found    ; if check_win_no_rebuild returned carry set (error/true)
    LDY disc_tile_val
    LDA tile_counts, Y: SEC: SBC #1: STA tile_counts, Y
.cr_next
    LDX tmp5: INX
    CPX #NUM_PLAYERS: BNE cr_loop
    CLC: RTS
.cr_found
    LDA tmp5: STA ron_player
    LDA #0: STA tsumo_flag
    LDA #1: STA ron_flag
    SEC: RTS

.check_win_no_rebuild
    LDX #0
.cwnr_try
    LDA tile_counts, X
    CMP #2: BCC cwnr_next
    SEC: SBC #2: STA tile_counts, X
    TXA: PHA
    JSR decompose_melds
    BCS cwnr_win    ; if decompose_melds returned carry set (error/true)
    PLA: TAX: PHA
    LDA tile_counts, X: CLC: ADC #2: STA tile_counts, X
    PLA: TAX
.cwnr_next
    INX: CPX #TILE_TYPES: BNE cwnr_try
    CLC: RTS
.cwnr_win
    PLA
    SEC: RTS

; =============================================
; SCORE DISPLAY
; =============================================

.display_score_result
    LDA #12: JSR oswrch

    LDA tsumo_flag: BEQ dsr_ron
    LDY #0
.dsr_tmsg
    LDA tsumo_msg, Y: BEQ dsr_tmsg_dn
    JSR oswrch: INY: JMP dsr_tmsg
.dsr_tmsg_dn
    JMP dsr_player
.dsr_ron
    LDY #0
.dsr_rmsg
    LDA ron_msg, Y: BEQ dsr_rmsg_dn
    JSR oswrch: INY: JMP dsr_rmsg
.dsr_rmsg_dn

.dsr_player
    ; Print " P" followed by player number (1-4)
    LDA #' ': JSR oswrch
    LDA #'P': JSR oswrch
    LDA current_player: CLC: ADC #1: CLC: ADC #'0': JSR oswrch

.dsr_yaku
    JSR osnewl
    LDA yaku_flags: AND #&01: BEQ dsr_no_tan
    LDY #0
.dsr_tan
    LDA yaku_tan_str, Y: BEQ dsr_tan_dn
    JSR oswrch: INY: JMP dsr_tan
.dsr_tan_dn
    JSR osnewl
.dsr_no_tan

    LDA yaku_flags: AND #&02: BEQ dsr_no_pin
    LDY #0
.dsr_pin
    LDA yaku_pin_str, Y: BEQ dsr_pin_dn
    JSR oswrch: INY: JMP dsr_pin
.dsr_pin_dn
    JSR osnewl
.dsr_no_pin

    LDA yaku_flags: AND #&80: BEQ dsr_no_toi
    LDY #0
.dsr_toi
    LDA yaku_toi_str, Y: BEQ dsr_toi_dn
    JSR oswrch: INY: JMP dsr_toi
.dsr_toi_dn
    JSR osnewl
.dsr_no_toi

    LDA yaku_flags: AND #&20: BEQ dsr_no_hon
    LDY #0
.dsr_hon
    LDA yaku_hon_str, Y: BEQ dsr_hon_dn
    JSR oswrch: INY: JMP dsr_hon
.dsr_hon_dn
    JSR osnewl
.dsr_no_hon

    LDA yaku_flags: AND #&40: BEQ dsr_no_chi2
    LDY #0
.dsr_chi2
    LDA yaku_chi_str, Y: BEQ dsr_chi2_dn
    JSR oswrch: INY: JMP dsr_chi2
.dsr_chi2_dn
    JSR osnewl
.dsr_no_chi2

    ; --- Display yaku_flags2 yaku ---
    LDA yaku_flags2: AND #&01: BEQ dsr_no_ipp
    LDY #0
.dsr_ipp
    LDA yaku_ipp_str, Y: BEQ dsr_ipp_dn
    JSR oswrch: INY: JMP dsr_ipp
.dsr_ipp_dn
    JSR osnewl
.dsr_no_ipp

    LDA yaku_flags2: AND #&02: BEQ dsr_no_iip
    LDY #0
.dsr_iip
    LDA yaku_iip_str, Y: BEQ dsr_iip_dn
    JSR oswrch: INY: JMP dsr_iip
.dsr_iip_dn
    JSR osnewl
.dsr_no_iip

    LDA yaku_flags2: AND #&04: BEQ dsr_no_sans
    LDY #0
.dsr_sans
    LDA yaku_sans_str, Y: BEQ dsr_sans_dn
    JSR oswrch: INY: JMP dsr_sans
.dsr_sans_dn
    JSR osnewl
.dsr_no_sans

    LDA yaku_flags2: AND #&08: BEQ dsr_no_itt
    LDY #0
.dsr_itt
    LDA yaku_itt_str, Y: BEQ dsr_itt_dn
    JSR oswrch: INY: JMP dsr_itt
.dsr_itt_dn
    JSR osnewl
.dsr_no_itt

    LDA yaku_flags2: AND #&10: BEQ dsr_no_cha
    LDY #0
.dsr_cha
    LDA yaku_cha_str, Y: BEQ dsr_cha_dn
    JSR oswrch: INY: JMP dsr_cha
.dsr_cha_dn
    JSR osnewl
.dsr_no_cha

    LDA yaku_flags2: AND #&20: BEQ dsr_no_ss
    LDY #0
.dsr_ss
    LDA yaku_ss_str, Y: BEQ dsr_ss_dn
    JSR oswrch: INY: JMP dsr_ss
.dsr_ss_dn
    JSR osnewl
.dsr_no_ss

    LDA yaku_flags2: AND #&40: BEQ dsr_no_ct
    LDY #0
.dsr_ct
    LDA yaku_ct_str, Y: BEQ dsr_ct_dn
    JSR oswrch: INY: JMP dsr_ct
.dsr_ct_dn
    JSR osnewl
.dsr_no_ct

    LDA yaku_flags2: AND #&80: BEQ dsr_no_ryp
    LDY #0
.dsr_ryp
    LDA yaku_ryp_str, Y: BEQ dsr_ryp_dn
    JSR oswrch: INY: JMP dsr_ryp
.dsr_ryp_dn
    JSR osnewl
.dsr_no_ryp

    ; --- Display yaku_flags3 yaku ---

    LDA yaku_flags3: AND #&80: BEQ dsr_no_mt
    LDY #0
.dsr_mt
    LDA yaku_mt_str, Y: BEQ dsr_mt_dn
    JSR oswrch: INY: JMP dsr_mt
.dsr_mt_dn
    JSR osnewl
.dsr_no_mt

    LDA yaku_flags3: AND #&01: BEQ dsr_no_sa
    LDY #0
.dsr_sa
    LDA yaku_sa_str, Y: BEQ dsr_sa_dn
    JSR oswrch: INY: JMP dsr_sa
.dsr_sa_dn
    JSR osnewl
.dsr_no_sa

    LDA yaku_flags3: AND #&02: BEQ dsr_no_hr
    LDY #0
.dsr_hr
    LDA yaku_hr_str, Y: BEQ dsr_hr_dn
    JSR oswrch: INY: JMP dsr_hr
.dsr_hr_dn
    JSR osnewl
.dsr_no_hr

    LDA yaku_flags3: AND #&04: BEQ dsr_no_sd
    LDY #0
.dsr_sd
    LDA yaku_sd_str, Y: BEQ dsr_sd_dn
    JSR oswrch: INY: JMP dsr_sd
.dsr_sd_dn
    JSR osnewl
.dsr_no_sd


    JSR osnewl

    ; Check if this is a yakuman hand
    LDA yakuman_flags
    BNE dsr_is_yakuman    ; yakuman hand detected
    LDA yakuman_flags2
    BNE dsr_is_yakuman    ; yakuman hand detected in flags2
    ; Not yakuman - show normal han/fu
    JMP dsr_normal_han
.dsr_is_yakuman

    ; Display yakuman type
    LDA yakuman_flags: AND #&01: BEQ dsr_no_suuk
    LDY #0
.dsr_suuk
    LDA yaku_suuk_str, Y: BEQ dsr_suuk_dn
    JSR oswrch: INY: JMP dsr_suuk
.dsr_suuk_dn
    JSR osnewl
.dsr_no_suuk

    LDA yakuman_flags: AND #&02: BEQ dsr_no_dai
    LDY #0
.dsr_dai
    LDA yaku_dai_str, Y: BEQ dsr_dai_dn
    JSR oswrch: INY: JMP dsr_dai
.dsr_dai_dn
    JSR osnewl
.dsr_no_dai

    LDA yakuman_flags: AND #&04: BEQ dsr_no_cr
    LDY #0
.dsr_cr
    LDA yaku_cr_str, Y: BEQ dsr_cr_dn
    JSR oswrch: INY: JMP dsr_cr
.dsr_cr_dn
    JSR osnewl
.dsr_no_cr

    LDA yakuman_flags: AND #&08: BEQ dsr_no_tsui
    LDY #0
.dsr_tsui
    LDA yaku_tsui_str, Y: BEQ dsr_tsui_dn
    JSR oswrch: INY: JMP dsr_tsui
.dsr_tsui_dn
    JSR osnewl
.dsr_no_tsui

    LDA yakuman_flags: AND #&20: BEQ dsr_no_daiw
    LDY #0
.dsr_daiw
    LDA yaku_daiw_str, Y: BEQ dsr_daiw_dn
    JSR oswrch: INY: JMP dsr_daiw
.dsr_daiw_dn
    JSR osnewl
.dsr_no_daiw

    LDA yakuman_flags: AND #&10: BEQ dsr_no_shouw
    LDY #0
.dsr_shouw
    LDA yaku_shouw_str, Y: BEQ dsr_shouw_dn
    JSR oswrch: INY: JMP dsr_shouw
.dsr_shouw_dn
    JSR osnewl
.dsr_no_shouw

    LDA yakuman_flags: AND #&40: BEQ dsr_no_ten
    LDY #0
.dsr_ten
    LDA yaku_ten_str, Y: BEQ dsr_ten_dn
    JSR oswrch: INY: JMP dsr_ten
.dsr_ten_dn
    JSR osnewl
.dsr_no_ten

    LDA yakuman_flags: AND #&80: BEQ dsr_no_chi_h
    LDY #0
.dsr_chi_h
    LDA yaku_chi_h_str, Y: BEQ dsr_chi_h_dn
    JSR oswrch: INY: JMP dsr_chi_h
.dsr_chi_h_dn
    JSR osnewl
.dsr_no_chi_h

    LDA yakuman_flags2: AND #&01: BEQ dsr_no_suuank
    LDY #0
.dsr_suuank
    LDA yaku_suuank_str, Y: BEQ dsr_suuank_dn
    JSR oswrch: INY: JMP dsr_suuank
.dsr_suuank_dn
    JSR osnewl
.dsr_no_suuank

    LDA yakuman_flags2: AND #&02: BEQ dsr_no_chuuren
    LDY #0
.dsr_chuuren
    LDA yaku_chuuren_str, Y: BEQ dsr_chuuren_dn
    JSR oswrch: INY: JMP dsr_chuuren
.dsr_chuuren_dn
    JSR osnewl
.dsr_no_chuuren


    ; Display YAKUMAN label
    LDY #0
.dsr_yk
    LDA yakuman_str, Y: BEQ dsr_yk_dn
    JSR oswrch: INY: JMP dsr_yk
.dsr_yk_dn
    JSR osnewl: JSR osnewl
    JMP dsr_score

.dsr_normal_han
    LDY #0
.dsr_han
    LDA han_lbl, Y: BEQ dsr_han_dn
    JSR oswrch: INY: JMP dsr_han
.dsr_han_dn
    ; Print han_count as up to 2 digits
    LDA han_count
    LDX #0
.dsr_h10
    CMP #10: BCC dsr_h10dn
    SEC: SBC #10: INX: JMP dsr_h10
.dsr_h10dn
    PHA
    TXA: CLC: ADC #'0': JSR oswrch
    PLA: CLC: ADC #'0': JSR oswrch
    LDA #' ': JSR oswrch

    LDY #0
.dsr_fu
    LDA fu_lbl, Y: BEQ dsr_fu_dn
    JSR oswrch: INY: JMP dsr_fu
.dsr_fu_dn
    LDA fu_count
    LDX #0
.dsr_fu10
    CMP #10: BCC dsr_fu10dn
    SEC: SBC #10: INX: JMP dsr_fu10
.dsr_fu10dn
    PHA
    TXA: CLC: ADC #'0': JSR oswrch
    PLA: CLC: ADC #'0': JSR oswrch
    JSR osnewl: JSR osnewl

.dsr_score

    LDY #0
.dsr_sc
    LDA score_lbl, Y: BEQ dsr_sc_dn
    JSR oswrch: INY: JMP dsr_sc
.dsr_sc_dn
    LDA score_hi: LDX score_lo
    JSR print_num16
    JSR osnewl: JSR osnewl

    LDY #0
.dsr_pk
    LDA press_key_str, Y: BEQ dsr_pk_dn
    JSR oswrch: INY: JMP dsr_pk
.dsr_pk_dn
    JSR osrdch
    RTS

; =============================================
; POINT AWARDING
; =============================================

.award_tsumo
    LDX #0
.at_lp
    STX tmp5                ; save loop counter before possible skip
    CPX current_player: BEQ at_skip
    LDA score_hi: STA tmp2
    LDA score_lo: STA tmp3
    LDA #0
    LDY #16
.at_d3
    ASL tmp3: ROL tmp2: ROL A
    CMP #3: BCC at_d3s
    SBC #3: INC tmp3
.at_d3s
    DEY: BNE at_d3
    CMP #0: BEQ at_nornd
    LDA tmp3: CLC: ADC #100: STA tmp3
    BCC at_nornd    ; no remainder - no rounding needed
    INC tmp2
.at_nornd
    LDA honba: BEQ at_hb_done
    STA tmp4
    LDA #0
.at_hb
    CLC: ADC #100: DEC tmp4: BNE at_hb
    CLC: ADC tmp3: STA tmp3
    BCC at_hb_done    ; honba bonus complete
    INC tmp2
.at_hb_done
    LDX tmp5
    TXA: ASL A: TAX
    LDA player_points, X
    SEC: SBC tmp3: STA player_points, X
    LDA player_points+1, X
    SBC tmp2: STA player_points+1, X
.at_skip
    LDX tmp5: INX
    CPX #NUM_PLAYERS: BNE at_lp

    LDX current_player
    TXA: ASL A: TAX
    LDA player_points, X
    CLC: ADC score_lo: STA player_points, X
    LDA player_points+1, X
    ADC score_hi: STA player_points+1, X

    LDA #0: STA honba
    RTS

.award_ron
    LDA score_lo: ASL A: STA tmp3
    LDA score_hi: ROL A: STA tmp2
    LDA tmp3: ASL A: STA tmp3
    LDA tmp2: ROL A: STA tmp2

    LDA honba: BEQ ar_hb_done
    STA tmp4
    LDA #0
.ar_hb
    CLC: ADC #100: DEC tmp4: BNE ar_hb
    ASL A: ASL A  ; *4 = *300 approx (close enough for now)
    CLC: ADC tmp3: STA tmp3
    BCC ar_hb_done    ; honba bonus complete
    INC tmp2
.ar_hb_done

    LDX disc_tile_player
    TXA: ASL A: TAX
    LDA player_points, X
    SEC: SBC tmp3: STA player_points, X
    LDA player_points+1, X
    SBC tmp2: STA player_points+1, X

    LDX ron_player
    TXA: ASL A: TAX
    LDA player_points, X
    CLC: ADC tmp3: STA player_points, X
    LDA player_points+1, X
    ADC tmp2: STA player_points+1, X

    LDA #0: STA honba
    RTS

; =============================================
; NEW ROUND
; =============================================

.new_round
    ; Advance the round (update dealer, check game end)
    JSR advance_round
    BCS nr_game_over    ; if advance_round returned carry set (error/true)
    ; Clear kan decline flag for new hand
    LDA #0: STA kan_declined
    ; Wait for user to see score, then rebuild wall
    JSR osrdch
    JSR wall_build
    JSR wall_shuffle
    JSR deal_all
    ; Reveal initial dora indicator from dead wall
    LDA wall+DORA_START
    STA dora_indicator
    LDA #0: STA dora_count
    ; Start with the dealer
    LDX dealer: STX current_player
    LDA #0: STA skip_draw
    LDA #0: STA tsumo_flag: STA ron_flag
    LDX #0
.nr_ip
    STA ippatsu_flags, X
    STA furiten_flags, X
    INX: CPX #NUM_PLAYERS: BNE nr_ip
    ; Reset per-player kans count
    LDX #0
.nr_kans
    STA player_kans, X
    INX: CPX #NUM_PLAYERS: BNE nr_kans
    ; Reset total kans counter
    STA four_kans_count
    ; Reset open meld count (clear between rounds)
    LDX #0
.nr_opn
    STA opn_count, X
    INX: CPX #NUM_PLAYERS: BNE nr_opn
    ; Reset yakuman flags
    STA yakuman_flags
    CLC: RTS
.nr_game_over
    SEC: RTS

; =============================================
; OPEN MELDS DISPLAY
; =============================================
; Display open melds for a player compactly.
; X = player number. Prints nothing if no melds.
; Format: " Open:P5m K7s A3p"
; Meld type: P=pon, K=closed kan, A=added kan

.disp_open_melds
    LDA opn_count, X
    BNE dom_has_melds    ; has open melds - display them
    RTS                   ; no open melds - nothing to display
.dom_has_melds

    ; Save player number
    TXA: PHA

    ; Calculate base offset into opn_melds: player * 20
    TXA: ASL A: ASL A          ; * 4
    STA tmp4
    TXA: ASL A: ASL A: ASL A: ASL A ; * 16
    CLC: ADC tmp4              ; = * 20
    STA tmp4                   ; tmp4 = base offset

    ; Print " Open:" label
    LDA #' ': JSR oswrch
    LDA #'O': JSR oswrch
    LDA #'p': JSR oswrch
    LDA #':': JSR oswrch

    ; Get meld count and start loop
    PLA: TAX                   ; restore player number
    LDA opn_count, X
    TAY: DEY                   ; Y = last meld index

.dom_loop
    ; Calculate meld offset: tmp4 + Y * 5
    STY tmp5                   ; save meld index
    LDA tmp5
    ASL A: ASL A               ; * 4
    CLC: ADC tmp5              ; * 5
    CLC: ADC tmp4              ; + base offset
    TAX                        ; X = offset into opn_melds

    ; Print type letter
    LDA opn_melds, X
    CMP #2: BEQ dom_chii     ; type 2 = sequence (chii)
    CMP #3: BEQ dom_kan
    CMP #4: BEQ dom_ak
    LDA #'P': JSR oswrch       ; type 1 = pon
    JMP dom_tiles
.dom_chii
    LDA #'C': JSR oswrch       ; type 2 = sequence (chii)
    JMP dom_tiles
.dom_kan
    LDA #'K': JSR oswrch       ; type 3 = closed kan
    JMP dom_tiles
.dom_ak
    LDA #'A': JSR oswrch       ; type 4 = added kan

.dom_tiles
    ; Print first tile in 2-char format
    INX
    LDA opn_melds, X
    PHA
    JSR tile_num_char: JSR oswrch
    PLA
    JSR tile_suit_char: JSR oswrch

    ; Space between melds
    LDA #' ': JSR oswrch

    ; Next meld - step down to previous index, stop after index 0
    LDY tmp5
    DEY
    BPL dom_loop    ; index still >= 0, more melds to display

.dom_done
    RTS

; =============================================
; ABORTIVE DRAWS
; =============================================
; Check for abortive draw conditions after each discard.
; Returns: C set = abortive draw, C clear = normal play.
; When abortive draw detected, displays message and handles draw resolution.

; Check Four Winds (Suu Fon Round)
; All 4 players discard wind tiles on the first turn (turn 1)
.check_four_winds
    ; Only check after 4 players have each discarded once
    LDA num_discards
    CMP #1    ; check if exactly 1
    BNE cfw_no    ; player not ready - can't be four winds
    LDA num_discards+1
    CMP #1    ; check if exactly 1
    BNE cfw_no    ; player not ready - can't be four winds
    LDA num_discards+2
    CMP #1    ; check if exactly 1
    BNE cfw_no    ; player not ready - can't be four winds
    LDA num_discards+3
    CMP #1    ; check if exactly 1
    BNE cfw_no    ; player not ready - can't be four winds
    ; All players have 1 discard - check if all are winds
    ; Read each player's first discard from their discard pile
    LDX #0
    JSR set_disc_ptr
    LDY #0: LDA (ptr), Y
    CMP #27: BCC cfw_no
    CMP #31: BCS cfw_no
    LDX #1
    JSR set_disc_ptr
    LDY #0: LDA (ptr), Y
    CMP #27: BCC cfw_no
    CMP #31: BCS cfw_no
    LDX #2
    JSR set_disc_ptr
    LDY #0: LDA (ptr), Y
    CMP #27: BCC cfw_no
    CMP #31: BCS cfw_no
    LDX #3
    JSR set_disc_ptr
    LDY #0: LDA (ptr), Y
    CMP #27: BCC cfw_no
    CMP #31: BCS cfw_no
    ; Clear screen and display message
    LDA #12: JSR oswrch    ; clear screen
    JSR game_display
    JSR osnewl              ; newline after game display
    LDY #0
.cfw_msg_lp
    LDA abortive_four_winds_str, Y
    BEQ cfw_msg_dn    ; end of string
    JSR oswrch: INY
    JMP cfw_msg_lp
.cfw_msg_dn
    JSR press_any_key
    SEC
    RTS
.cfw_no
    CLC
    RTS

; Check Four Kans (Suu Kan)
; Scan opn_melds for actual kan melds (types 3 and 4) across all players.
; Avoids relying on four_kans_count which can get corrupted.
; Suu Kan = 4 kans total across multiple players.
; If one player has all 4 kans, that's Suuankou (yakuman), not abortive.
.check_four_kans
    LDX #0
    STX tmp5            ; tmp5 = total kan count
.cfk_player_lp
    STX tmp6            ; tmp6 = current player
    ; Calculate base offset into opn_melds: player * 20
    TXA: ASL A: ASL A
    STA tmp4
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp4
    STA tmp4            ; tmp4 = player * 20
    ; Get meld count for this player
    LDX tmp6
    LDY opn_count, X
    BEQ cfk_next_player ; no melds - skip
    STY tmp7            ; tmp7 = meld count
    ; Scan each meld for kan type (3 or 4)
.cfk_meld_lp
    DEY
    STY tmp8            ; save meld index
    TYA: ASL A: ASL A: CLC: ADC tmp8
    CLC: ADC tmp4: TAX
    LDA opn_melds, X   ; type byte
    CMP #3: BEQ cfk_is_kan
    CMP #4: BEQ cfk_is_kan
    JMP cfk_meld_next
.cfk_is_kan
    INC tmp5            ; total kan count++
    ; Check if this player alone has 4 kans
    LDX tmp6
    LDA player_kans, X
    CMP #4
    BEQ cfk_no          ; Suuankou - not abortive draw
.cfk_meld_next
    LDY tmp8
    CPY #0: BNE cfk_meld_lp
.cfk_next_player
    LDX tmp6
    INX
    CPX #NUM_PLAYERS
    BNE cfk_player_lp
    ; Check total: need 4 kans for Suu Kan
    LDA tmp5
    CMP #4
    BCC cfk_no          ; fewer than 4 kans total
    ; Clear screen, show game state, print message on new line
    LDA #12: JSR oswrch    ; clear screen
    JSR game_display
    JSR osnewl              ; newline after game display
    LDY #0
.cfk_msg_lp
    LDA abortive_four_kans_str, Y
    BEQ cfk_msg_dn    ; end of string
    JSR oswrch: INY
    JMP cfk_msg_lp
.cfk_msg_dn
    JSR press_any_key
    SEC
    RTS
.cfk_no
    CLC
    RTS

; Check Triple Ron (San Kan Ron)
; Two or more players can win on the same discard
; Returns C set if multiple ron claims detected
.check_triple_ron
    LDA ron_flag: PHA
    LDA ron_player: PHA
    ; First, do a normal ron check
    JSR check_ron
    BCC ctr_no_ron    ; if check_ron returned carry clear (OK/false)
    ; One ron found - check for more
    LDA ron_player: STA tmp5
    LDX ron_player: INX
.ctr_loop
    STX tmp6
    CPX disc_tile_player: BEQ ctr_next
    JSR count_tiles_for_player
    LDY disc_tile_val
    LDA tile_counts, Y: CLC: ADC #1: STA tile_counts, Y
    JSR check_win_no_rebuild
    BCS ctr_second_found    ; if check_win_no_rebuild returned carry set (error/true)
    LDY disc_tile_val
    LDA tile_counts, Y: SEC: SBC #1: STA tile_counts, Y
.ctr_next
    LDX tmp6: INX
    CPX #NUM_PLAYERS: BNE ctr_loop
    ; Only one ron found - not triple ron
    PLA: STA ron_player
    PLA: STA ron_flag
    CLC
    RTS
.ctr_second_found
    ; Two rons found = abortive draw
    PLA: STA ron_player
    PLA: STA ron_flag
    LDA #12: JSR oswrch    ; clear screen
    JSR game_display
    JSR osnewl              ; newline after game display
    LDY #0
.ctr_msg_lp
    LDA abortive_triple_ron_str, Y
    BEQ ctr_msg_dn    ; end of string
    JSR oswrch: INY
    JMP ctr_msg_lp
.ctr_msg_dn
    JSR press_any_key
    SEC
    RTS
.ctr_no_ron
    PLA: STA ron_player
    PLA: STA ron_flag
    CLC
    RTS

; Check Nine Gates (Kyuu Shuu Kyuu Hai)
; Pattern: 1-1-1-2-3-4-5-6-7-8-9-9-9 of one suit + 14th tile
; Only for closed hands with 14 tiles
.check_nine_gates
    LDX current_player
    LDA num_tiles, X
    CMP #14    ; check if suit has exactly 14 tiles
    BNE cng_no    ; not zero - condition not met
    ; Check if hand is closed (no open melds)
    LDA opn_count, X
    BNE cng_no    ; not zero - condition not met
    ; Build tile counts
    JSR build_tile_counts
    ; Check each suit: Man(0-8), Pin(9-17), Sou(18-26)
    LDX #0
.cng_suit_lp
    STX tmp5
    JSR cng_check_suit
    BCS cng_found    ; if cng_check_suit returned carry set (error/true)
    LDX tmp5
    INX
    CPX #3    ; check if all 3 suits tested
    BNE cng_suit_lp    ; more suits to test
    CLC
    RTS
.cng_found
    SEC
    RTS
.cng_no
    CLC
    RTS

; Check if a specific suit matches the 9-gate pattern
; X = suit index (0=Man, 1=Pin, 2=Sou)
; Returns C set if pattern matches
.cng_check_suit
    TXA
    ASL A: ASL A: ASL A: ASL A
    TAX
    ; X = base tile value for suit (0, 9, or 18)
    LDY #0
    STY tmp6
    ; Check tile X+0 (1) has at least 3
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cng_no_match    ; not enough copies for nine gates
    CLC: ADC tmp6: STA tmp6
    ; Check tiles X+1 through X+8 have at least 1 each
    INX
.cng_mid_lp
    LDA tile_counts, X
    BEQ cng_no_match    ; pattern doesn't match - not nine gates
    CLC: ADC tmp6: STA tmp6
    INX
    CPX #9    ; check if all middle tiles checked
    BCC cng_mid_lp    ; more middle tiles to check
    ; Now X is at X+9 (the 9 tile)
    LDA tile_counts, X
    CMP #3    ; need 3+ copies for triplet
    BCC cng_no_match    ; not enough copies for nine gates
    CLC: ADC tmp6: STA tmp6
    ; Total should be 14
    LDA tmp6
    CMP #14    ; check if suit has exactly 14 tiles
    BNE cng_no_match    ; not zero - condition not met
    SEC
    RTS
.cng_no_match
    CLC
    RTS

; =============================================
; DISPLAY DELAY
; =============================================
; Wait ~1 second so player can see the game board
; before the tsumo/ron result screen appears.
; Uses the 6522 VIA T1 counter at &FE44/&FE45
; which counts down at 1MHz. The high byte changes
; every ~65ms, so 16 changes ≈ 1 second.
.delay_display
    LDX #16         ; count 16 high-byte changes (~1 second)
.delay_outer
    LDA &FE45       ; read VIA T1 high byte
.delay_hi
    CMP &FE45       ; wait until it changes
    BEQ delay_hi
    DEX
    BNE delay_outer
    RTS

; Clear the prompt line at row 24 and position cursor there.
; Used by kans/riichi prompts so multiple prompts overwrite each other.
; Prints 39 spaces (not 40) to avoid scrolling: 40 chars from col 0
; fills columns 0-39 and the cursor wraps off the end, scrolling the
; screen by one line and pushing the title off the top.
.clear_prompt_line
    PHA
    ; VDU 31,0,24 - position at column 0, row 24
    LDA #31: JSR oswrch
    LDA #0: JSR oswrch
    LDA #24: JSR oswrch
    ; Print 39 spaces to clear the line (column 39 left as-is)
    LDX #39
.cpl_loop
    LDA #' ': JSR oswrch
    DEX: BNE cpl_loop
    ; Reposition at column 0, row 24
    LDA #31: JSR oswrch
    LDA #0: JSR oswrch
    LDA #24: JSR oswrch
    PLA
    RTS

; =============================================
; DISPLAY ROUTINES FOR ABORTIVE DRAWS
; =============================================
; Print "Press any key to continue" prompt
.press_any_key
    JSR osnewl
    LDY #0
.pak_lp
    LDA press_any_key_str, Y
    BEQ pak_dn
    JSR oswrch: INY
    JMP pak_lp
.pak_dn
    JSR osnewl
    JSR osrdch    ; wait for key
    RTS

; Display nine gates win message
.display_nine_gates
    LDY #0
.dng_lp
    LDA abortive_nine_gates_str, Y
    BEQ dng_dn    ; end of string
    JSR oswrch: INY
    JMP dng_lp
.dng_dn
    JSR osnewl
    RTS

; =============================================
; CHOMBO - PENALTY SYSTEM
; =============================================
; Detects illegal plays and applies penalties.
; Violations: illegal riichi, illegal discard, illegal win declaration
; Penalty: 8000 pts (12000 for dealer)

; Apply chombo penalty to a player
; X = player number
; Deducts 8000 pts (dealer pays 12000)
.apply_chombo
    TXA: PHA
    INC chombo_count, X
    ; Calculate penalty: 8000 (non-dealer) or 12000 (dealer)
    CPX dealer: BNE apc_non_dealer
    ; Dealer penalty: 12000 = &2EE0
    TXA: ASL A: TAY
    LDA player_points, Y: SEC: SBC #<12000
    STA player_points, Y
    LDA player_points+1, Y: SBC #>12000
    STA player_points+1, Y
    JMP apc_check_underflow
.apc_non_dealer
    ; Non-dealer penalty: 8000 = &1F40
    TXA: ASL A: TAY
    LDA player_points, Y: SEC: SBC #<8000
    STA player_points, Y
    LDA player_points+1, Y: SBC #>8000
    STA player_points+1, Y
.apc_check_underflow
    ; If points went negative, set to 0
    LDA player_points+1, Y: BPL apc_done
    LDA #0: STA player_points, Y: STA player_points+1, Y
.apc_done
    ; Display chombo message
    JSR game_display
    JSR osnewl
    LDY #0
.apc_msg
    LDA chombo_str, Y: BEQ apc_msg_dn
    JSR oswrch: INY: JMP apc_msg
.apc_msg_dn
    JSR osnewl
    ; Show who pays
    PLA: TAX
    TXA: CLC: ADC #'1'
    JSR oswrch
    LDY #0
.apc_pay
    LDA chombo_pay_str, Y: BEQ apc_pay_dn
    JSR oswrch: INY: JMP apc_pay
.apc_pay_dn
    ; Show penalty amount
    CPX dealer: BNE apc_show_8k
    LDA #'1': JSR oswrch
    LDA #'2': JSR oswrch
    LDA #'0': JSR oswrch
    LDA #'0': JSR oswrch
    LDA #'0': JSR oswrch
    JMP apc_pts_done
.apc_show_8k
    LDA #'8': JSR oswrch
    LDA #'0': JSR oswrch
    LDA #'0': JSR oswrch
    LDA #'0': JSR oswrch
.apc_pts_done
    LDA #' ': JSR oswrch
    LDA #'p': JSR oswrch
    LDA #'t': JSR oswrch
    LDA #'s': JSR oswrch
    JSR osnewl
    ; Show "Press any key to continue"
    LDY #0
.apc_key_msg
    LDA press_any_key_str, Y: BEQ apc_key_msg_dn
    JSR oswrch: INY: JMP apc_key_msg
.apc_key_msg_dn
    ; Wait for keypress
    JSR osrdch
    RTS

; Display chombo counts in scoreboard
.disp_chombo
    LDX #0
.dch_lp
    CPX #NUM_PLAYERS: BCS dch_done
    LDA chombo_count, X: BEQ dch_next
    ; Show "C" marker if player has chombo
    TXA: CLC: ADC #'1'
    JSR oswrch
    LDA #'C': JSR oswrch
    LDA #' ': JSR oswrch
.dch_next
    INX: JMP dch_lp
.dch_done
    RTS

; =============================================
; DATA
; =============================================

.title_str
    EQUS "RIICHI MAHJONG", 0

.hand_hdr_str
    EQUS "Your Hand", 0

.my_disc_str
    EQUS "Your Disc", 0

.inst_str
    EQUS "Z-M,A-J discard   Q:quit", 0

.cpu_move_str
    EQUS "CPU P", 0

.your_move_str
    EQUS "YOUR MOVE", 0

.game_over_str
    EQUS "GAME OVER", 0

.quit_cmd
    EQUS "BASIC", 13

.tsumo_msg
    EQUS "TSUMO!", 0
.ron_msg
    EQUS "RON!", 0
.yaku_tan_str
    EQUS "TANYAO", 0
.yaku_pin_str
    EQUS "PINFU", 0
.yaku_toi_str
    EQUS "TOITOI", 0
.yaku_hon_str
    EQUS "HONITSU", 0
.yaku_chi_str
    EQUS "CHINITSU", 0
.yaku_ipp_str
    EQUS "IPPATSU", 0
.yaku_iip_str
    EQUS "IIPPEIKO", 0
.yaku_sans_str
    EQUS "SANSHOKU", 0
.yaku_itt_str
    EQUS "ITTSU", 0
.yaku_cha_str
    EQUS "CHANTA", 0
.yaku_ss_str
    EQUS "SHOU SANGEN", 0
.yaku_ct_str
    EQUS "CHII TOITSU", 0
.yaku_ryp_str
    EQUS "RYANPEIKOU", 0
.han_lbl
    EQUS "Han: ", 0
.fu_lbl
    EQUS "Fu: ", 0
.score_lbl
    EQUS "Score: ", 0
.riichi_msg
    EQUS "RIICHI!", 0
.riichi_ask
    EQUS "Declare Riichi? (Y/N)", 0
.riichi_no_pts
    EQUS "Need 1000+ pts!", 0
.riichi_no_close
    EQUS "Must be closed!", 0

.closed_kan_ask
    EQUS "Declare Closed Kan? (Y/N)", 0

.added_kan_ask
    EQUS "Declare Added Kan? (Y/N)", 0

.pon_ask_str
    EQUS "Declare Pon? (Y/N)", 0

.chii_ask_str
    EQUS "Declare Chii? (Y/N)", 0

.kan_ask_str
    EQUS "Declare Kan? (Y/N)", 0

.press_key_str
    EQUS "Press any key...", 0
.furiten_msg
    EQUS "FURITEN!", 0

.drawn_str
    EQUS "DRAW - Wall Exhausted", 0

    .diff_title
        EQUS "RIICHI MAHJONG - Select Difficulty", 0
    .diff_novice
        EQUS "1: Novice    - Simple AI, always calls", 0
    .diff_inter
        EQUS "2: Intermediate - Selective AI calls", 0
    .diff_expert
        EQUS "3: Expert - Strategic, defensive AI", 0
    .diff_prompt
        EQUS "Press 1, 2, or 3:", 0
.pract_title
    EQUS "PRACTICE MODE", 0
.pract_off
    EQUS "1: OFF - Play without hints", 0
.pract_on
    EQUS "2: ON  - Show best discard hints", 0
.pract_prompt
    EQUS "Press 1 or 2:", 0
.practice_mode
    EQUB 0
.winner_str
    EQUS "Winner: Player ", 0
.east_str
    EQUS "East", 0
.south_str
    EQUS "South", 0
.seat_wind_chrs
    EQUS "ESWN"

.gd_cpu_str
    EQUS "CPU P", 0

.gd_par_str
    EQUS " (", 0

.gd_par2_str
    EQUS "): ", 0

.gd_dora_str
    EQUS "Dora: ", 0

.gd_wall_str
    EQUS "  Wall: ", 0

.gd_dealer_str
    EQUS "  Dealer: ", 0

.honor_nums
    EQUS "ESWNHTC"

.hand_bases
    EQUW hands + 0 * HAND_SIZE
    EQUW hands + 1 * HAND_SIZE
    EQUW hands + 2 * HAND_SIZE
    EQUW hands + 3 * HAND_SIZE

.disc_bases
    EQUW discards + 0 * MAX_DISC
    EQUW discards + 1 * MAX_DISC
    EQUW discards + 2 * MAX_DISC
    EQUW discards + 3 * MAX_DISC

.wall
    FOR I, 0, TOTAL_TILES-1
    EQUB 0
    NEXT

.hands
    FOR I, 0, (HAND_SIZE * NUM_PLAYERS)-1
    EQUB 0
    NEXT

.num_tiles
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0
    NEXT

.discards
    FOR I, 0, (MAX_DISC * NUM_PLAYERS)-1
    EQUB 0
    NEXT

.num_discards
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0
    NEXT

.wall_pos
    EQUB 0

.current_player
    EQUB 0

.rng_seed
    EQUB &A5

.player_points
    FOR I, 0, (NUM_PLAYERS*2)-1
    EQUB 0
    NEXT

.riichi_sticks
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0
    NEXT

.honba
    EQUB 0

.riichi_on_table
    EQUB 0

; Open melds storage
; 4 players x 4 melds x 5 bytes = 80 bytes
; Each meld: type(1=pon,2=kan), tile1, tile2, tile3, tile4
.opn_melds
    FOR I, 0, (MAX_OPEN_MELDS * MELD_SIZE * NUM_PLAYERS)-1
    EQUB 0
    NEXT

; Number of open melds per player
.opn_count
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0
    NEXT

; Scoring variables
.yaku_flags EQUB 0
.yaku_flags2 EQUB 0
.yaku_flags3 EQUB 0
.yakuman_flags EQUB 0
.yakuman_flags2 EQUB 0
; First turn flag for Tenhou/Chiihou detection
.first_turn
    EQUB 0
.han_count EQUB 0
.fu_count EQUB 0
.hand_closed EQUB 0
.score_lo EQUB 0
.score_hi EQUB 0
.round_wind EQUB 27
.tsumo_flag EQUB 0
.ron_flag EQUB 0
.ron_player EQUB 0

.dora_indicator EQUB 0
.dora_count EQUB 0

; AI difficulty level (0=novice, 1=intermediate, 2=expert)
.ai_difficulty EQUB 0

; Match structure
.dealer EQUB 0          ;\ current dealer player index (0-3)
.hands_played EQUB 0   ;\ total hands played this game
.seat_winds
    FOR I, 0, NUM_PLAYERS-1
    EQUB 27             ;\ seat wind for each player (27=East initially)
    NEXT

; Abortive draw tracking
.first_disc_winds
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0               ;\ first discard is wind for this player?
    NEXT
.four_kans_count EQUB 0  ;\ total kans declared this hand

; Per-player kans count (for Suukantsu detection)
.player_kans
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0
    NEXT

; Flag set when human declines closed kan prompt (cleared on new round)
.kan_declined EQUB 0

; Player who made the last discard (for open call checking)
.disc_tile_player EQUB 0

; Chombo penalty tracking
.chombo_count
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0               ;\ chombo penalties per player
    NEXT

.abortive_four_winds_str
    EQUS "ABORTIVE DRAW - Four Winds!", 0
.abortive_four_kans_str
    EQUS "ABORTIVE DRAW - Four Kans!", 0
.abortive_triple_ron_str
    EQUS "ABORTIVE DRAW - Triple Ron!", 0
.abortive_nine_gates_str
    EQUS "NINE GATES WIN!", 0
.press_any_key_str
    EQUS "Press any key to continue", 0
.chombo_str
    EQUS "CHOMBO - PENALTY!", 0
.chombo_pay_str
    EQUS " pays ", 0
.tenpai_str
    EQUS "TENPAI", 0
.noten_str
    EQUS "NOTEN", 0
.tenpai_pay_str
    EQUS " pays ", 0
.pts_str
    EQUS " pts", 0

; Yaku display strings (new yaku)
.yaku_mt_str
    EQUS "MENZEN TSUMO 1 han", 0
.yaku_sa_str
    EQUS "SANANKOU 2 han", 0
.yaku_hr_str
    EQUS "HONROUTOU 2 han", 0
.yaku_sd_str
    EQUS "SANSHOKU DOUKOU 2 han", 0

; Yakuman display strings
.yaku_suuk_str
    EQUS "SUUKANTSU", 0
.yaku_dai_str
    EQUS "DAISANGEN", 0
.yaku_cr_str
    EQUS "CHINROUTOU", 0
.yaku_tsui_str
    EQUS "TSUUISOU", 0
.yaku_daiw_str
    EQUS "DAISUUSHII", 0
.yaku_shouw_str
    EQUS "SHOUSUUSHII", 0
.yakuman_str
    EQUS "YAKUMAN", 0
; Tenhou/Chiihou display strings
.yaku_ten_str
    EQUS "TENHOU", 0
.yaku_chi_h_str
    EQUS "CHIIHOU", 0
.yaku_suuank_str
    EQUS "SUUANKOU", 0
.yaku_chuuren_str
    EQUS "CHUUREN POUTOU", 0

.tile_counts
    FOR I, 0, 33
    EQUB 0
    NEXT

; Debug counters (for diagnosing win detection)
.dbg_tsumo_calls
    EQUB 0
.dbg_tsumo_wins
    EQUB 0
.dbg_ron_calls
    EQUB 0
.dbg_ron_wins
    EQUB 0


; ============================================================
; Splash screen and instructions
; ============================================================

.show_splash
    ; Clear screen
    LDA #12: JSR oswrch
    ; Draw mahjong tile at top of screen (rows 2-9, centred)
    JSR draw_tile_image
    ; Position cursor for splash text (row 12)
    LDA #31: JSR oswrch
    LDA #0: JSR oswrch
    LDA #12: JSR oswrch
    ; Print splash text
    LDA #<splash_text: STA ptr
    LDA #>splash_text: STA ptr+1
    JSR print_page
    ; Wait for I or P
.ss_wait
    JSR osrdch
    CMP #'I': BEQ show_instructions
    CMP #'i': BEQ show_instructions
    CMP #'P': BEQ ss_play
    CMP #'p': BEQ ss_play
    CMP #27: BEQ ss_play
    JMP ss_wait
.ss_play
    RTS

; ============================================================
; Instructions - 5 paginated pages
; ============================================================

.show_instructions
    LDX #0
.si_loop
    STX tmp4
    ; Clear screen
    LDA #12: JSR oswrch
    ; Get page address
    LDX tmp4
    LDA page_table_lo, X: STA ptr
    LDA page_table_hi, X: STA ptr+1
    JSR print_page
    ; Wait for key
    JSR osrdch
    CMP #27: BEQ si_exit
    LDX tmp4
    INX
    CPX #5
    BNE si_loop
.si_exit
    JMP show_splash

; ============================================================
; Print null-terminated text from (ptr)
; Handles strings longer than 255 bytes
; ============================================================

.print_page
    LDY #0
.pp_loop
    LDA (ptr), Y
    BEQ pp_done
    CMP #10          ; LF = line feed
    BEQ pp_newline
    JSR oswrch
    JMP pp_next
.pp_newline
    JSR osnewl
.pp_next
    INY
    BNE pp_loop
    INC ptr+1
    JMP pp_loop
.pp_done
    RTS

; ============================================================
; Page address tables
; ============================================================

.page_table_lo
    EQUB <page1_text, <page2_text, <page3_text, <page4_text, <page5_text
.page_table_hi
    EQUB >page1_text, >page2_text, >page3_text, >page4_text, >page5_text

; ============================================================
; Splash screen text (null terminated)
; ============================================================

.splash_text
    EQUS "            RIICHI MAHJONG"
    EQUB 10
    EQUS "           BBC Micro Edition"
    EQUB 10, 10
    EQUS "       Press I for Instructions"
    EQUB 10
    EQUS "            Press P to Play"
    EQUB 10, 10, 0

; ============================================================
; Page 1: Game Overview
; ============================================================

.page1_text
    EQUS "  RIICHI MAHJONG - Page 1/5"
    EQUB 10, 10
    EQUS "  Riichi Mahjong is a"
    EQUB 10
    EQUS "  four-player tile game"
    EQUB 10
    EQUS "  from Japan. Each player"
    EQUB 10
    EQUS "  builds a hand of 13"
    EQUB 10
    EQUS "  tiles, aiming to form"
    EQUB 10
    EQUS "  4 melds and 1 pair."
    EQUB 10, 10
    EQUS "  The game uses 136"
    EQUB 10
    EQUS "  tiles: 4 copies each"
    EQUB 10
    EQUS "  of 34 distinct tiles."
    EQUB 10
    EQUS "  These are 9 Man, 9"
    EQUB 10
    EQUS "  Pin, 9 Sou, and 7"
    EQUB 10
    EQUS "  honor tiles."
    EQUB 10, 10
    EQUS "  Press any key to continue"
    EQUB 10, 0

; ============================================================
; Page 2: Tiles and Melds
; ============================================================

.page2_text
    EQUS "  RIICHI MAHJONG - Page 2/5"
    EQUB 10, 10
    EQUS "  Tile Types:"
    EQUB 10, 10
    EQUS "  Man (Characters): 1-9m"
    EQUB 10
    EQUS "  Pin (Circles):    1-9p"
    EQUB 10
    EQUS "  Sou (Bamboo):     1-9s"
    EQUB 10, 10
    EQUS "  Winds: East South"
    EQUB 10
    EQUS "         West North"
    EQUB 10
    EQUS "  Dragons: Red Green"
    EQUB 10
    EQUS "           White"
    EQUB 10, 10
    EQUS "  Melds (groups of 3):"
    EQUB 10
    EQUS "  Pon: 3 matching tiles"
    EQUB 10
    EQUS "  Chii: 3 same-suit"
    EQUB 10
    EQUS "       sequential tiles"
    EQUB 10
    EQUS "  Kan: 4 matching tiles"
    EQUB 10, 10
    EQUS "  Press any key to continue"
    EQUB 10, 0

; ============================================================
; Page 3: Winning
; ============================================================

.page3_text
    EQUS "  RIICHI MAHJONG - Page 3/5"
    EQUB 10, 10
    EQUS "  Winning a Hand:"
    EQUB 10, 10
    EQUS "  You win when your hand"
    EQUB 10
    EQUS "  has 4 melds and 1 pair"
    EQUB 10
    EQUS "  (14 tiles total)."
    EQUB 10, 10
    EQUS "  Tsumo: Draw the final"
    EQUB 10
    EQUS "  tile yourself."
    EQUB 10
    EQUS "  Ron: Claim a discard"
    EQUB 10
    EQUS "  from any opponent."
    EQUB 10, 10
    EQUS "  After a win, count"
    EQUB 10
    EQUS "  han (bonus points)"
    EQUB 10
    EQUS "  and fu (base points)."
    EQUB 10
    EQUS "  More han = bigger"
    EQUB 10
    EQUS "  score!"
    EQUB 10, 10
    EQUS "  Press any key to continue"
    EQUB 10, 0

; ============================================================
; Page 4: Riichi and Scoring
; ============================================================

.page4_text
    EQUS "  RIICHI MAHJONG - Page 4/5"
    EQUB 10, 10
    EQUS "  Riichi:"
    EQUB 10, 10
    EQUS "  When 1 tile from win,"
    EQUB 10
    EQUS "  declare riichi for a"
    EQUB 10
    EQUS "  1000 point bet. You"
    EQUB 10
    EQUS "  must then discard"
    EQUB 10
    EQUS "  randomly each turn."
    EQUB 10, 10
    EQUS "  Ippatsu: Win within 1"
    EQUB 10
    EQUS "  turn for bonus han."
    EQUB 10, 10
    EQUS "  Scoring:"
    EQUB 10
    EQUS "  Score = han x fu."
    EQUB 10
    EQUS "  You need at least"
    EQUB 10
    EQUS "  1 han to win."
    EQUB 10, 10
    EQUS "  Press any key to continue"
    EQUB 10, 0

; ============================================================
; Page 5: Special Rules
; ============================================================

.page5_text
    EQUS "  RIICHI MAHJONG - Page 5/5"
    EQUB 10, 10
    EQUS "  Special Rules:"
    EQUB 10, 10
    EQUS "  Yakuman hands score"
    EQUB 10
    EQUS "  maximum points! There"
    EQUB 10
    EQUS "  are 12 types including"
    EQUB 10
    EQUS "  Thirteen Orphans and"
    EQUB 10
    EQUS "  All Green."
    EQUB 10, 10
    EQUS "  Abortive Draws:"
    EQUB 10, 10
    EQUS "  If 4 kans are declared"
    EQUB 10
    EQUS "  or 4 winds appear as"
    EQUB 10
    EQUS "  first discards, the"
    EQUB 10
    EQUS "  round is void."
    EQUB 10, 10
    EQUS "  Good luck and have fun!"
    EQUB 10, 10
    EQUS "  Press any key to exit"
    EQUB 10, 0


.draw_tile_image
    ; Draw Red Dragon tile centred at top of screen
    ; Y = screen row (starts at 2), tmp3 = data offset
    LDY #2
    LDX #0
    STX tmp3
.dt_row
    LDA #31: JSR oswrch  ; VDU 31,x,y
    LDA #15: JSR oswrch  ; column 15 (centred for 9-col tile)
    TYA: JSR oswrch      ; row
    LDX tmp3
    LDA tile_data, X     ; row byte count
    STA tmp2
.dt_loop
    INX
    LDA tile_data, X
    JSR oswrch
    DEC tmp2
    BNE dt_loop
    INX                  ; skip end marker (&9C)
    STX tmp3
    INY                  ; next row
    CPY #10              ; 8 rows: 2-9
    BNE dt_row
    RTS

.tile_data
    ; Red Dragon mahjong tile (8 rows, 9 bytes each)
    ; Row format: length, &9D, &91, graphics..., &9C
    EQUB 9, &9D, &91, &20, &20, &20, &20, &20, &20, &9C
    EQUB 9, &9D, &91, &20, &6A, &34, &70, &20, &20, &9C
    EQUB 9, &9D, &91, &7C, &6F, &3F, &6B, &20, &20, &9C
    EQUB 9, &9D, &91, &35, &7A, &7D, &2F, &20, &20, &9C
    EQUB 9, &9D, &91, &2F, &6B, &35, &20, &20, &20, &9C
    EQUB 9, &9D, &91, &20, &6A, &35, &20, &20, &20, &9C
    EQUB 9, &9D, &91, &20, &6A, &25, &20, &20, &20, &9C
    EQUB 9, &9D, &91, &20, &20, &20, &20, &20, &20, &9C

    ; 34-byte buffer for wall integrity check (zeroed on each check)
.wall_check_counts
    EQUB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

.end
SAVE "MAHJONG", start, end, start