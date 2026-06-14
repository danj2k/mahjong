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
    LDA skip_draw
    BNE ml_skip_draw

    JSR player_draw
    BCS game_over
    JMP ml_got_tile

.ml_skip_draw
    LDA #0: STA skip_draw

.ml_got_tile
    LDX current_player
    CPX #0
    BEQ ml_human

    \ AI turn
    JSR sort_hand
    JSR ai_choose_discard
    JSR player_discard
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
    JSR check_open_calls
    BCS ml_call_made_h
    JSR advance_player
    JMP mainloop

.ml_call_made_h
    JSR game_display
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
    RTS
.quit
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
\ GAME INITIALIZATION
\ =============================================

.game_init
    JSR wall_build
    JSR wall_shuffle
    JSR deal_all
    LDA #0: STA current_player
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
    CPX #TOTAL_TILES: BCS pd_fail
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
    JSR execute_chii
    SEC: RTS

.soc_try_kan
    LDY disc_tile_val
    LDA tile_counts, Y
    CMP #3
    BCC soc_skip
    JSR execute_kan
    SEC: RTS

.soc_skip
    LDX tmp5
    INX
    CPX #NUM_PLAYERS
    BNE soc_lp
    CLC
    RTS

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
    LDA #' ': JSR oswrch
.dpl_honba
    LDX tmp5
    INX
    CPX #NUM_PLAYERS
    BNE dpl_lp
    \ Print honba count
    LDA #' ': JSR oswrch
    LDA #'H': JSR oswrch
    LDA #':': JSR oswrch
    LDA honba
    CLC: ADC #'0'
    JSR oswrch
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

.end

SAVE "MAHJONG", start, end, start
