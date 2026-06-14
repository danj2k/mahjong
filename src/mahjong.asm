\ mahjong.asm - BBC Micro Riichi Mahjong v2
\ Multi-player: 1 Human (Player 0) + 3 AI opponents
\
\ Tile encoding:
\   0-8   = Man (Manzu) 1-9
\   9-17  = Pin (Pinzu) 1-9
\   18-26 = Sou (Souzu) 1-9
\   27-30 = Winds: East, South, West, North
\   31-33 = Dragons: Hatsu(Green), Haku(White), Chun(Red)
\
\ Display format (two-character stacked):
\   Top row:    1 2 3 4 5 6 7 8 9  (numbers for suited tiles)
\               E S W N T H C      (letters for honor tiles)
\   Bottom row: m m m p p p s s s  (suit letter for suited)
\               w w w w g b r      (w for winds, unique for dragons)
\               g=Hatsu(green) b=Haku(white) r=Chun(red)

oswrch = &FFEE
osnewl = &FFE7
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

\ Zero page
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

\ Open call flag - skip draw on next turn
.skip_draw EQUB 0

\ Last discarded tile info
.disc_tile_val EQUB 0
.disc_tile_player EQUB 0


\ Tile count array for meld decomposition (34 bytes)
\ &7C-&9D: count of each tile type (0-33) in the hand being analyzed
tile_counts = &7C

\ Meld decomposition result storage
\\ Temp variable for open call routines
tmp9 = &9E
no_seq_flag = &9F

riichi_declared = &A0       \ per-player riichi flag (4 bytes)
ippatsu_flags = &A4        \ per-player ippatsu flag (4 bytes)
furiten_flags = &A8        \ per-player furiten flags (4 bytes)
\ Bit 0: temporary furiten (cleared on draw)
\ Bit 1: permanent furiten (set when riichi + discard is winning tile)

\ =============================================
ORG &3000
\ =============================================

.start
    LDA #22: JSR oswrch
    LDA #7: JSR oswrch
    JSR game_init
    JSR game_display

\ --- Main loop ---
.mainloop
    LDA #0: STA tsumo_flag: STA ron_flag
    LDA skip_draw
    JMP ml_skip_draw

    JSR player_draw
    BCC ml_draw_ok
    \ Wall exhausted - drawn game
    JSR game_display
    LDY #0
.draw_msg
    LDA drawn_str, Y
    BEQ draw_msg_dn
    JSR oswrch: INY
    JMP draw_msg
.draw_msg_dn
    JSR osnewl
    \ Drawn game: dealer stays, honba++, hands_played++
    INC honba: INC hands_played
    \ Check game end
    LDA hands_played
    CMP #8
    BCC draw_new
    SEC: JMP game_over
.draw_new
    JSR new_round
    BCC draw_ok
    JMP game_over
.draw_ok

.ml_draw_ok
    JSR check_tsumo
    BCC ml_not_tsumo
    \\ Check for illegal tsumo (chombo)
    JSR check_chombo_win
    BCC ml_tsumo_valid
    \\ Invalid tsumo - apply chombo
    LDX current_player: JSR apply_chombo
    JSR advance_player
    JMP mainloop
.ml_tsumo_valid
    JSR sort_hand
    JSR game_display
    JSR calculate_score
    JSR display_score_result
    JSR award_tsumo
    JSR new_round
    BCC tsumo_ok
    JMP game_over
.tsumo_ok

.ml_not_tsumo
    JSR check_closed_kan
    JMP ml_kan_declared
    JSR check_added_kan
    JMP ml_kan_declared
    JMP ml_no_kan
.ml_kan_declared
    \\ Check for four kans abortive draw
    JSR check_four_kans
    JMP ml_abortive
    JMP ml_got_tile
.ml_no_kan
    \\ Check riichi for human player
    LDX current_player
    CPX #0
    BNE ml_got_tile
    JSR check_riichi_human
    BCC ml_got_tile
    \\ Riichi declared - check for illegal riichi (chombo)
    JSR check_chombo_riichi
    BCC ml_riichi_ok
    \\ Illegal riichi - apply chombo penalty
    LDX current_player: JSR apply_chombo
    JSR advance_player
    JMP mainloop
.ml_riichi_ok
    \\ Riichi declared - auto-discard drawn tile (last in hand)
    LDX num_tiles
    DEX
    JSR player_discard
    JSR check_furiten_after_discard
    JSR check_ron
    BCC ml_no_ron_riichi
    JMP ml_ron
.ml_no_ron_riichi
    JSR advance_player
    JMP mainloop

.ml_skip_draw
    LDA #0: STA skip_draw

.ml_got_tile
    LDX current_player
    CPX #0
    BEQ ml_human

    \ AI turn
    JSR sort_hand
    JSR check_riichi_ai
    LDX current_player
    JSR ai_choose_discard
    JSR player_discard
    JSR check_furiten_after_discard
    \\ Check for abortive draws after discard
    JSR check_four_winds
    JMP ml_abortive
    JSR check_ron
    JMP ml_not_ron
    JMP ml_ron
.ml_not_ron
    JSR check_open_calls
    BCS ml_call_made
    JSR ai_delay
    JSR game_display
    JSR advance_player
    JMP mainloop

.ml_call_made
    JSR ai_delay
    JSR game_display
    JMP mainloop

.ml_human
    JSR sort_hand
    JSR game_display
    JSR human_input
    JSR player_discard
    JSR check_furiten_after_discard
    \\ Check for abortive draws after discard
    JSR check_four_winds
    JMP ml_abortive
    JSR check_ron
    JMP ml_not_ron_h
    JMP ml_ron
.ml_not_ron_h
    JSR check_open_calls
    BCS ml_call_made_h
    JSR advance_player
    JMP mainloop

.ml_call_made_h
    JSR game_display
    JMP mainloop

\\ Abortive draw handler
.ml_abortive
    JSR display_abortive_draw
    JSR new_round
    BCC abortive_ok
    JMP game_over
.abortive_ok
    JMP mainloop

.ml_tsumo
    \\ Check for nine gates before handling win
    JSR check_nine_gates
    BCC ml_not_nine_gates
    \\ Nine gates win - display special message
    JSR display_nine_gates
    JSR calculate_score
    JSR display_score_result
    JSR award_tsumo
    JSR new_round
    BCC nine_gates_ok
    JMP game_over
.nine_gates_ok
    JMP mainloop
.ml_not_nine_gates
    JSR sort_hand
    JSR game_display
    JSR calculate_score
    JSR display_score_result
    JSR award_ron
    JSR new_round
    BCC ron_ok
    JMP game_over
.ron_ok

.ml_ron
    \\ Check for triple ron before handling
    JSR check_triple_ron
    BCC ml_not_triple_ron
    \\ Triple ron - abortive draw
    JSR display_abortive_draw
    JSR new_round
    BCC triple_ron_ok
    JMP game_over
.triple_ron_ok
    JMP mainloop
.ml_not_triple_ron
    LDX ron_player: STX current_player
    \\ Check for illegal ron (chombo)
    JSR check_chombo_win
    BCC ml_ron_valid
    \\ Invalid ron - apply chombo
    LDX current_player: JSR apply_chombo
    JSR advance_player
    JMP mainloop
.ml_ron_valid
    JSR sort_hand
    JSR game_display
    JSR calculate_score
    JSR display_score_result
    JSR award_ron
    JSR new_round
    BCC ron_continue
    JMP game_over
.ron_continue
    JMP mainloop

.game_over
    LDA #12: JSR oswrch
    LDY #0
.go_lp
    LDA game_over_str, Y
    BEQ go_dn
    JSR oswrch: INY
    JMP go_lp
.go_dn
    JSR osnewl
    \ Show final scores
    JSR disp_points_line
    JSR osnewl
    \ Find and display the winner (highest points)
    LDX #0: STX tmp5          \ tmp5 = highest index
    LDX #1
.go_find_lp
    CPX #NUM_PLAYERS
    BCS go_show_winner
    STX tmp6
    TXA: ASL A: TAX
    LDA player_points+1, X
    LDY tmp5: TYA: ASL A: TAY
    CMP player_points+1, Y
    BCC go_find_next
    BNE go_new_high
    LDA player_points, X
    CMP player_points, Y
    BCC go_find_next
.go_new_high
    LDX tmp6: STX tmp5
.go_find_next
    LDX tmp6: INX
    JMP go_find_lp
.go_show_winner
    LDY #0
.go_w_lp
    LDA winner_str, Y
    BEQ go_w_dn
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
    BEQ go_pk_dn
    JSR oswrch: INY
    JMP go_pk
.go_pk_dn
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    \ Reset game and restart
    JSR game_init
    JSR game_display
    JMP mainloop
.quit
    LDA #12: JSR oswrch
    RTS

\ =============================================
\ HUMAN INPUT
\ Wait for a valid discard key or Q to quit
\ Returns position (0-based) in X
\ =============================================
.human_input
    \ Clear entire keyboard buffer before reading
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    \ Now wait for a new keypress
    JSR osrdch
    CMP #'Q': BEQ quit
    CMP #'q': BEQ quit
    JSR parse_disc_key
    BCC human_input
    RTS

\ Parse discard key. Returns C set + position in X, or C clear.
.parse_disc_key
    CMP #'1': BCC pdck_bad
    CMP #':': BCS pdck_0
    SEC: SBC #'1'
    TAX: SEC: RTS
.pdck_0
    CMP #'0': BNE pdck_abc
    LDX #9: SEC: RTS
.pdck_abc
    CMP #'A': BCC pdck_bad
    CMP #'E': BCS pdck_bad
    SEC: SBC #'A'
    CLC: ADC #10
    TAX: SEC: RTS
.pdck_bad
    CLC: RTS

\ =============================================
\ TURN MANAGEMENT
\ =============================================

.advance_player
    INC current_player
    LDA current_player
    CMP #NUM_PLAYERS
    BNE ap_dn
    LDA #0: STA current_player
.ap_dn
    RTS

\ AI delay - ~2.3M cycles per call
\ Triple-nested: 7 x 256 x 256 x 5 ~ 2.3M cycles
\ Three AI turns x 2.3M ~ 6.9M total > 5M type_input hold
.ai_delay
    LDA #7
    STA tmp7
.adl1
    LDX #0
.adl2
    LDY #0
.adl3
    DEY
    BNE adl3
    DEX
    BNE adl2
    DEC tmp7
    BNE adl1
    RTS

\\ =============================================
\\ DIFFICULTY SELECTION
\\ =============================================
\\ Display difficulty menu and read player choice.
\\ Stores result in ai_difficulty (0=novice, 1=intermediate, 2=expert).

.difficulty_select
    \ Clear screen
    LDA #12: JSR oswrch
    \ Display menu title
    LDY #0
.ds_title_lp
    LDA diff_title, Y
    BEQ ds_title_dn
    JSR oswrch: INY
    JMP ds_title_lp
.ds_title_dn
    JSR osnewl: JSR osnewl
    \ Display option 1: Novice
    LDY #0
.ds_opt1_lp
    LDA diff_novice, Y
    BEQ ds_opt1_dn
    JSR oswrch: INY
    JMP ds_opt1_lp
.ds_opt1_dn
    JSR osnewl
    \ Display option 2: Intermediate
    LDY #0
.ds_opt2_lp
    LDA diff_inter, Y
    BEQ ds_opt2_dn
    JSR oswrch: INY
    JMP ds_opt2_lp
.ds_opt2_dn
    JSR osnewl
    \ Display option 3: Expert
    LDY #0
.ds_opt3_lp
    LDA diff_expert, Y
    BEQ ds_opt3_dn
    JSR oswrch: INY
    JMP ds_opt3_lp
.ds_opt3_dn
    JSR osnewl: JSR osnewl
    \ Display prompt
    LDY #0
.ds_prompt_lp
    LDA diff_prompt, Y
    BEQ ds_prompt_dn
    JSR oswrch: INY
    JMP ds_prompt_lp
.ds_prompt_dn
    \ Wait for keypress
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    \ Check 1, 2, 3
    CMP #'1': BEQ ds_novice
    CMP #'2': BEQ ds_intermediate
    CMP #'3': BEQ ds_expert
    \ Invalid - try again
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

\\ =============================================
\\ ADVANCE ROUND
\ =============================================
\ Called after each hand ends (tsumo/ron).
\ Updates dealer, seat winds, hands_played.
\ Returns: C set = game over, C clear = continue.
\
\ Rules:
\ - Dealer won: dealer stays, hands_played++
\ - Non-dealer won: dealer advances, hands_played++
\ - Draw: dealer stays, hands_played++, honba++
\ - Game ends after 8 hands (South 4) unless dealer won
\   (dealer repeat extends the game)

.advance_round
    \ Increment hands_played
    INC hands_played

    \ Determine if it was a draw (wall exhausted)
    LDA tsumo_flag
    ORA ron_flag
    BEQ ar_draw

    \ Was a win - check if dealer won
    LDA tsumo_flag
    BNE ar_tsumo
    \ Ron: winner = ron_player
    LDX ron_player
    JMP ar_got_winner
.ar_tsumo
    \ Tsumo: winner = current_player
    LDX current_player
.ar_got_winner
    \ Check if winner is dealer
    CPX dealer
    BEQ ar_dealer_won

    \ Non-dealer won: advance dealer, reset honba
    LDA #0: STA honba
    LDX dealer
    INX
    CPX #NUM_PLAYERS
    BNE ar_no_wrap
    LDX #0
.ar_no_wrap
    STX dealer
    JMP ar_update_seats

.ar_dealer_won
    \ Dealer won: stay as dealer, increment honba
    INC honba
    JMP ar_update_seats

.ar_draw
    \ Draw: dealer stays, honba++
    INC honba

.ar_update_seats
    \ Calculate seat winds: dealer=East, then clockwise
    LDX #0
.ar_seat_lp
    TXA: CLC: ADC dealer
    CMP #NUM_PLAYERS
    BCC ar_no_wrap2
    SEC: SBC #NUM_PLAYERS
.ar_no_wrap2
    TAY                         \ Y = position relative to dealer
    TXA: CLC: ADC #27          \ East + offset
    STA seat_winds, Y
    INX
    CPX #NUM_PLAYERS
    BNE ar_seat_lp

    \ Check for game end
    \ Game ends when hands_played >= 8 (completed South 4)
    \ unless the dealer just won (extends by one more hand)
    LDA hands_played
    CMP #8
    BCC ar_not_over            \ less than 8 hands: continue

    \ 8+ hands played - check if dealer won (extends game)
    LDA tsumo_flag
    ORA ron_flag
    BEQ ar_not_over           \ draw doesn't extend
    LDX #0
    LDA tsumo_flag
    BNE ar_chk_winner
    LDX ron_player
    JMP ar_chk_dealer
.ar_chk_winner
    LDX current_player
.ar_chk_dealer
    CPX dealer
    BEQ ar_not_over           \ dealer won: extend game

    \ Non-dealer won at 8+ hands: game over
    SEC
    RTS

.ar_not_over
    \ Safety: end game at 12 hands maximum (South All-Stars limit)
    LDA hands_played
    CMP #12
    BCC ar_continue
    SEC
    RTS

.ar_continue
    CLC
    RTS

\ =============================================
\ GAME INITIALIZATION
\ =============================================


\ =============================================
\ RIICHI DECLARATION
\ =============================================
\ Check if human player can declare riichi.
\\ Conditions: closed hand (no open melds), 1000+ points, not already declared.
\\ If eligible, prompts Y/N and deducts 1000 points + places riichi stick.
\\ Returns: C set = riichi declared, C clear = no riichi.

\\ =============================================
\\ CHOMBO CHECK ROUTINES
\\ =============================================
\\ Quick checks for illegal plays.
\\ Returns C set if chombo detected.

\\ Check for illegal riichi
\\ Returns C set if riichi declared with open hand
.check_chombo_riichi
    LDX current_player
    LDA riichi_declared, X
    BEQ ccri_not_riichi
    LDA opn_count, X
    BEQ ccri_valid
    \\ Riichi with open hand = chombo
    SEC: RTS
.ccri_not_riichi
    CLC: RTS
.ccri_valid
    CLC: RTS

\\ Check for illegal win (tsumo or ron)
\\ Returns C set if win declared on invalid hand
.check_chombo_win
    JSR check_win
    BCS ccmw_valid
    \\ Invalid win = chombo
    SEC: RTS
.ccmw_valid
    CLC: RTS

.check_riichi_human
    \ Already declared?
    LDX current_player
    LDA riichi_declared, X
    BNE crh_no

    \ Must have closed hand (no open melds)
    LDA opn_count, X
    BNE crh_open

    \ Must have 1000+ points
    TXA: ASL A: TAX
    LDA player_points+1, X
    CMP #>1000
    BCC crh_nopoints
    BNE crh_enough
    LDA player_points, X
    CMP #<1000
    BCC crh_nopoints
.crh_enough

    \ Display riichi prompt
    JSR riichi_display_prompt

    \ Read Y/N key
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    CMP #'Y': BEQ crh_declare
    CMP #'y': BEQ crh_declare

.crh_no
    CLC: RTS

.crh_open
    \ Could display "Must be closed!" but skip for now
    JMP crh_no

.crh_nopoints
    \ Could display "Need 1000+ pts!" but skip for now
    JMP crh_no

.crh_declare
    \ Deduct 1000 points from player
    LDX current_player
    TXA: ASL A: TAX
    LDA player_points, X
    SEC: SBC #<1000
    STA player_points, X
    LDA player_points+1, X
    SBC #>1000
    STA player_points+1, X

    \ Place riichi stick on table
    LDX current_player
    LDA #1
    STA riichi_declared, X
    LDA riichi_on_table
    CLC: ADC #1
    STA riichi_on_table

    \ Set ippatsu flag (bonus if win within one full rotation)
    LDX current_player
    LDA #1
    STA ippatsu_flags, X

    \ Check permanent furiten for riichi
    JSR check_furiten_for_player

    \ Display RIICHI message
    LDA #12: JSR oswrch
    LDY #0
.crh_msg
    LDA riichi_msg, Y
    BEQ crh_msg_dn
    JSR oswrch: INY
    JMP crh_msg
.crh_msg_dn
    JSR osnewl
    \ Brief pause
    LDX #0: LDY #0
.crh_pause
    DEY: BNE crh_pause
    DEX: BNE crh_pause

    SEC: RTS

\ Check if AI player can declare riichi.
\ AI always declares if eligible (closed hand + 1000+ pts).
.check_riichi_ai
    LDX current_player
    \ Already declared?
    LDA riichi_declared, X
    BNE cra_no
    \ Must have closed hand
    LDA opn_count, X
    BNE cra_no
    \ Novice AI: always declares riichi if eligible
    LDA ai_difficulty
    BEQ cra_enough      \ 0 = novice, always riichi
    \ Intermediate: only riichi if hand has good tiles (>= 4 pairs or 3+ sequences)
    \ For now, intermediate and expert both skip riichi AI (conservative)
    CMP #1
    BEQ cra_intermediate
    \ Expert: only riichi when hand is very strong (1000+ pts AND more than 2 open melds would be bad)
    \ Conservative: skip riichi for expert too - too complex to evaluate hand quality here
    JMP cra_no
.cra_intermediate
    \ Intermediate: check if player has enough pairs (at least 3) - basic hand quality check
    STX tmp5
    JSR build_tile_counts
    LDY #0: STY tmp6    \ tmp6 = pair count
.cra_pair_lp
    CPY #34: BCS cra_inter_done
    LDA tile_counts, Y
    CMP #2
    BCC cra_pair_next
    INC tmp6
.cra_pair_next
    INY
    JMP cra_pair_lp
.cra_inter_done
    \ Need at least 3 pairs to consider riichi
    LDX tmp5
    LDA tmp6
    CMP #3
    BCC cra_no          \ fewer than 3 pairs: don't riichi
    \ Must have 1000+ points
    TXA: ASL A: TAX
    LDA player_points+1, X
    CMP #>1000
    BCC cra_no
    BNE cra_enough
    LDA player_points, X
    CMP #<1000
    BCC cra_no
.cra_enough

    \ Deduct 1000 points
    LDX current_player
    TXA: ASL A: TAX
    LDA player_points, X
    SEC: SBC #<1000
    STA player_points, X
    LDA player_points+1, X
    SBC #>1000
    STA player_points+1, X

    \ Set riichi flags
    LDX current_player
    LDA #1
    STA riichi_declared, X
    STA ippatsu_flags, X
    LDA riichi_on_table
    CLC: ADC #1
    STA riichi_on_table

    \ Check permanent furiten for riichi
    JSR check_furiten_for_player

.cra_no
    RTS

\ Display riichi prompt for human player
.riichi_display_prompt
    LDY #0
.rdp_lp
    LDA riichi_ask, Y
    BEQ rdp_dn
    JSR oswrch: INY
    JMP rdp_lp
.rdp_dn
    RTS

\\ =============================================
\\ CLOSED KAN AND ADDED KAN
\\ =============================================
\\ Per Turn Sequence: CHECK CLOSED KAN, CHECK ADDED KAN
\\ Called after tsumo check, before riichi declaration.
\\ Returns: C set = kan declared (player needs to discard), C clear = no kan.

\\ Check if current player can declare a closed kan (4 of same tile in hand).
\\ For AI: always declares. For human: prompts Y/N.
\\ Returns C set if kan declared.
.check_closed_kan
    LDX current_player
    JSR build_tile_counts
    LDY #0             \\ Y = tile index to scan

.cck_scan
    CPY #34: BCS cck_no
    LDA tile_counts, Y
    CMP #4
    BCC cck_next

    \\ Found 4 of tile Y! Check if this is a valid closed kan
    \\ (tile must be in hand, not already part of open meld)
    \\ Since we built tile_counts from the hand, all 4 are in hand

    \\ For AI player: auto-declare
    LDX current_player
    CPX #0
    BEQ cck_human_ask
    JSR execute_closed_kan
    SEC: RTS

.cck_human_ask
    \ Y = tile index from scan loop. Save it first.
    STY tmp9
    \ Display "Declare Closed Kan" prompt
    LDY #0
.cck_prompt_lp
    LDA closed_kan_ask, Y
    BEQ cck_prompt_dn
    JSR osnewl: JSR oswrch: INY
    JMP cck_prompt_lp
.cck_prompt_dn
    \ Show which tile: " tile "
    LDA #' ': JSR oswrch
    LDA tmp9: JSR tile_num_char: JSR oswrch
    LDA tmp9: JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    \ Wait for key
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    CMP #'Y': BEQ cck_do_it
    CMP #'y': BEQ cck_do_it
    \ User said no - continue scanning for other kans
    LDY tmp9
    JMP cck_scan

.cck_do_it
    JSR execute_closed_kan
    SEC: RTS

.cck_next
    INY
    JMP cck_scan

.cck_no
    CLC: RTS

\\ Execute closed kan: remove 4 tiles from hand, create meld, draw replacement.
\\ Y = tile index (0-33) of the 4-of-a-kind.
.execute_closed_kan
    STY tmp5             \\ save tile index
    \\ Create open meld record
    LDX current_player
    TXA: ASL A: ASL A
    STA tmp6
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp6: STA tmp6   \\ tmp6 = player * 20
    LDY opn_count, X
    TYA: ASL A: ASL A: CLC: ADC tmp6
    TAX                      \\ X = offset into opn_melds
    \\ Store meld: type 3 (closed kan), tile1, tile2, tile3, tile4
    LDA #3: STA opn_melds, X
    LDA tmp5
    STA opn_melds+1, X
    STA opn_melds+2, X
    STA opn_melds+3, X
    STA opn_melds+4, X
    \\ Increment meld count
    LDX current_player
    INC opn_count, X

    \\ Remove 4 copies of tmp5 from hand
    LDA #4: STA tmp8
.cck_rm_lp
    LDX current_player
    JSR set_hand_ptr
    LDY #0
.cck_rm_find
    LDA (ptr), Y
    CMP tmp5: BNE cck_rm_nxt
    JSR ep_remove_at
    DEC tmp8
    BNE cck_rm_lp
    JMP cck_rm_done
.cck_rm_nxt
    INY
    \\ Bounds check
    STY tmp4
    LDX current_player
    LDA num_tiles, X
    CMP tmp4
    BCS cck_rm_find
    JMP cck_rm_done
.cck_rm_done

    \\ Draw replacement from dead wall
    LDA dora_count
    CLC: ADC #DORA_START
    TAX
    LDA wall, X          \\ draw from end of dead wall
    PHA
    LDX current_player
    JSR set_hand_ptr
    PLA
    LDY num_tiles, X
    STA (ptr), Y
    INC num_tiles, X

    \\ Reveal new dora indicator
    JSR reveal_dora
    \\ Increment four kans counter
    INC four_kans_count
    RTS

\\ Check if current player can declare an added kan (4th tile for an open pon).
.check_added_kan
    LDX current_player
    LDA opn_count, X
    BEQ cak_no
    JMP cak_check
.cak_no
    CLC: RTS
.cak_check

    \\ Build tile counts from hand
    JSR build_tile_counts

    \\ For each open meld, check if it's a pon (type 1)
    \\ and if player has a matching tile in hand
    LDX current_player
    TXA: ASL A: ASL A
    STA tmp6
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp6: STA tmp6   \\ tmp6 = player * 20
    LDX current_player
    LDY opn_count, X
    BEQ cak_no
    STY tmp7            \\ tmp7 = meld count

.cak_scan
    DEY
    STY tmp5
    TYA: ASL A: ASL A: CLC: ADC tmp5
    CLC: ADC tmp6: TAX
    INX                  \\ X points to tile1 of meld
    LDA opn_melds, X    \\ meld type
    CMP #1: BNE cak_next \\ only check pons (type 1)
    INX
    LDA opn_melds, X    \\ tile value of pon
    TAY
    LDA tile_counts, Y
    BEQ cak_next        \\ player doesn't have it
    \\ Player has the 4th tile! Check if AI or human

    LDX current_player
    CPX #0
    BEQ cak_human_ask

    \\ AI: auto-declare
    JSR execute_added_kan
    SEC: RTS

.cak_human_ask
    \ tmp8 = tile value from scan. Save it.
    \ Display "Declare Added Kan" prompt
    LDY #0
.cak_prompt_lp
    LDA added_kan_ask, Y
    BEQ cak_prompt_dn
    JSR osnewl: JSR oswrch: INY
    JMP cak_prompt_lp
.cak_prompt_dn
    \ Show which tile: " tile "
    LDA #' ': JSR oswrch
    LDA tmp8: JSR tile_num_char: JSR oswrch
    LDA tmp8: JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    \ Wait for key
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    CMP #'Y': BEQ cak_do_it
    CMP #'y': BEQ cak_do_it
    JMP cak_next

.cak_do_it
    JSR execute_added_kan
    SEC: RTS

.cak_next
    LDY tmp5
    CPY #0: BNE cak_scan

    CLC: RTS

\\ Execute added kan: remove tile from hand, update pon to kan, draw replacement.
.execute_added_kan
    \\ First, find the pon meld to update
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
    INX
    LDA opn_melds, X
    CMP #1: BNE eak_meld_next  \\ skip non-pons
    INX
    LDA opn_melds, X    \\ tile value
    STA tmp8             \\ save tile value

    \\ Check if this pon's tile is in hand
    PHA
    LDX current_player
    JSR build_tile_counts
    PLA
    TAY
    LDA tile_counts, Y
    BEQ eak_meld_next   \\ not in hand
    \\ Found it! Update meld type to 4 (added kan)
    \\ Recalculate offset
    LDX current_player
    TXA: ASL A: ASL A
    STA tmp6
    TXA: ASL A: ASL A: ASL A: ASL A
    CLC: ADC tmp6: STA tmp6
    LDY tmp5
    TYA: ASL A: ASL A: CLC: ADC tmp5
    CLC: ADC tmp6: TAX
    LDA #4: STA opn_melds, X  \\ type 4 = added kan

    \\ Remove one copy of tile from hand
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
    CMP tmp4
    BCS eak_rm_find
    JMP eak_draw

.eak_meld_next
    LDY tmp5
    CPY #0: BNE eak_meld_lp
    CLC: RTS

.eak_draw
    \\ Draw replacement from dead wall
    LDA dora_count
    CLC: ADC #DORA_START
    TAX
    LDA wall, X
    PHA
    LDX current_player
    JSR set_hand_ptr
    PLA
    LDY num_tiles, X
    STA (ptr), Y
    INC num_tiles, X

    \\ Reveal new dora indicator
    JSR reveal_dora
    \\ Increment four kans counter
    INC four_kans_count
    SEC: RTS

\\ Reveal next dora indicator from dead wall.
.reveal_dora
    INC dora_count
    LDA dora_count
    CLC: ADC #DORA_START
    TAX
    LDA wall, X
    STA dora_indicator
    RTS


\ =============================================
\ FURITEN DETECTION
\ =============================================
\ Two forms of furiten:
\ - Temporary: after discard, if your discard + your hand = winning hand,
\   you are in temporary furiten until you draw again.
\ - Permanent: when declaring riichi, if any of your discards + your hand
\   = winning hand, you are permanently in furiten for the rest of the hand.
\ A player in furiten cannot win by ron (only tsumo).

\ check_furiten_for_player:
\ Tests all discards of player in X against their hand.
\ If any discard + hand = winning hand:
\   If player is in riichi -> set permanent furiten (bit 1)
\   Otherwise -> set temporary furiten (bit 0)
\ Preserves X on entry.
.check_furiten_for_player
    STX tmp5                 \ save player index
    JSR build_tile_counts    \ build counts for this player hand
    \ Check each discard
    JSR set_disc_ptr
    LDY num_discards, X
    BEQ cff_done
    STY tmp8                 \ tmp8 = number of discards
.cff_loop
    DEY
    STY tmp4                 \ save discard index
    \ Temporarily add discard tile to counts
    LDA (ptr), Y
    TAX
    INC tile_counts, X
    \ Check if this forms a winning hand
    JSR check_win_no_rebuild
    \ Remove the temporary tile
    LDY tmp4
    LDA (ptr), Y
    TAX
    DEC tile_counts, X
    BCS cff_found
    LDY tmp4
    CPY #0
    BNE cff_loop
    JMP cff_done
.cff_found
    \ Player is in furiten - set appropriate flag
    LDX tmp5
    LDA riichi_declared, X
    BNE cff_set_perm
    \ Set temporary furiten (bit 0)
    LDA furiten_flags, X
    ORA #1
    STA furiten_flags, X
    JMP cff_done
.cff_set_perm
    \ Set permanent furiten (bit 1)
    LDA furiten_flags, X
    ORA #2
    STA furiten_flags, X
.cff_done
    LDX tmp5                 \ restore player index
    RTS

\ check_furiten_after_discard:
\ Called after a discard to update furiten status for the discarder.
.check_furiten_after_discard
    LDX current_player
    JSR check_furiten_for_player
    RTS

.game_init
    JSR wall_build
    JSR wall_shuffle
    JSR deal_all
    \\ Reveal initial dora indicator from dead wall
    LDA wall+DORA_START
    STA dora_indicator
    LDA #0: STA dora_count
    LDA #0: STA current_player
    LDA #0: STA dealer: STA hands_played
    \ Initialize seat winds - player 0 is East initially
    LDA #27: STA seat_winds
    LDA #28: STA seat_winds+1
    LDA #29: STA seat_winds+2
    LDA #30: STA seat_winds+3
    \ Initialize points to 25000 for each player
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
    \\ Initialize abortive draw counters
    LDA #0
    STA first_disc_winds
    STA first_disc_winds+1
    STA first_disc_winds+2
    STA first_disc_winds+3
    STA four_kans_count
    \\ Reset chombo counts
    LDX #0
.gi_ch
    STA chombo_count, X
    INX: CPX #NUM_PLAYERS: BNE gi_ch
    \\ Reset per-player kans count
    LDX #0
.gi_kans
    STA player_kans, X
    INX: CPX #NUM_PLAYERS: BNE gi_kans
    \\ Reset yakuman flags
    STA yakuman_flags
    RTS
\ =============================================
\ WALL OPERATIONS
\ =============================================

.wall_build
    LDX #0: LDY #0
.wb_lp
    TYA: STA wall, X
    INX
    TXA: AND #3: BNE wb_lp
    INY: CPY #34: BNE wb_lp
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
    LDA rng_seed
    ASL A: ASL A: CLC
    ADC rng_seed: ADC #7
    STA rng_seed
    RTS

\ =============================================
\ DEALING
\ =============================================

.deal_all
    LDX #0
.da_lp
    LDA wall, X: STA hands, X
    INX
    CPX #(INITIAL_HAND * NUM_PLAYERS): BNE da_lp
    LDA #(INITIAL_HAND * NUM_PLAYERS): STA wall_pos
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

\ =============================================
\ POINTER HELPERS
\ =============================================

\ Set ptr to player X's hand. Preserves X.
.set_hand_ptr
    STX tmp5
    TXA: ASL A: TAX
    LDA hand_bases, X: STA ptr
    LDA hand_bases+1, X: STA ptr+1
    LDX tmp5
    RTS

\ Set ptr to player X's discards. Preserves X.
.set_disc_ptr
    STX tmp5
    TXA: ASL A: TAX
    LDA disc_bases, X: STA ptr
    LDA disc_bases+1, X: STA ptr+1
    LDX tmp5
    RTS

\ =============================================
\ PLAYER OPERATIONS
\ =============================================

\ Draw a tile for current player
.player_draw
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

\ Discard tile at position X (0-based) for current player
.player_discard
    STX tmp
    LDX current_player
    JSR set_hand_ptr
    LDY tmp
    LDA (ptr), Y
    PHA
    LDX current_player
    JSR set_disc_ptr
    LDY num_discards, X
    PLA
    STA (ptr), Y
    INC num_discards, X
    \ Shift hand left to remove tile
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
    \ Clear temporary furiten for this player
    LDX current_player
    LDA furiten_flags, X
    AND #&FE              \ clear bit 0 (temp furiten)
    STA furiten_flags, X
    RTS

\ =============================================
\ SORT HAND (bubble sort, player in X)
\ =============================================

.sort_hand
    JSR set_hand_ptr
    LDA num_tiles, X
    BEQ sr_dn
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
    BCC sr_no
    \ Swap
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

\ =============================================
\ AI LOGIC
\ =============================================

\ Choose best tile to discard for current player.
\ Returns 0-based position in X.
.ai_choose_discard
    STX tmp5
    JSR set_hand_ptr
    LDA num_tiles, X
    STA tmp7
    LDA ai_difficulty
    CMP #2: BEQ ai_expert_discard
    CMP #1: BEQ ai_intermediate_discard
    \ Novice: use simple evaluation (current algorithm)
    LDA #$FF: STA tmp
    LDA #0: STA tmp2
    LDA #0: STA tmp3
    JMP ai_outer

.ai_intermediate_discard
    \ Intermediate: evaluate by counting connected tiles
    \ Score each tile: pairs +3, adjacent +2, gap +1
    \ Same as novice but with bonus for terminal tiles
    LDA #$FF: STA tmp
    LDA #0: STA tmp2
    LDA #0: STA tmp3
    JMP ai_outer

.ai_expert_discard
    \ Expert: try to evaluate hand closeness to winning
    \ Build tile counts and use a better evaluation
    \ Score tiles by how much removing them hurts the hand
    \ Higher score = more important = less likely to discard
    LDA #$FF: STA tmp
    LDA #0: STA tmp2
    LDA #0: STA tmp3
    JMP ai_outer

.ai_outer
    LDY tmp3
    CPY tmp7: BCS ai_done
    LDA (ptr), Y
    STA tmp4
    LDA #0: STA tmp6
    LDY #0

.ai_inner
    CPY tmp7: BCS ai_eval_done
    CPY tmp3: BEQ ai_next_j
    LDA (ptr), Y
    CMP tmp4: BNE ai_not_pair
    LDA tmp6: CLC: ADC #3
    STA tmp6
    JMP ai_next_j

.ai_not_pair
    LDA tmp4
    CMP #27: BCS ai_next_j
    LDA (ptr), Y
    CMP #27: BCS ai_next_j
    JSR check_same_suit
    BCC ai_next_j
    LDA (ptr), Y
    SEC: SBC tmp4
    BPL ai_abs
    EOR #$FF: CLC: ADC #1
.ai_abs
    CMP #1: BNE ai_nadj1
    LDA tmp6: CLC: ADC #2
    STA tmp6
    JMP ai_next_j
.ai_nadj1
    CMP #2: BNE ai_next_j
    LDA tmp6: CLC: ADC #1
    STA tmp6

.ai_next_j
    INY
    JMP ai_inner

.ai_eval_done
    LDA tmp6
    CMP tmp: BCS ai_skip
    LDA tmp6: STA tmp
    LDA tmp3: STA tmp2
.ai_skip
    INC tmp3
    JMP ai_outer

.ai_done
    LDX tmp2
    RTS

\ Check same suit for tile in tmp4 and (ptr),Y. C set if same.
.check_same_suit
    LDA tmp4
    CMP #9: BCC css_man
    CMP #18: BCC css_pin
    LDA (ptr), Y
    CMP #18: BCC css_no
    CMP #27: BCS css_no
    SEC: RTS
.css_man
    LDA (ptr), Y
    CMP #9: BCS css_no
    SEC: RTS
.css_pin
    LDA (ptr), Y
    CMP #9: BCC css_no
    CMP #18: BCS css_no
    SEC: RTS
.css_no
    CLC: RTS

\ =============================================
\ OPEN CALL DETECTION
\ =============================================
\ After a discard, check if any other player can claim it.
\ Per Turn Sequence: check Pon, Chii, Kan.
\ Returns: C set = call made (current_player changed), C clear = no call.

\ Count tiles for player X into tile_counts.
.count_tiles_for_player
    JSR set_hand_ptr
    LDA #0: LDY #0
.ctfp_clear
    STA tile_counts, Y
    INY: CPY #34: BNE ctfp_clear
    LDY num_tiles, X
    BEQ ctfp_done
    DEY
.ctfp_loop
    LDA (ptr), Y
    PHA: TAX
    INC tile_counts, X
    PLA: TAY
    DEY
    BPL ctfp_loop
.ctfp_done
    RTS

\ Main open call check.
.check_open_calls
    LDX disc_tile_player
    STX tmp7                 \ tmp7 = who discarded
    LDX #0
.soc_lp
    CPX tmp7: BEQ soc_skip
    STX tmp5                 \ tmp5 = checking player
    JSR count_tiles_for_player

    \ Check Pon
    LDY disc_tile_val
    LDA tile_counts, Y
    CMP #2
    BCC soc_try_chii
    \ Human player: prompt first
    LDX tmp5
    CPX #0
    BNE soc_pon_ai
    JSR soc_human_prompt_pon
    BCC soc_try_chii          \ N = skip pon, try chii
    JSR execute_pon
    SEC: RTS
.soc_pon_ai
    JSR execute_pon
    SEC: RTS

.soc_try_chii
    \ Chii only from left player (discarder+1 mod 4)
    LDA tmp7
    CLC: ADC #1: AND #3
    CMP tmp5: BNE soc_try_kan
    \ Only suited tiles
    LDA disc_tile_val
    CMP #27: BCS soc_try_kan
    \ Try 3 Chii patterns
    JSR try_chii_low
    BCS soc_do_chii
    JSR try_chii_mid
    BCS soc_do_chii
    JSR try_chii_high
    BCS soc_do_chii
    JMP soc_try_kan
.soc_do_chii
    \ Human player: prompt first
    LDX tmp5
    CPX #0
    BNE soc_chii_ai
    JSR soc_human_prompt_chii
    BCC soc_try_kan          \ N = skip chii, try kan
    JSR execute_chii
    SEC: RTS
.soc_chii_ai
    JSR execute_chii
    SEC: RTS

.soc_try_kan
    LDY disc_tile_val
    LDA tile_counts, Y
    CMP #3
    BCC soc_skip
    \ Human player: prompt first
    LDX tmp5
    CPX #0
    BNE soc_kan_ai
    JSR soc_human_prompt_kan
    BCC soc_skip              \ N = skip kan
    JSR execute_kan
    SEC: RTS
.soc_kan_ai
    JSR execute_kan
    SEC: RTS

.soc_skip
    LDX tmp5
    INX
    CPX #NUM_PLAYERS
    BEQ soc_done
    JMP soc_lp
.soc_done
    CLC
    RTS

\ =============================================
\ HUMAN OPEN CALL PROMPTS
\ =============================================
\ Display prompt and read Y/N for open calls.
\ Returns C set if human said Y, C clear if N.

\ Prompt for Pon
.soc_human_prompt_pon
    LDY #0
.shp_lp
    LDA pon_ask_str, Y
    BEQ shp_dn
    JSR osnewl: JSR oswrch: INY
    JMP shp_lp
.shp_dn
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    CMP #'Y': BEQ shp_yes
    CMP #'y': BEQ shp_yes
    CLC: RTS
.shp_yes
    SEC: RTS

\ Prompt for Chii
.soc_human_prompt_chii
    LDY #0
.shc_lp
    LDA chii_ask_str, Y
    BEQ shc_dn
    JSR osnewl: JSR oswrch: INY
    JMP shc_lp
.shc_dn
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    CMP #'Y': BEQ shc_yes
    CMP #'y': BEQ shc_yes
    CLC: RTS
.shc_yes
    SEC: RTS

\ Prompt for Kan from discard
.soc_human_prompt_kan
    LDY #0
.shk_lp
    LDA kan_ask_str, Y
    BEQ shk_dn
    JSR osnewl: JSR oswrch: INY
    JMP shk_lp
.shk_dn
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    CMP #'Y': BEQ shk_yes
    CMP #'y': BEQ shk_yes
    CLC: RTS
.shk_yes
    SEC: RTS

\ Chii: disc tile as low end (need X+1, X+2)
.try_chii_low
    LDA disc_tile_val
    CLC: ADC #1
    CMP #27: BCS tcl_no
    TAX: LDA tile_counts, X
    BEQ tcl_no
    LDA disc_tile_val
    CLC: ADC #2
    CMP #27: BCS tcl_no
    TAX: LDA tile_counts, X
    BEQ tcl_no
    SEC: RTS
.tcl_no
    CLC: RTS

\ Chii: disc tile as middle (need X-1, X+1)
.try_chii_mid
    LDA disc_tile_val
    \ Check lower tile in same suit
    CMP #9: BCC tcm_man
    CMP #18: BCC tcm_pin
    CMP #27: BCC tcm_sou
    CLC: RTS
.tcm_man
    CMP #2: BCC tcm_no     \ need tile >= 2
    JMP tcm_check
.tcm_pin
    CMP #11: BCC tcm_no    \ need tile >= 11
    JMP tcm_check
.tcm_sou
    CMP #20: BCC tcm_no    \ need tile >= 20
.tcm_check
    TAX: DEX
    LDA tile_counts, X
    BEQ tcm_no
    LDA disc_tile_val
    CLC: ADC #1
    TAX: LDA tile_counts, X
    BEQ tcm_no
    SEC: RTS
.tcm_no
    CLC: RTS

\ Chii: disc tile as high end (need X-2, X-1)
.try_chii_high
    LDA disc_tile_val
    CMP #9: BCC tch_man
    CMP #18: BCC tch_pin
    CMP #27: BCC tch_sou
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
    BEQ tch_no
    INX
    LDA tile_counts, X
    BEQ tch_no
    SEC: RTS
.tch_no
    CLC: RTS

\ Execute Pon: claim discarded tile with 2 from hand.
\ Removes 2 tiles, adds open meld, sets current_player.
.execute_pon
    LDX tmp5
    STX current_player
    JSR set_hand_ptr
    \ Find and remove 2 copies of disc_tile_val
    LDA #0: STA tmp8          \ removal counter
    LDY #0
.ep_find
    STY tmp4
    LDA num_tiles, X
    CMP tmp4
    BCC skp_654
    JMP ep_add
.skp_654
    LDA (ptr), Y
    CMP disc_tile_val: BNE ep_next
    INC tmp8
    LDA tmp8: CMP #2: BEQ ep_rm2
.ep_next
    INY: JMP ep_find
.ep_rm2
    \ Found 2nd copy at Y-1 (we incremented past it)
    DEY: JSR ep_remove_at
    \ Re-find and remove first copy
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

\ Remove tile at position Y from hand (shift left)
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

\ Execute Chii: claim discarded tile with 2 from hand (sequence).
.execute_chii
    LDX tmp5
    STX current_player
    JSR set_hand_ptr
    \ Find and remove 2 tiles that form sequence with disc_tile_val
    \ Try disc+1 and disc+2 first
    LDA disc_tile_val: CLC: ADC #1
    STA tmp8                 \ first tile to find
    LDA disc_tile_val: CLC: ADC #2
    STA tmp9                 \ second tile to find
    LDX current_player
    JSR set_hand_ptr
    \ Remove tmp8
    LDY #0
.ec_find1
    LDA (ptr), Y
    CMP tmp8: BNE ec_n1
    JSR ep_remove_at
    JMP ec_rm2
.ec_n1
    INY: JMP ec_find1
.ec_rm2
    \ Re-find hand pointer and remove tmp9
    LDX current_player
    JSR set_hand_ptr
    LDY #0
.ec_find2
    LDA (ptr), Y
    CMP tmp9: BNE ec_n2
    JSR ep_remove_at
    JMP ep_add
.ec_n2
    INY: JMP ec_find2

\ Execute Kan: claim discarded tile with 3 from hand.
.execute_kan
    LDX tmp5
    STX current_player
    JSR set_hand_ptr
    \ Remove 3 copies of disc_tile_val
    LDA #3: STA tmp8          \ need to remove 3
.ek_rm_loop
    LDX current_player
    JSR set_hand_ptr
    LDY #0
.ek_rm_find
    LDA (ptr), Y
    CMP disc_tile_val: BNE ek_rm_nxt
    JSR ep_remove_at
    DEC tmp8
    BNE ek_rm_loop
    \\ All 3 removed, fall through to ep_add
.ek_rm_nxt
    INY
    STY tmp4
    LDA num_tiles, X
    CMP tmp4
    BCS ek_rm_find \\ if num_tiles >= Y, continue scanning
    \\ Increment per-player kans count
    LDX current_player
    INC player_kans, X
    JMP ep_add     \\ past end of hand
.ep_add
    \ Calculate offset into opn_melds
    \ offset = player * 20 + count * 5
    LDX current_player
    TXA: ASL A: ASL A       \ * 4
    STA tmp4
    TXA: ASL A: ASL A: ASL A: ASL A \ * 16
    CLC: ADC tmp4            \ = * 20
    STA tmp4                 \ tmp4 = player * 20
    \ Add count * 5
    LDX current_player
    LDY opn_count, X
    BEQ ep_off_done
    LDA #0
.ep_mul5
    CLC: ADC #5
    DEY: BNE ep_mul5
    JMP ep_off_add
.ep_off_done
    LDA #0
.ep_off_add
    CLC: ADC tmp4            \ + player * 20
    TAX                      \ X = offset into opn_melds
    \ Determine meld type from caller
    \ For now, all calls are pon (type 1)
    LDA #1
    STA opn_melds, X
    INX
    LDA disc_tile_val
    STA opn_melds, X
    STA opn_melds+1, X
    STA opn_melds+2, X
    \ Increment meld count
    LDX current_player
    INC opn_count, X
    \ Remove last entry from discard pile
    JSR set_disc_ptr
    LDA num_discards, X
    SEC: SBC #1
    STA num_discards, X
    \\ Set skip_draw
    LDA #1
    STA skip_draw
    \\ Increment four kans counter
    INC four_kans_count
    RTS

\ =============================================
\ DISPLAY
\ =============================================

.game_display
    LDA #12: JSR oswrch

    \ Title
    LDY #0
.gd_title
    LDA title_str, Y
    BEQ gd_title_dn
    JSR oswrch: INY
    JMP gd_title
.gd_title_dn
    JSR osnewl
    JSR disp_points_line
    JSR osnewl

    \ Human hand header
    LDY #0
.gd_hh
    LDA hand_hdr_str, Y
    BEQ gd_hh_dn
    JSR oswrch: INY
    JMP gd_hh
.gd_hh_dn
    \ Print seat wind in brackets
    LDA #' ': JSR oswrch
    LDA #'(': JSR oswrch
    LDA seat_winds
    JSR tile_num_char: JSR oswrch
    LDA #')': JSR oswrch
    LDA #':': JSR oswrch
    JSR osnewl

    \ Hand top row (numbers/symbols)
    LDX #0
.gd_ht
    CPX num_tiles: BCS gd_ht_dn
    LDA hands, X
    JSR tile_num_char: JSR oswrch
    LDA #' ': JSR oswrch
    INX: JMP gd_ht
.gd_ht_dn
    JSR osnewl

    \ Hand bottom row (suits)
    LDX #0
.gd_hb
    CPX num_tiles: BCS gd_hb_dn
    LDA hands, X
    JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    INX: JMP gd_hb
.gd_hb_dn
    JSR osnewl: JSR osnewl

    \ Human discards
    LDY #0
.gd_mydi
    LDA my_disc_str, Y
    BEQ gd_mydi_dn
    JSR oswrch: INY
    JMP gd_mydi
.gd_mydi_dn
    \ Print seat wind in brackets
    LDA #' ': JSR oswrch
    LDA #'(': JSR oswrch
    LDA seat_winds
    JSR tile_num_char: JSR oswrch
    LDA #')': JSR oswrch
    LDA #':': JSR oswrch
    LDX #0
    JSR set_disc_ptr
    LDY num_discards, X
    BEQ gd_mydisc_nl
    STY tmp6
    LDY #0
.gd_my_lp
    CPY tmp6: BEQ gd_mydisc_nl
    LDA (ptr), Y: PHA
    JSR tile_num_char: JSR oswrch
    PLA
    JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    INY: JMP gd_my_lp
.gd_mydisc_nl
    JSR osnewl
    \ Show human open melds
    LDX #0
    JSR disp_open_melds

    \ AI discards (players 1-3)
    LDX #1
.gd_disc_lp
    CPX #NUM_PLAYERS: BCS gd_disc_dn
    STX tmp7
    LDA #'P': JSR oswrch
    TXA: CLC: ADC #'1'
    JSR oswrch
    \ Print seat wind in brackets
    PHA
    LDA seat_winds, X
    JSR tile_num_char: JSR oswrch
    PLA
    LDA #':': JSR oswrch
    LDA #' ': JSR oswrch
    JSR set_disc_ptr
    LDX tmp7
    LDY num_discards, X
    BEQ gd_disc_nl
    STY tmp6
    LDY #0
.gd_d_lp
    CPY tmp6: BEQ gd_disc_nl
    LDA (ptr), Y: PHA
    JSR tile_num_char: JSR oswrch
    PLA
    JSR tile_suit_char: JSR oswrch
    LDA #' ': JSR oswrch
    INY: JMP gd_d_lp
.gd_disc_nl
    JSR osnewl
    \ Show open melds for this AI player
    LDA tmp7: PHA
    LDX tmp7
    JSR disp_open_melds
    PLA: STA tmp7
    LDX tmp7
    INX
    JMP gd_disc_lp
.gd_disc_dn
    JSR osnewl

    \ Instructions
    LDY #0
.gd_inst
    LDA inst_str, Y
    BEQ gd_done
    JSR oswrch: INY
    JMP gd_inst
.gd_done
    RTS

\ =============================================
\ POINT DISPLAY
\ =============================================

\ Display points for all 4 players + honba
\ Format: P1:25000 P2:25000 P3:25000 P4:25000 H:0
.disp_points_line
    LDX #0
.dpl_lp
    STX tmp5
    \ Print "P" + player number + ":"
    LDA #'P': JSR oswrch
    TXA: CLC: ADC #'1': JSR oswrch
    LDA #':': JSR oswrch
    \ Load player's points (16-bit, little-endian)
    TXA: ASL A: TAX
    LDA player_points+1, X
    PHA
    LDA player_points, X
    TAX
    PLA                     \ A=high, X=low
    JSR print_num16
    \ Print space between players
    LDA tmp5
    CMP #NUM_PLAYERS-1
    BEQ dpl_honba
    \ Show F marker if furiten, R if riichi, space otherwise
    LDY tmp5
    LDA furiten_flags, Y
    BEQ dpl_no_furi
    LDA #'F': JSR oswrch
    JMP dpl_honba
.dpl_no_furi
    LDA riichi_declared, Y
    BEQ dpl_no_riichi
    LDA #'R': JSR oswrch
    JMP dpl_honba
.dpl_no_riichi
    LDA chombo_count, Y
    BEQ dpl_no_chombo
    LDA #'C': JSR oswrch
    JMP dpl_honba
.dpl_no_chombo
    LDA #' ': JSR oswrch
.dpl_honba
    LDX tmp5
    INX
    CPX #NUM_PLAYERS
    BNE dpl_lp
    \\ Print honba and round info on one line
    LDA #' ': JSR oswrch
    LDA #'H': JSR oswrch
    LDA #':': JSR oswrch
    LDA honba
    CLC: ADC #'0'
    JSR oswrch
    \ Print round wind
    LDA hands_played
    CMP #4
    BCC dpl_east
    LDA #'S': JSR oswrch
    JMP dpl_round_dn
.dpl_east
    LDA #'E': JSR oswrch
.dpl_round_dn
    \ Print dealer number
    LDA #'D': JSR oswrch
    LDX dealer
    INX
    TXA: CLC: ADC #'0'
    JSR oswrch
    \ Print dora indicator
    LDA #'O': JSR oswrch
    LDA dora_indicator
    JSR tile_num_char: JSR oswrch
    LDA dora_indicator
    JSR tile_suit_char: JSR oswrch
    \ Print wall remaining count
    LDA #' ': JSR oswrch
    LDA #'W': JSR oswrch
    LDA #':': JSR oswrch
    LDA #DORA_START
    SEC: SBC wall_pos
    \ Print as 2-digit decimal
    LDX #0
.wc10
    CMP #10: BCC wc10dn
    SEC: SBC #10: INX: JMP wc10
.wc10dn
    PHA
    TXA: CLC: ADC #'0': JSR oswrch
    PLA: CLC: ADC #'0': JSR oswrch
    RTS

\ Print 16-bit value as 5 decimal digits
\ Input: A = high byte, X = low byte
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
    BPL pn_outer
    LDY #0
.pn_print
    PLA: JSR oswrch
    INY: CPY #5: BNE pn_print
    RTS

\ Divide tmp2:tmp3 by 10
\ Quotient in tmp2:tmp3, remainder in A
.pn_div10
    LDA #0
    LDY #16
.pd_loop
    ASL tmp3
    ROL tmp2
    ROL A
    CMP #10
    BCC pd_skip
    SBC #10
    INC tmp3
.pd_skip
    DEY
    BNE pd_loop
    RTS

\ =============================================
\ TILE CHARACTER ROUTINES
\ =============================================

\ A = tile value (0-33). Returns display char in A.
\ Preserves X and Y (used by caller's loop counters).
.tile_num_char
    CMP #27: BCS tnc_honor
    CMP #18: BCC tnc_cp
    SEC: SBC #18
    JMP tnc_dig
.tnc_cp
    CMP #9: BCC tnc_dig
    SEC: SBC #9
.tnc_dig
    CLC: ADC #'1'
    RTS
.tnc_honor
    \ Must preserve X and Y for caller's loop counters
    \ A = tile value on entry, must compute offset = A - 27
    STA tmp8                        \ save tile value
    TYA: PHA                        \ save Y
    LDA tmp8                        \ restore tile value
    SEC: SBC #27
    TAY                             \ Y = offset into honor_nums
    LDA honor_nums, Y              \ A = display character
    STA tmp8                        \ save result
    PLA: TAY                        \ restore Y
    LDA tmp8                        \ restore result to A
    RTS                             \ A = character, X/Y preserved

\ A = tile value (0-33). Returns suit char in A.
\ Winds (27-30): 'w' for all (top letter distinguishes them)
\ Dragons (31-33): 'g'=green(Hatsu), 'b'=blank(Haku), 'r'=red(Chun)
\ Must preserve X and Y for caller's loop counters.
.tile_suit_char
    CMP #9: BCC tsc_m
    CMP #18: BCC tsc_p
    CMP #27: BCC tsc_s
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

\ =============================================
\ MELD DECOMPOSITION ENGINE
\ =============================================
\ Core algorithm for win detection.
\ Recursively decomposes a hand into melds (triplets/sequences) + pair.
\ Based on the Mahjong overview [1] as the most important subsystem.

\ Build tile_counts (34 bytes at &7C) from current player's hand.
\ Counts how many of each tile type (0-33) are in the hand.
.build_tile_counts
    \ Clear tile_counts
    LDX #0
    LDA #0
.btc_clear
    STA tile_counts, X
    INX
    CPX #34
    BNE btc_clear
    \ Count tiles from current player's hand
    LDX current_player
    JSR set_hand_ptr
    LDY num_tiles, X
    BEQ btc_done
    DEY
.btc_count
    LDA (ptr), Y
    TAX
    INC tile_counts, X
    DEY
    BPL btc_count
.btc_done
    RTS

\ Recursive meld decomposition.
\ Attempts to decompose all tiles with count > 0 into melds.
\ Uses backtracking: tries triplet first, then sequence.
\ Returns: C set = success (all tiles decomposed), C clear = failure.
\ Preserves X on entry (caller's loop variable).
.decompose_melds
    \ Find first tile with count > 0
    LDX #0
.dm_find
    LDA tile_counts, X
    BNE dm_found
    INX
    CPX #34
    BNE dm_find
    \ All counts are zero - all tiles decomposed successfully!
    SEC
    RTS

.dm_found
    \ Save tile index on stack for backtracking
    TXA: PHA

    \ Try triplet (count >= 3)
    CMP #3
    BCC dm_try_seq

    \ Remove triplet
    SEC: SBC #3
    STA tile_counts, X
    \ Recurse
    JSR decompose_melds
    BCS dm_success
    \ Backtrack: restore triplet
    PLA: TAX            \ restore tile index
    PHA                 \ save again for potential sequence attempt
    LDA tile_counts, X
    CLC: ADC #3
    STA tile_counts, X

.dm_try_seq
    \ Skip sequences if no_seq_flag is set (for toitoi check)
    LDA no_seq_flag: BNE dm_fail

    \ Try sequence (only suited tiles 0-26)
    PLA: TAX            \ restore tile index
    PHA                 \ save again for potential backtrack
    CPX #27
    BCS dm_fail
    \ Check tiles X+1 and X+2 exist
    LDA tile_counts+1, X
    BEQ dm_fail
    LDA tile_counts+2, X
    BEQ dm_fail
    \ Remove sequence
    DEC tile_counts, X
    DEC tile_counts+1, X
    DEC tile_counts+2, X
    \ Recurse
    JSR decompose_melds
    BCS dm_success
    \ Backtrack: restore sequence
    PLA: TAX            \ restore tile index
    INC tile_counts, X
    INC tile_counts+1, X
    INC tile_counts+2, X
    CLC
    RTS

.dm_fail
    PLA                 \ clean up stack
    CLC
    RTS

.dm_success
    PLA                 \ clean up stack
    SEC
    RTS

\ Check if a 14-tile hand (13 dealt + 1 drawn) is a winning hand.
\ Standard win: 4 melds + 1 pair.
\ Also checks seven pairs.
\ Returns: C set = win, C clear = not a win.
\ Calls build_tile_counts internally.
.check_win
    JSR build_tile_counts

    \ Try each possible pair (tile with count >= 2)
    LDX #0
.cw_try_pair
    LDA tile_counts, X
    CMP #2
    BCC cw_next_pair

    \ Remove pair from counts
    SEC: SBC #2
    STA tile_counts, X

    \ Save pair tile index on stack (tmp8 is used by decompose_melds)
    TXA: PHA

    \ Try to decompose remaining 12 tiles into 4 melds
    JSR decompose_melds
    BCS cw_win

    \ Backtrack: restore pair
    PLA: TAX            \ restore pair tile index
    PHA                 \ save it again for restore after
    LDA tile_counts, X
    CLC: ADC #2
    STA tile_counts, X
    PLA: TAX            \ restore X for the loop

.cw_next_pair
    INX
    CPX #34
    BNE cw_try_pair

    \ Standard win failed - check seven pairs
    JSR check_seven_pairs
    BCS cw_win

    \ Not a winning hand
    CLC
    RTS

.cw_win
    PLA                 \ clean up saved X from stack
    SEC
    RTS

\ Check for seven pairs win condition.
\ Requires exactly 7 pairs (each tile count is 0 or 2).
\ Returns: C set = seven pairs, C clear = not seven pairs.
.check_seven_pairs
    LDX #0
    LDY #0          \ pair counter
.csp_loop
    LDA tile_counts, X
    BEQ csp_next
    CMP #2
    BNE csp_fail    \ count must be exactly 0 or 2
    INY             \ found a pair
.csp_next
    INX
    CPX #34
    BNE csp_loop
    \ Must have exactly 7 pairs
    CPY #7
    BNE csp_fail
    SEC
    RTS
.csp_fail
    CLC
    RTS

\ Check for thirteen orphans (kokushi musou).
\ Requires one of each 1-9 man, 1-9 pin, 1-9 sou, all 4 winds, all 3 dragons,
\ plus one duplicate of any of these terminal/honor tiles.
\ Returns: C set = thirteen orphans, C clear = not thirteen orphans.
.check_thirteen_orphans
    \ Clear tile counts
    LDX #0
    LDA #0
.cto_clear
    STA tile_counts, X
    INX
    CPX #34
    BNE cto_clear
    \ Count tiles from current player's hand
    LDX current_player
    JSR set_hand_ptr
    LDY num_tiles, X
    BEQ cto_fail
    DEY
.cto_count
    LDA (ptr), Y
    TAX
    INC tile_counts, X
    DEY
    BPL cto_count

    \ Must have exactly 14 tiles
    LDX current_player
    LDA num_tiles, X
    CMP #HAND_SIZE
    BNE cto_fail

    \ Check all 13 terminal/honor tiles exist at least once
    LDY #0          \ pair found flag
    LDX #0          \ tile index
.cto_check
    LDA tile_counts, X
    BEQ cto_fail    \ missing a required tile
    CMP #1
    BEQ cto_next
    CMP #2
    BNE cto_fail    \ count > 2 not allowed
    INY             \ found pair
    CPY #2
    BCS cto_fail    \ more than one pair
.cto_next
    INX
    CPX #34
    BNE cto_check
    \ Must have exactly one pair (Y = 1)
    CPY #1
    BNE cto_fail
    SEC
    RTS
.cto_fail
    CLC
    RTS


\ =============================================
\ SCORING SYSTEM
\ =============================================

\ Main scoring entry point
.calculate_score
    LDA #0
    STA han_count: STA fu_count: STA yaku_flags: STA yaku_flags2: STA yaku_flags3
    JSR build_tile_counts

    \ Determine if hand is closed
    LDX current_player
    LDA opn_count, X
    CMP #1
    LDA #0
    BCS cs_set_open
    LDA #1
.cs_set_open
    STA hand_closed

    \ --- TANYAO (1 han) ---
    JSR check_tanyao
    BCC cs_no_tanyao
    INC han_count
    LDA yaku_flags: ORA #&01: STA yaku_flags
.cs_no_tanyao

    \ --- YAKUHAI ---
    JSR check_yakuhai

    \ --- TOITOI (2 han) ---
    JSR check_toitoi
    BCC cs_no_toitoi
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags: ORA #&80: STA yaku_flags
.cs_no_toitoi

    \ --- CHINITSU (6 han) ---
    JSR check_chinitsu
    BCC cs_no_chi
    LDA han_count: CLC: ADC #6: STA han_count
    LDA yaku_flags: ORA #&40: STA yaku_flags
    JMP cs_fu
.cs_no_chi

    \ --- HONITSU (3 han) ---
    JSR check_honitsu
    BCC cs_no_hon
    LDA han_count: CLC: ADC #3: STA han_count
    LDA yaku_flags: ORA #&20: STA yaku_flags
.cs_no_hon

    \ --- PINFU (1 han, closed only) ---
.cs_fu
    LDA hand_closed: BEQ cs_no_pin
    JSR check_pinfu
    BCC cs_no_pin
    INC han_count
    LDA yaku_flags: ORA #&02: STA yaku_flags
.cs_no_pin
    \ --- IPPATSU (1 han, closed, riichi + ippatsu flag) ---
    LDX current_player
    LDA hand_closed: BEQ cs_no_ipp
    LDA riichi_on_table, X
    AND #1: BEQ cs_no_ipp
    LDA ippatsu_flags, X
    BEQ cs_no_ipp
    INC han_count
    LDA yaku_flags2: ORA #&01: STA yaku_flags2
.cs_no_ipp
    LDA hand_closed: BEQ cs_no_iip
    JSR check_iipeiko
    BCC cs_no_iip
    INC han_count
    LDA yaku_flags2: ORA #&02: STA yaku_flags2
.cs_no_iip

    \ --- RYANPEIKOU (3 han, closed only) ---
    LDA hand_closed: BEQ cs_no_ryp
    JSR check_ryanpeikou
    BCC cs_no_ryp
    LDA han_count: CLC: ADC #3: STA han_count
    LDA yaku_flags2: ORA #&80: STA yaku_flags2
.cs_no_ryp

    \ --- SANSHOKU (1 han) ---
    JSR check_sanshoku
    BCC cs_no_sans
    INC han_count
    LDA yaku_flags2: ORA #&04: STA yaku_flags2
.cs_no_sans

    \ --- ITTSU (2 han) ---
    JSR check_ittsu
    BCC cs_no_itt
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags2: ORA #&08: STA yaku_flags2
.cs_no_itt

    \ --- CHANTA (2 han closed / 1 han open) ---
    JSR check_chanta
    BCC cs_no_cha
    LDA hand_closed
    BEQ cs_cha_open
    LDA han_count: CLC: ADC #2: STA han_count
    JMP cs_cha_set
.cs_cha_open
    INC han_count
.cs_cha_set
    LDA yaku_flags2: ORA #&10: STA yaku_flags2
.cs_no_cha

    \ --- SHOU SANGEN (2 han) ---
    JSR check_shousangen
    BCC cs_no_ss
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags2: ORA #&20: STA yaku_flags2
.cs_no_ss

    \ --- CHII TOITSU (2 han) ---
    JSR check_chitoitsu
    BCC cs_no_ct
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags2: ORA #&40: STA yaku_flags2
.cs_no_ct

    \\ --- MENZEN TSUMO (1 han, closed only, self-draw) ---
    LDA hand_closed: BEQ cs_no_mt
    LDA tsumo_flag: BEQ cs_no_mt
    INC han_count
    LDA yaku_flags3: ORA #&80: STA yaku_flags3
.cs_no_mt

    \\ --- SANANKOU (2 han) - three concealed triplets ---
    JSR check_sanankou
    BCC cs_no_sa
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags3: ORA #&01: STA yaku_flags3
.cs_no_sa

    \\ --- HONROUTOU (2 han) - all terminals and honors ---
    JSR check_honroutou
    BCC cs_no_hr
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags3: ORA #&02: STA yaku_flags3
.cs_no_hr

    \\ --- SANSHOKU DOUKOU (2 han) - same triplets across 3 suits ---
    JSR check_sanshoku_doukou
    BCC cs_no_sd
    LDA han_count: CLC: ADC #2: STA han_count
    LDA yaku_flags3: ORA #&04: STA yaku_flags3
.cs_no_sd

    \\ --- YAKUMAN CHECKS ---
    LDA #0: STA yakuman_flags

    \\ Check Suukantsu (Four Kans)
    JSR check_suukantsu
    BCC cs_no_suuk
    LDA yakuman_flags: ORA #&01: STA yakuman_flags
.cs_no_suuk

    \\ Check Daisangen (Big Three Dragons)
    JSR check_daisangen
    BCC cs_no_dai
    LDA yakuman_flags: ORA #&02: STA yakuman_flags
.cs_no_dai

    \\ Check Chinroutou (All Terminals)
    JSR check_chinroutou
    BCC cs_no_chi_rt
    LDA yakuman_flags: ORA #&04: STA yakuman_flags
.cs_no_chi_rt

    \\ Check Tsuuiisou (All Honors)
    JSR check_tsuuiisou
    BCC cs_no_tsui
    LDA yakuman_flags: ORA #&08: STA yakuman_flags
.cs_no_tsui

    \\ Check Daisuushii (Big Four Winds)
    JSR check_daisuushii
    BCC cs_no_daiw
    LDA yakuman_flags: ORA #&20: STA yakuman_flags
.cs_no_daiw

    \\ Check Shousuushii (Little Four Winds)
    JSR check_shousuushii
    BCC cs_no_shouw
    LDA yakuman_flags: ORA #&10: STA yakuman_flags
.cs_no_shouw

    \\ If any yakuman detected, set han_count to 13 and skip fu calculation
    LDA yakuman_flags
    BEQ cs_no_yakuman
    LDA #13: STA han_count
    JMP compute_points
.cs_no_yakuman

        JSR calculate_fu
        JSR compute_points
        RTS

\ =============================================
\ YAKU DETECTION
\ =============================================

\ TANYAO: all simples (no terminals/honors)
.check_tanyao
    LDX #0
.ct_loop
    LDA tile_counts, X
    BEQ ct_next
    CPX #0: BEQ ct_fail
    CPX #8: BEQ ct_fail
    CPX #9: BEQ ct_fail
    CPX #17: BEQ ct_fail
    CPX #18: BEQ ct_fail
    CPX #26: BEQ ct_fail
    CPX #27: BCS ct_fail
.ct_next
    INX: CPX #34: BNE ct_loop
    SEC: RTS
.ct_fail
    CLC: RTS

\ YAKUHAI: check pair and open melds for value tiles
.check_yakuhai
    LDX #0
.cy_pair
    LDA tile_counts, X
    CMP #2: BNE cy_pnext
    JSR is_yakuhai_tile
    BCC cy_pnext
    INC han_count
.cy_pnext
    INX: CPX #34: BNE cy_pair

    \ Check open melds
    LDX current_player
    LDA opn_count, X
    BEQ cy_done
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
    BCC cy_onext
    INC han_count
.cy_onext
    LDY tmp: INY
    JMP cy_omlp
.cy_done
    RTS

\ Check if tile X is yakuhai
.is_yakuhai_tile
    TXA: PHA
    CPX #31: BCS iy_yes
    CPX #27: BCC iy_not
    \ Wind tiles 27-30: check seat and round wind
    TXA: SEC: SBC #27
    CMP current_player: BEQ iy_yes
    TXA: CMP round_wind: BEQ iy_yes
.iy_not
    PLA: TAX
    CLC: RTS
.iy_yes
    PLA: TAX
    SEC: RTS

\ TOITOI: all melds are triplets (no sequences)
.check_toitoi
    LDX current_player
    LDA opn_count, X
    BEQ ctt_check

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
    BCS ctt_found
    PLA: TAX: PHA
    LDA tile_counts, X: CLC: ADC #2: STA tile_counts, X
    PLA: TAX
.ctt_next
    INX: CPX #34: BNE ctt_try
    CLC: RTS
.ctt_found
    PLA
    SEC: RTS
.ctt_no
    CLC: RTS

\ COUNT SUITS
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
    BNE csh_yes
    INX: INY: CPY #9: BNE csh_lp
    CLC: RTS
.csh_yes
    SEC: RTS

\ HONITSU: one suit + honors
.check_honitsu
    JSR count_suits
    CMP #1: BNE ch_no
    LDX #27: LDA #0
.ch_hon
    ORA tile_counts, X: INX: CPX #34: BNE ch_hon
    BEQ ch_no
    SEC: RTS
.ch_no
    CLC: RTS

\ CHINITSU: one suit, no honors
.check_chinitsu
    JSR count_suits
    CMP #1: BNE cc_no
    LDX #27: LDA #0
.cc_hon
    ORA tile_counts, X: INX: CPX #34: BNE cc_hon
    BNE cc_no
    SEC: RTS
.cc_no
    CLC: RTS

\ PINFU: closed hand, all sequences, pair not yakuhai
.check_pinfu
    LDA hand_closed: BEQ cp_no
    JSR build_tile_counts
    LDX #0
.cp_pair
    LDA tile_counts, X
    CMP #2: BNE cp_pnext
    JSR is_yakuhai_tile
    BCS cp_no
    LDA #0: STA tile_counts, X
    LDY #0
.cp_trip
    LDA tile_counts, Y
    CMP #3: BCS cp_no
    INY: CPY #34: BNE cp_trip
    SEC: RTS
.cp_pnext
    INX: CPX #34: BNE cp_pair
.cp_no
    CLC: RTS

\ =============================================
\ NEW YAKU DETECTION (7 additional yaku)
\ =============================================

\ IIPPEIKO: two identical sequences (closed only)
\ Check: find a sequence (i, i+1, i+2), then check if the same sequence exists again
.check_iipeiko
    LDA hand_closed: BEQ ci_no
    JSR build_tile_counts
.ci_restart
    LDX #0
.ci_outer
    CPX #27: BCS ci_no
    LDA tile_counts, X
    CMP #2: BCC ci_next
    \ Check for sequence starting at X
    INX: LDA tile_counts, X
    CMP #2: BCC ci_next2
    INX: LDA tile_counts, X
    CMP #2: BCC ci_next3
    \ Found first sequence at X-2, X-1, X
    \ Check for second identical sequence
    TXA: SEC: SBC #2: TAY
    \ Remove first sequence temporarily
    LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    \ Now check if remaining tiles form valid hand (3 melds + 1 pair)
    JSR decompose_melds
    BCS ci_found
    \ Restore first sequence
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

\ RYANPEIKOU: two pairs of identical sequences (closed only)
\ Check: find two pairs of identical sequences, remaining must be exactly one pair
.check_ryanpeikou
    LDA hand_closed: BNE crp_have_closed
    JMP crp_no
.crp_have_closed
    JSR build_tile_counts
    \ Find first pair of identical sequences
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
    \ Found first pair at X-2, X-1, X - save X and remove pair
    STX tmp5
    TXA: SEC: SBC #2: TAY
    LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    \ Find second pair of identical sequences
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
    \ Found second pair at X-2, X-1, X - remove pair
    TXA: SEC: SBC #2: TAY
    LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    INY: LDA tile_counts, Y: SEC: SBC #2: STA tile_counts, Y
    \ Check if remaining is exactly one pair
    JSR check_single_pair
    BCS crp_found
    \ Restore second pair
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
    \ Restore first pair
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


\ Check if tile_counts has exactly one tile with count 2, rest zero
.check_single_pair
    LDX #0
    LDY #0
.crsp_loop
    CPX #34: BCS crsp_done
    LDA tile_counts, X
    BEQ crsp_next
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

\ SANSHOKU: three identical sequences in different suits
\ Check: for each sequence (1-9) in man suit, check if same exists in pin and sou
.check_sanshoku
    JSR build_tile_counts
    LDY #0
.cs_outer
    CPY #9: BCS cs_no
    LDA tile_counts, Y
    BEQ cs_next
    INY: LDA tile_counts, Y
    BEQ cs_next2
    INY: LDA tile_counts, Y
    BEQ cs_next3
    \ Found sequence in man (Y-2, Y-1, Y)
    \ Check pin (Y+7, Y+8, Y+9)
    TYA: CLC: ADC #7: TAX
    LDA tile_counts, X: BEQ cs_no_seq
    INX: LDA tile_counts, X: BEQ cs_no_seq
    INX: LDA tile_counts, X: BEQ cs_no_seq
    \ Check sou (Y+16, Y+17, Y+18)
    TYA: CLC: ADC #16: TAX
    LDA tile_counts, X: BEQ cs_no_seq
    INX: LDA tile_counts, X: BEQ cs_no_seq
    INX: LDA tile_counts, X: BEQ cs_no_seq
    SEC: RTS
.cs_no_seq
    DEY
.cs_next3
    DEY
.cs_next2
    DEY
.cs_next
    INY: JMP cs_outer
.cs_no
    CLC: RTS

\ ITTSU (Straight): sequences 123, 456, 789 in one suit
.check_ittsu
    JSR build_tile_counts
    \ Try man suit (0-8)
    LDX #0: JSR ci_check_straight: BCS ci_yes
    \ Try pin suit (9-17)
    LDX #9: JSR ci_check_straight: BCS ci_yes
    \ Try sou suit (18-26)
    LDX #18: JSR ci_check_straight
.ci_yes
    RTS

\ Helper: check if suit starting at X has 123, 456, 789
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

\ CHANTA: all melds contain terminals/honors, pair is terminal/honor
.check_chanta
    JSR build_tile_counts
    \ Find the pair - must be terminal or honor
    LDX #0
.ct_pair
    LDA tile_counts, X
    CMP #2: BNE ct_pnext
    JSR is_terminal_or_honor
    BCC ct_pnext
    \ Pair is terminal/honor, now check all melds
    \ Temporarily remove pair
    TXA: PHA
    LDA tile_counts, X: SEC: SBC #2: STA tile_counts, X
    PLA: TAX
    \ Check all remaining melds contain terminals/honors
    LDY #0
.ct_mcheck
    CPY #34: BCS ct_mcheck_done
    LDA tile_counts, Y
    BEQ ct_mcheck_next
    JSR is_terminal_or_honor
    BCC ct_mcheck_fail
.ct_mcheck_next
    INY: JMP ct_mcheck
.ct_mcheck_done
    \ Restore pair
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
    INX: CPX #34: BNE ct_pair
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

\ SHOU SANGEN: two dragon triplets + dragon pair (or three dragon triplets)
.check_shousangen
    LDA #0: STA tmp
    JSR build_tile_counts
    \ Check dragons 31(Hatsu), 32(Haku), 33(Chun)
    LDX #31: LDA tile_counts, X: CMP #3: BCS cs_d3
    LDX #32: LDA tile_counts, X: CMP #3: BCS cs_d3
    CLC: RTS
.cs_d3
    \ Count dragon triplets and pairs
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
    \ Need at least 2 dragon groups (triplets or pairs)
    LDA tmp
    CMP #2: BCS cs_ss_yes
    CLC: RTS
.cs_ss_yes
    SEC: RTS

\ CHII TOITSU: seven pairs (2 han)
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
    INX: CPX #34: BNE ct_pair2
    LDA tmp
    CMP #7: BNE ct_no7
    SEC: RTS
.ct_no7
    CLC: RTS


\\ =============================================
\\ NEW YAKU DETECTION (4 additional yaku)
\\ =============================================

\\ SANANKOU: three concealed triplets (2 han)
\\ A concealed triplet is a triplet of tiles held in hand (not from open melds).
\\ We check by finding tiles with count >= 3 in tile_counts.
\\ The pair tile (count 2) must be excluded from the count.
.check_sanankou
    JSR build_tile_counts
    \\ Remove pair from tile_counts
    LDX #0
.csa_find_pair
    LDA tile_counts, X
    CMP #2: BEQ csa_found_pair
    INX: CPX #34: BNE csa_find_pair
    JMP csa_count
.csa_found_pair
    LDA #0: STA tile_counts, X
.csa_count
    \\ Count triplets (concealed = all 3 in hand)
    LDX #0: STX tmp
.csa_loop
    LDA tile_counts, X
    CMP #3: BCC csa_next
    INC tmp
.csa_next
    INX: CPX #34: BNE csa_loop
    \\ Restore the pair to 2 for later use
    LDX #0
.csa_restore
    LDA tile_counts, X: CMP #0: BEQ csa_rnext
    INX: CPX #34: BNE csa_restore
.csa_rnext
    LDA #2: STA tile_counts, X
    \\ Check if we have 3 or more concealed triplets
    LDA tmp
    CMP #3: BCS csa_yes
    CLC: RTS
.csa_yes
    SEC: RTS

\\ HONROUTOU: all terminals and honors (2 han)
\\ Every tile in the hand must be a terminal (1 or 9 of any suit) or honor tile
.check_honroutou
    JSR build_tile_counts
    LDX #0
.chr_loop
    LDA tile_counts, X
    BEQ chr_next
    TXA: JSR is_terminal_or_honor_a
    BCC chr_fail
.chr_next
    INX: CPX #34: BNE chr_loop
    SEC: RTS
.chr_fail
    CLC: RTS

\\ Helper: is tile value in A terminal or honor? Returns C set if yes.
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

\\ SANSHOKU DOUKOU: same triplets across all 3 suits (2 han)
\\ For each number 1-9, check if there's a triplet in all 3 suits (man, pin, sou)
.check_sanshoku_doukou
    JSR build_tile_counts
    LDY #0
.csd_outer
    CPY #9: BCS csd_no
    \\ Check man (Y), pin (Y+9), sou (Y+18)
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


\\ =============================================
\\ YAKUMAN DETECTION
\\ =============================================

\\ SUUKANTSU: four kans (13 han yakuman)
\\ Check if current player has declared 4 kans
.check_suukantsu
    LDX current_player
    LDA player_kans, X
    CMP #4
    BCS csu_yes
    CLC
    RTS
.csu_yes
    SEC
    RTS

\\ Daisangen: big three dragons (13 han yakuman)
\\ All three dragon triplets (Hatsu=31, Haku=32, Chun=33) must exist
\\ Checks both hand tiles and open melds
.check_daisangen
    JSR build_tile_counts
    \ Add open meld dragon tiles to counts
    LDX current_player
    LDA opn_count, X
    BEQ cd_check_hand
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
    \ Check if it's a dragon tile
    CMP #31: BCC cd_open_next
    CMP #34: BCS cd_open_next
    \ It's a dragon - add 3 to count (triplet in open meld)
    TAX
    LDA tile_counts, X: CLC: ADC #3: STA tile_counts, X
.cd_open_next
    LDY tmp: INY
    JMP cd_open_lp
.cd_check_hand
    \ Check all three dragons have count >= 3
    LDX #31
    LDA tile_counts, X
    CMP #3
    BCC cd_no
    LDX #32
    LDA tile_counts, X
    CMP #3
    BCC cd_no
    LDX #33
    LDA tile_counts, X
    CMP #3
    BCC cd_no
    SEC
    RTS
.cd_no
    CLC
    RTS

\\ Chinroutou: all terminals (13 han yakuman)
\\ Every tile must be a terminal (1 or 9 of any suit)
\\ No honor tiles or simple tiles allowed
.check_chinroutou
    JSR build_tile_counts
    LDX #0
.ccr_loop
    LDA tile_counts, X
    BEQ ccr_next
    \\ Check if tile is a terminal (0, 8, 9, 17, 18, 26)
    CPX #0: BEQ ccr_next
    CPX #8: BEQ ccr_next
    CPX #9: BEQ ccr_next
    CPX #17: BEQ ccr_next
    CPX #18: BEQ ccr_next
    CPX #26: BEQ ccr_next
    \\ Not a terminal - fail
    CLC
    RTS
.ccr_next
    INX
    CPX #34
    BNE ccr_loop
    SEC
    RTS

\\ Tsuuiisou: all honors (13 han yakuman)
\\ Every tile must be an honor tile (values 27-33)
\\ No suit tiles allowed
.check_tsuuiisou
    JSR build_tile_counts
    LDX #0
.ctu_loop
    LDA tile_counts, X
    BEQ ctu_next
    \\ Check if tile is an honor (27-33)
    CPX #27
    BCS ctu_next
    \\ Not an honor - fail
    CLC
    RTS
.ctu_next
    INX
    CPX #34
    BNE ctu_loop
    SEC
    RTS

\\ Daisuushii: big four winds (13 han yakuman)
\\ All four wind triplets (East=27, South=28, West=29, North=30)
\\ Checks both hand tiles and open melds
.check_daisuushii
    JSR build_tile_counts
    \\ Add open meld wind tiles to counts
    LDX current_player
    LDA opn_count, X
    BEQ cds_check_hand
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
    \\ Check if it's a wind tile (27-30)
    CMP #27: BCC cds_open_next
    CMP #31: BCS cds_open_next
    \\ It's a wind - add 3 to count (triplet in open meld)
    TAX
    LDA tile_counts, X: CLC: ADC #3: STA tile_counts, X
.cds_open_next
    LDY tmp: INY
    JMP cds_open_lp
.cds_check_hand
    \\ Check all four winds have count >= 3
    LDX #27
    LDA tile_counts, X
    CMP #3
    BCC cds_no
    LDX #28
    LDA tile_counts, X
    CMP #3
    BCC cds_no
    LDX #29
    LDA tile_counts, X
    CMP #3
    BCC cds_no
    LDX #30
    LDA tile_counts, X
    CMP #3
    BCC cds_no
    SEC
    RTS
.cds_no
    CLC
    RTS

\\ Shousuushii: little four winds (13 han yakuman)
\\ Three wind triplets + one wind pair
\\ Checks both hand tiles and open melds
.check_shousuushii
    JSR build_tile_counts
    \\ Add open meld wind tiles to counts
    LDX current_player
    LDA opn_count, X
    BEQ csss_check_hand
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
    \\ Check if it's a wind tile (27-30)
    CMP #27: BCC csss_open_next
    CMP #31: BCS csss_open_next
    \\ It's a wind - add 3 to count (triplet in open meld)
    TAX
    LDA tile_counts, X: CLC: ADC #3: STA tile_counts, X
.csss_open_next
    LDY tmp: INY
    JMP csss_open_lp
.csss_check_hand
    \\ Count wind triplets and wind pairs
    LDX #27
    LDA #0: STA tmp8  \\ triplet count
    LDA #0: STA tmp9  \\ pair count
    LDX #27
.csss_count_lp
    LDA tile_counts, X
    CMP #3
    BCC csss_not_triplet
    \\ Count as triplet
    INC tmp8
    JMP csss_next_tile
.csss_not_triplet
    CMP #2
    BCC csss_next_tile
    \\ Count as pair
    INC tmp9
.csss_next_tile
    INX
    CPX #31
    BNE csss_count_lp
    \\ Need exactly 3 triplets and 1 pair
    LDA tmp8
    CMP #3
    BNE csss_no
    LDA tmp9
    CMP #1
    BNE csss_no
    SEC
    RTS
.csss_no
    CLC
    RTS


\\ =============================================
\\ FU CALCULATION
\\ =============================================

.calculate_fu
    LDA #30: STA fu_count

    LDX #0
.cf_pair
    LDA tile_counts, X
    CMP #2: BNE cf_pnext
    JSR is_yakuhai_tile
    BCC cf_pnext
    LDA fu_count: CLC: ADC #2: STA fu_count
    JMP cf_melds
.cf_pnext
    INX: CPX #34: BNE cf_pair

.cf_melds
    LDX current_player
    LDA opn_count, X
    BEQ cf_closed

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
    BCC cf_open_s
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
    BCC cf_csimp
    LDA fu_count: CLC: ADC #8: STA fu_count
    JMP cf_cnext
.cf_csimp
    LDA fu_count: CLC: ADC #4: STA fu_count
.cf_cnext
    INX: CPX #34: BNE cf_clp

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

\ Check if tile A is terminal or honor
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

\ =============================================
\ SCORE FORMULA
\ =============================================

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
    BNE cp_limit_chk
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

\ =============================================
\ WIN DETECTION (Tsumo/Ron)
\ =============================================

.check_tsumo
    JSR check_win
    BCS cts_win
    CLC: RTS
.cts_win
    LDA #1: STA tsumo_flag
    LDA #0: STA ron_flag
    SEC: RTS

.check_ron
    LDX #0
.cr_loop
    CPX disc_tile_player: BEQ cr_next
    STX tmp5
    JSR count_tiles_for_player
    LDY disc_tile_val
    LDA tile_counts, Y: CLC: ADC #1: STA tile_counts, Y
    JSR check_win_no_rebuild
    BCS cr_found
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
    BCS cwnr_win
    PLA: TAX: PHA
    LDA tile_counts, X: CLC: ADC #2: STA tile_counts, X
    PLA: TAX
.cwnr_next
    INX: CPX #34: BNE cwnr_try
    CLC: RTS
.cwnr_win
    PLA
    SEC: RTS

\ =============================================
\ SCORE DISPLAY
\ =============================================

.display_score_result
    LDA #12: JSR oswrch

    LDA tsumo_flag: BEQ dsr_ron
    LDY #0
.dsr_tmsg
    LDA tsumo_msg, Y: BEQ dsr_tmsg_dn
    JSR oswrch: INY: JMP dsr_tmsg
.dsr_tmsg_dn
    JMP dsr_yaku
.dsr_ron
    LDY #0
.dsr_rmsg
    LDA ron_msg, Y: BEQ dsr_rmsg_dn
    JSR oswrch: INY: JMP dsr_rmsg
.dsr_rmsg_dn

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

    \ --- Display yaku_flags2 yaku ---
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

    \\ --- Display yaku_flags3 yaku ---

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

    \\ Check if this is a yakuman hand
    LDA yakuman_flags
    BEQ dsr_norm
    JMP dsr_normal_han
.dsr_norm

    \\ Display yakuman type
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

    \\ Display YAKUMAN label
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
    LDA han_count: CLC: ADC #'0': JSR oswrch
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
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    RTS

\ =============================================
\ POINT AWARDING
\ =============================================

.award_tsumo
    LDX #0
.at_lp
    CPX current_player: BEQ at_skip
    STX tmp5
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
    BCC at_nornd
    INC tmp2
.at_nornd
    LDA honba: BEQ at_hb_done
    STA tmp4
    LDA #0
.at_hb
    CLC: ADC #100: DEC tmp4: BNE at_hb
    CLC: ADC tmp3: STA tmp3
    BCC at_hb_done
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
    ASL A: ASL A  \ *4 = *300 approx (close enough for now)
    CLC: ADC tmp3: STA tmp3
    BCC ar_hb_done
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

\ =============================================
\ NEW ROUND
\ =============================================

.new_round
    \ Advance the round (update dealer, check game end)
    JSR advance_round
    BCS nr_game_over
    \ Clear keyboard buffer and wait for user to see score
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    \ Rebuild wall
    JSR wall_build
    JSR wall_shuffle
    JSR deal_all
    \ Reveal initial dora indicator from dead wall
    LDA wall+DORA_START
    STA dora_indicator
    LDA #0: STA dora_count
    \ Start with the dealer
    LDX dealer: STX current_player
    LDA #0: STA skip_draw
    LDA #0: STA tsumo_flag: STA ron_flag
    LDX #0
.nr_ip
    STA ippatsu_flags, X
    STA furiten_flags, X
    INX: CPX #NUM_PLAYERS: BNE nr_ip
    \\ Reset per-player kans count
    LDX #0
.nr_kans
    STA player_kans, X
    INX: CPX #NUM_PLAYERS: BNE nr_kans
    \\ Reset yakuman flags
    STA yakuman_flags
    CLC: RTS
.nr_game_over
    SEC: RTS

\ =============================================
\ OPEN MELDS DISPLAY
\ =============================================
\ Display open melds for a player compactly.
\ X = player number. Prints nothing if no melds.
\ Format: " Open:P5m K7s A3p"
\ Meld type: P=pon, K=closed kan, A=added kan

.disp_open_melds
    LDA opn_count, X
    BEQ dom_done

    \ Save player number
    TXA: PHA

    \ Calculate base offset into opn_melds: player * 20
    TXA: ASL A: ASL A          \ * 4
    STA tmp4
    TXA: ASL A: ASL A: ASL A: ASL A \ * 16
    CLC: ADC tmp4              \ = * 20
    STA tmp4                   \ tmp4 = base offset

    \ Print " Open:" label
    LDA #' ': JSR oswrch
    LDA #'O': JSR oswrch
    LDA #'p': JSR oswrch
    LDA #':': JSR oswrch

    \ Get meld count and start loop
    PLA: TAX                   \ restore player number
    LDA opn_count, X
    TAY: DEY                   \ Y = last meld index

.dom_loop
    \ Calculate meld offset: tmp4 + Y * 5
    STY tmp5                   \ save meld index
    LDA tmp5
    ASL A: ASL A               \ * 4
    CLC: ADC tmp5              \ * 5
    CLC: ADC tmp4              \ + base offset
    TAX                        \ X = offset into opn_melds

    \ Print type letter
    LDA opn_melds, X
    CMP #3: BEQ dom_kan
    CMP #4: BEQ dom_ak
    LDA #'P': JSR oswrch       \ type 1 = pon
    JMP dom_tiles
.dom_kan
    LDA #'K': JSR oswrch       \ type 3 = closed kan
    JMP dom_tiles
.dom_ak
    LDA #'A': JSR oswrch       \ type 4 = added kan

.dom_tiles
    \ Print first tile in 2-char format
    INX
    LDA opn_melds, X
    PHA
    JSR tile_num_char: JSR oswrch
    PLA
    JSR tile_suit_char: JSR oswrch

    \ Space between melds
    LDA #' ': JSR oswrch

    \ Next meld
    LDY tmp5
    CPY #0
    BNE dom_loop

.dom_done
    RTS

\\\\ =============================================
\\\\ ABORTIVE DRAWS
\\\\ =============================================
\\\\ Check for abortive draw conditions after each discard.
\\\\ Returns: C set = abortive draw, C clear = normal play.
\\\\ When abortive draw detected, displays message and handles draw resolution.

\\\\ Check Four Winds (Suu Fon Round)
\\\\ All 4 players discard wind tiles on the first turn (turn 1)
.check_four_winds
    \\ Only check after 4 players have each discarded once
    LDA num_discards
    CMP #1
    BNE cfw_no
    LDA num_discards+1
    CMP #1
    BNE cfw_no
    LDA num_discards+2
    CMP #1
    BNE cfw_no
    LDA num_discards+3
    CMP #1
    BNE cfw_no
    \\ All players have 1 discard - check if all are winds
    \\ Player 0 first discard at disc_bases+0
    LDA disc_bases
    CMP #27
    BCC cfw_no
    CMP #31
    BCS cfw_no
    \\ Player 1 first discard at disc_bases+2 -> discards+MAX_DISC
    LDA disc_bases+2
    CMP #27
    BCC cfw_no
    CMP #31
    BCS cfw_no
    \\ Player 2 first discard at disc_bases+4 -> discards+MAX_DISC*2
    LDA disc_bases+4
    CMP #27
    BCC cfw_no
    CMP #31
    BCS cfw_no
    \\ Player 3 first discard at disc_bases+6 -> discards+MAX_DISC*3
    LDA disc_bases+6
    CMP #27
    BCC cfw_no
    CMP #31
    BCS cfw_no
    \\ All 4 first discards are winds!
    JSR game_display
    LDY #0
.cfw_msg_lp
    LDA abortive_four_winds_str, Y
    BEQ cfw_msg_dn
    JSR oswrch: INY
    JMP cfw_msg_lp
.cfw_msg_dn
    JSR osnewl
    SEC
    RTS
.cfw_no
    CLC
    RTS

\\\\ Check Four Kans (Suu Kan)
\\\\ When 4 kans have been declared total by all players
.check_four_kans
    LDA four_kans_count
    CMP #4
    BCC cfk_no
    JSR game_display
    LDY #0
.cfk_msg_lp
    LDA abortive_four_kans_str, Y
    BEQ cfk_msg_dn
    JSR oswrch: INY
    JMP cfk_msg_lp
.cfk_msg_dn
    JSR osnewl
    SEC
    RTS
.cfk_no
    CLC
    RTS

\\\\ Check Triple Ron (San Kan Ron)
\\\\ Two or more players can win on the same discard
\\\\ Returns C set if multiple ron claims detected
.check_triple_ron
    LDA ron_flag: PHA
    LDA ron_player: PHA
    \\ First, do a normal ron check
    JSR check_ron
    BCC ctr_no_ron
    \\ One ron found - check for more
    LDA ron_player: STA tmp5
    LDX ron_player: INX
.ctr_loop
    CPX disc_tile_player: BEQ ctr_next
    STX tmp6
    JSR count_tiles_for_player
    LDY disc_tile_val
    LDA tile_counts, Y: CLC: ADC #1: STA tile_counts, Y
    JSR check_win_no_rebuild
    BCS ctr_second_found
    LDY disc_tile_val
    LDA tile_counts, Y: SEC: SBC #1: STA tile_counts, Y
.ctr_next
    LDX tmp6: INX
    CPX #NUM_PLAYERS: BNE ctr_loop
    \\ Only one ron found - not triple ron
    PLA: STA ron_player
    PLA: STA ron_flag
    CLC
    RTS
.ctr_second_found
    \\ Two rons found = abortive draw
    PLA: STA ron_player
    PLA: STA ron_flag
    JSR game_display
    LDY #0
.ctr_msg_lp
    LDA abortive_triple_ron_str, Y
    BEQ ctr_msg_dn
    JSR oswrch: INY
    JMP ctr_msg_lp
.ctr_msg_dn
    JSR osnewl
    SEC
    RTS
.ctr_no_ron
    PLA: STA ron_player
    PLA: STA ron_flag
    CLC
    RTS

\\\\ Check Nine Gates (Kyuu Shuu Kyuu Hai)
\\\\ Pattern: 1-1-1-2-3-4-5-6-7-8-9-9-9 of one suit + 14th tile
\\\\ Only for closed hands with 14 tiles
.check_nine_gates
    LDX current_player
    LDA num_tiles, X
    CMP #14
    BNE cng_no
    \\ Check if hand is closed (no open melds)
    LDA opn_count, X
    BNE cng_no
    \\ Build tile counts
    JSR build_tile_counts
    \\ Check each suit: Man(0-8), Pin(9-17), Sou(18-26)
    LDX #0
.cng_suit_lp
    STX tmp5
    JSR cng_check_suit
    BCS cng_found
    LDX tmp5
    INX
    CPX #3
    BNE cng_suit_lp
    CLC
    RTS
.cng_found
    SEC
    RTS
.cng_no
    CLC
    RTS

\\\\ Check if a specific suit matches the 9-gate pattern
\\\\ X = suit index (0=Man, 1=Pin, 2=Sou)
\\\\ Returns C set if pattern matches
.cng_check_suit
    TXA
    ASL A: ASL A: ASL A: ASL A
    TAX
    \\ X = base tile value for suit (0, 9, or 18)
    LDY #0
    STY tmp6
    \\ Check tile X+0 (1) has at least 3
    LDA tile_counts, X
    CMP #3
    BCC cng_no_match
    CLC: ADC tmp6: STA tmp6
    \\ Check tiles X+1 through X+8 have at least 1 each
    INX
.cng_mid_lp
    LDA tile_counts, X
    BEQ cng_no_match
    CLC: ADC tmp6: STA tmp6
    INX
    CPX #9
    BCC cng_mid_lp
    \\ Now X is at X+9 (the 9 tile)
    LDA tile_counts, X
    CMP #3
    BCC cng_no_match
    CLC: ADC tmp6: STA tmp6
    \\ Total should be 14
    LDA tmp6
    CMP #14
    BNE cng_no_match
    SEC
    RTS
.cng_no_match
    CLC
    RTS

\\\\ =============================================
\\\\ DISPLAY ROUTINES FOR ABORTIVE DRAWS
\\\\ =============================================

\\\\ Display abortive draw message and handle draw resolution
\\\\ This is called when any abortive draw condition is detected
.display_abortive_draw
    \\ The message was already displayed by the check routine
    \\ Now handle the draw resolution
    INC honba: INC hands_played
    LDA hands_played
    CMP #8
    BCC dad_new
    SEC: RTS
.dad_new
    JSR new_round
    RTS

\\\\ Display nine gates win message
.display_nine_gates
    LDY #0
.dng_lp
    LDA abortive_nine_gates_str, Y
    BEQ dng_dn
    JSR oswrch: INY
    JMP dng_lp
.dng_dn
    JSR osnewl
    RTS

\\ =============================================
\\ CHOMBO - PENALTY SYSTEM
\\ =============================================
\\ Detects illegal plays and applies penalties.
\\ Violations: illegal riichi, illegal discard, illegal win declaration
\\ Penalty: 8000 pts (12000 for dealer)

\\ Apply chombo penalty to a player
\\ X = player number
\\ Deducts 8000 pts (dealer pays 12000)
.apply_chombo
    TXA: PHA
    INC chombo_count, X
    \\ Calculate penalty: 8000 (non-dealer) or 12000 (dealer)
    CPX dealer: BNE apc_non_dealer
    \\ Dealer penalty: 12000 = &2EE0
    TXA: ASL A: TAY
    LDA player_points, Y: SEC: SBC #<12000
    STA player_points, Y
    LDA player_points+1, Y: SBC #>12000
    STA player_points+1, Y
    JMP apc_check_underflow
.apc_non_dealer
    \\ Non-dealer penalty: 8000 = &1F40
    TXA: ASL A: TAY
    LDA player_points, Y: SEC: SBC #<8000
    STA player_points, Y
    LDA player_points+1, Y: SBC #>8000
    STA player_points+1, Y
.apc_check_underflow
    \\ If points went negative, set to 0
    LDA player_points+1, Y: BPL apc_done
    LDA #0: STA player_points, Y: STA player_points+1, Y
.apc_done
    \\ Display chombo message
    JSR game_display
    LDY #0
.apc_msg
    LDA chombo_str, Y: BEQ apc_msg_dn
    JSR oswrch: INY: JMP apc_msg
.apc_msg_dn
    JSR osnewl
    \\ Show who pays
    PLA: TAX
    TXA: CLC: ADC #'1'
    JSR oswrch
    LDY #0
.apc_pay
    LDA chombo_pay_str, Y: BEQ apc_pay_dn
    JSR oswrch: INY: JMP apc_pay
.apc_pay_dn
    \\ Show penalty amount
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
    \\ Wait for keypress
    LDA #&0F: LDX #0: LDY #0: JSR osbyte
    JSR osrdch
    RTS

\\ Display chombo counts in scoreboard
.disp_chombo
    LDX #0
.dch_lp
    CPX #NUM_PLAYERS: BCS dch_done
    LDA chombo_count, X: BEQ dch_next
    \\ Show "C" marker if player has chombo
    TXA: CLC: ADC #'1'
    JSR oswrch
    LDA #'C': JSR oswrch
    LDA #' ': JSR oswrch
.dch_next
    INX: JMP dch_lp
.dch_done
    RTS

\\\\\\\\\\\\\\\\ =============================================
\\\\\\\\\\\\\\\\ DATA
\\\\\\\\ =============================================

.title_str
    EQUS "RIICHI MAHJONG", 0

.hand_hdr_str
    EQUS "Your Hand", 0

.my_disc_str
    EQUS "Your Disc", 0

.inst_str
    EQUS "1-9,0,A-D discard Q quit", 0

.game_over_str
    EQUS "GAME OVER", 0

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
    EQUS "Pon? (Y/N)", 0

.chii_ask_str
    EQUS "Chii? (Y/N)", 0

.kan_ask_str
    EQUS "Kan? (Y/N)", 0

.press_key_str
    EQUS "Press any key...", 0
.furiten_msg
    EQUS "FURITEN!", 0

.drawn_str
    \ EQUS "DRAW - Wall Exhausted", 0

    .diff_title
        EQUS "RIICHI MAHJONG - Select Difficulty", 0
    .diff_novice
        EQUS "1: Novice    - Simple AI, always calls", 0
    .diff_inter
        EQUS "2: Intermediate - Smarter AI, selective calls", 0
    .diff_expert
        EQUS "3: Expert    - Strategic AI, defensive play", 0
    .diff_prompt
        EQUS "Press 1, 2, or 3:", 0
.winner_str
    EQUS "Winner: Player ", 0
.east_str
    EQUS "East", 0
.south_str
    EQUS "South", 0
.seat_wind_chrs
    EQUS "ESWN"

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

\\ Open melds storage
\\ 4 players x 4 melds x 5 bytes = 80 bytes
\\ Each meld: type(1=pon,2=kan), tile1, tile2, tile3, tile4
.opn_melds
    FOR I, 0, (MAX_OPEN_MELDS * MELD_SIZE * NUM_PLAYERS)-1
    EQUB 0
    NEXT

\\ Number of open melds per player
.opn_count
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0
    NEXT

\\ Scoring variables
.yaku_flags EQUB 0
.yaku_flags2 EQUB 0
.yaku_flags3 EQUB 0
.yakuman_flags EQUB 0
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

\\ AI difficulty level (0=novice, 1=intermediate, 2=expert)
.ai_difficulty EQUB 0

\\ Match structure
.dealer EQUB 0          \\ current dealer player index (0-3)
.hands_played EQUB 0   \\ total hands played this game
.seat_winds
    FOR I, 0, NUM_PLAYERS-1
    EQUB 27             \\ seat wind for each player (27=East initially)
    NEXT

\\\\ Abortive draw tracking
.first_disc_winds
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0               \\ first discard is wind for this player?
    NEXT
.four_kans_count EQUB 0  \\ total kans declared this hand

\\ Per-player kans count (for Suukantsu detection)
.player_kans
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0
    NEXT

\\ Chombo penalty tracking
.chombo_count
    FOR I, 0, NUM_PLAYERS-1
    EQUB 0               \\ chombo penalties per player
    NEXT

.abortive_four_winds_str
    EQUS "ABORTIVE DRAW - Four Winds!", 0
.abortive_four_kans_str
    EQUS "ABORTIVE DRAW - Four Kans!", 0
.abortive_triple_ron_str
    EQUS "ABORTIVE DRAW - Triple Ron!", 0
.abortive_nine_gates_str
    EQUS "NINE GATES WIN!", 0
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

\\ Yaku display strings (new yaku)
.yaku_mt_str
    EQUS "MENZEN TSUMO 1 han", 0
.yaku_sa_str
    EQUS "SANANKOU 2 han", 0
.yaku_hr_str
    EQUS "HONROUTOU 2 han", 0
.yaku_sd_str
    EQUS "SANSHOKU DOUKOU 2 han", 0

\\ Yakuman display strings
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

.end
SAVE "MAHJONG", start, end, start