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
    BNE ml_skip_draw

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
    BCS ml_got_tile
    JSR check_added_kan
    BCS ml_got_tile
    \ Check riichi for human player
    LDX current_player
    CPX #0
    BNE ml_got_tile
    JSR check_riichi_human
    BCC ml_got_tile
    \ Riichi declared - auto-discard drawn tile (last in hand)
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
    JSR check_ron
    BCC ml_not_ron
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
    JSR check_ron
    BCC ml_not_ron_h
    JMP ml_ron
.ml_not_ron_h
    JSR check_open_calls
    BCS ml_call_made_h
    JSR advance_player
    JMP mainloop

.ml_call_made_h
    JSR game_display
    JMP mainloop

.ml_tsumo
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
    LDX ron_player: STX current_player
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

\ =============================================
\ ADVANCE ROUND
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
\ Conditions: closed hand (no open melds), 1000+ points, not already declared.
\ If eligible, prompts Y/N and deducts 1000 points + places riichi stick.
\ Returns: C set = riichi declared, C clear = no riichi.

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
    LDA #$FF: STA tmp
    LDA #0: STA tmp2
    LDA #0: STA tmp3

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
    \ Set skip_draw
    LDA #1
    STA skip_draw
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
    JSR osnewl: JSR osnewl

    \ AI discards (players 1-3)
    LDX #1
.gd_disc_lp
    CPX #NUM_PLAYERS: BCS gd_disc_dn
    STX tmp7
    LDA #'P': JSR oswrch
    TXA: CLC: ADC #'1'
    JSR oswrch
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
    STA han_count: STA fu_count: STA yaku_flags
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
\ FU CALCULATION
\ =============================================

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

    JSR osnewl

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
    CLC: RTS
.nr_game_over
    SEC: RTS

\ =============================================
\ DATA
\ =============================================

.title_str
    EQUS "RIICHI MAHJONG", 0

.hand_hdr_str
    EQUS "Your Hand:", 0

.my_disc_str
    EQUS "Your Disc:", 0

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
    EQUS "DRAW - Wall Exhausted", 0
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

\\ Match structure
.dealer EQUB 0          \\ current dealer player index (0-3)
.hands_played EQUB 0   \\ total hands played this game
.seat_winds
    FOR I, 0, NUM_PLAYERS-1
    EQUB 27             \\ seat wind for each player (27=East initially)
    NEXT

.end

SAVE "MAHJONG", start, end, start