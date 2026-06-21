# Development Log

This log records significant changes, discoveries, and problems solved during development.

## AI Outer Loop Bug (Most Critical)

**Problem:** CPU players never won hands. Debug counters showed 70+ tsumo checks and 70+ ron checks with 0 wins across multiple games.

**Root cause:** In `ai_choose_discard`, the outer loop had an unconditional `JMP ai_done` where a conditional `BNE` was needed:
```asm
; BEFORE (broken):
CPY tmp7: JMP ai_done   ; always jumps — loop runs ONCE

; AFTER (fixed):
CPY tmp7: BNE ai_outer_go
JMP ai_done              ; only jumps when Y == tmp7
```

**Impact:** The AI only ever evaluated the first tile in its hand and immediately discarded it, regardless of quality. This is why CPU players "hardly got any melds" and nobody won.

**Discovery method:** Code review by Claude identified the `CPY tmp7: JMP ai_done` pattern as an unconditional branch after a comparison — the classic "compare then always jump" bug.

## sort_hand X Register Clobbering

**Problem:** Discards showed wrong tiles (e.g. 8s displayed as Hg), wall corruption detected, 5 melds displayed for a single player.

**Root cause:** `sort_hand` takes the player number in the X register. After `check_win`, X was left at 34 (TILE_TYPES). With X=34, `sort_hand` called `set_hand_ptr(34)` which read garbage from `hand_bases + 68` (past the 8-byte table), producing a random 16-bit pointer. The bubble sort then wrote to random memory addresses, corrupting hands, discards, wall arrays, and open meld data.

**Fix:** Added `LDX current_player` before every `JSR sort_hand` call in the main game loop (5 call sites). The `deal_all` routine was already correct — it explicitly sets X in its loop.

**Discovery method:** Debug counters and memory dumps showed wall corruption patterns. The sort_hand fix was implemented before the AI outer loop fix, but the AI bug meant hands were never being built properly anyway.

## PRNG Period Bug

**Problem:** The same hand and the same four-kans abortive draw appeared repeatedly.

**Root cause:** An xorshift PRNG with shifts (1,1) had a period of only 15 (not 255 as the comment claimed). With 136 tiles in the wall and ~250 rng calls per shuffle, wall shuffles repeated every 4 hands.

**Fix:** Replaced with an LCG (`seed * 5 + 7 mod 256`) which has a full period of 256 (verified via Hull-Dobell criteria). The seed is initialised from the hardware System VIA timer at startup.

## Closed Kan Meld Offset

**Problem:** CPU players showed 5 melds (impossible — max 4).

**Root cause:** `execute_closed_kan` computed `opn_count * 4` to calculate the offset into `opn_melds`, but each meld entry is 5 bytes. The other execute routines correctly used `opn_count * 5`.

**Fix:** Changed the calculation to use `opn_count * 5`, matching the other execute routines.

## Wall Count Display

**Problem:** Wall count showed "<2" instead of a proper number.

**Root cause:** The 2-digit display loop divided by 10 to extract tens and units. When the wall count exceeded 99 (e.g. if `wall_pos` was corrupted to 0, giving a count of 122), the tens digit became 12, and `12 + '0'` = ASCII 60 = `<`.

**Fix:** Added a hundreds digit to the display loop, with leading zero suppression.

## Chombo Message Formatting

**Problem:** "CHOMBO - PENALTY!" was printed on the same line as the dora/wall/dealer status line, causing it to wrap to the next line.

**Root cause:** `apply_chombo` called `game_display` then immediately printed the penalty string via OSWRCH with no `osnewl` in between.

**Fix:** Added `JSR osnewl` before the penalty string print.

## Drawn String Data Bug

**Problem:** Wall exhaustion displayed "RIICHI MAHJONG - Select Difficulty" instead of "DRAW - Wall Exhausted".

**Root cause:** The `drawn_str` label had its EQUS data commented out (`; EQUS "DRAW - Wall Exhausted", 0`). The label fell through to the next string in memory — `diff_title`.

**Fix:** Uncommented the EQUS so `drawn_str` has its own data.

## Player 4 Riichi Indicator

**Problem:** Player 4's riichi indicator (R) never appeared on the score line.

**Root cause:** In `disp_points_line`, the indicator check code was skipped for the last player due to a `CMP #NUM_PLAYERS-1: BEQ dpl_done` that jumped past the indicator logic.

**Fix:** Removed the early exit so all 4 players get their indicator check.

## Novice AI Riichi (Inverted Logic)

**Problem:** Novice AI declared riichi (should never do so).

**Root cause:** The code at `check_riichi_ai` had the novice check backwards — when `ai_difficulty = 0` (novice), it jumped to `cra_enough` which declared riichi, instead of `cra_no` which skips it.

**Fix:** Changed the branch target from `cra_enough` to `cra_no`.

## Splash Screen Tile Display

**Problem:** The title screen text was not centred below the Red Dragon tile graphic.

**Fix:** Added a `draw_tile_image` routine that positions each row of the tile graphic using `VDU 31,x,y` to centre it on screen. The tile data uses MODE 7 teletext graphic bytes from a BBC BASIC program.

## Multiple Kans Prompt Stacking

**Problem:** When multiple kans were available, each prompt appeared below the previous one, cluttering the screen.

**Fix:** Added `clear_prompt_line` which positions at row 24, clears 39 spaces (not 40 — 40 would cause Mode 7 scrolling), then repositions. All prompt routines now use this instead of `osnewl`, so each prompt overwrites the previous one.

## Sanshoku Infinite Loop

**Problem:** CPU player stuck in infinite loop, game froze. BeebEm debugger showed the CPU cycling endlessly between addresses 0x4E01 and 0x4E48.

**Root cause:** In `check_sanshoku` (SANSHOKU — three identical sequences in different suits), when the cross-suit sequence check failed (pin or sou tiles not found), the code fell through to `cs_no_seq` which did `DEY DEY DEY INY` — a net change of -2. Combined with the 2 INYs that advanced Y to check the sequence, Y always returned to its starting value. For example, with Y starting at 3: advanced to 5, failed check, DEY→4, DEY→3, DEY→2, INY→3 — same as before. Infinite loop.

**Fix:** Changed all 6 `BEQ cs_no_seq` instructions (in both pin and sou checks) to `BEQ cs_next3`. The `cs_next3` path does `DEY DEY INY` (net -1 from the advanced position), correctly advancing Y to the next starting position. Removed the `cs_no_seq` label and its extra DEY.

**Discovery method:** User manually broke into BeebEm debugger when game froze, single-stepped through the code, and shared the trace showing the repeating Y=3→5→3 cycle.

## Ron Win Detection Rejected by Chombo Check

**Problem:** `dbg_ron_wins` showed 1 but no winner screen appeared — the game showed "Wall Exhausted" instead.

**Root cause:** `check_chombo_win` is called after both Tsumo and Ron detections to verify the win is valid. It calls `check_win`, which rebuilds `tile_counts` from the hand array via `build_tile_counts`. For Tsumo, the drawn tile IS in the hand, so the rebuild works correctly. For Ron, the discarded tile is NOT in the hand — it's in the discard pile — so `check_win` finds no win and `check_chombo_win` returns carry set (invalid win = chombo). The ron win was detected correctly by `check_ron`, then immediately rejected by `check_chombo_win`.

**Fix (first attempt — 753e848):** `check_chombo_win` now checks `tsumo_flag`. For Tsumo, it calls `check_win` directly (drawn tile is in hand). For Ron, it temporarily adds `disc_tile_val` to `tile_counts` before calling `check_win_no_rebuild`, then restores tile_counts afterwards.

**Fix (carry flag — e875c5d):** The first attempt had a second bug: the carry flag from `check_win_no_rebuild` was overwritten by the tile_counts restore (`SEC: SBC #1` always set carry for counts ≥ 2). This inverted the result: valid wins were rejected, invalid hands passed. Fixed by adding PHP before the restore and PLP after, preserving the carry across the restore.

**Discovery method:** BeebEm debugger watches showed `dbg_ron_wins = 1` but no winner screen appeared. Traced the code flow from `check_ron` through `check_chombo_win` to find the rejection. Second bug found by code review of the restored carry flag.

## check_win Seven Pairs Stack Imbalance

**Problem:** If `check_seven_pairs` detected a win, `check_win` jumped to `cw_win` which did `PLA` to clean up the saved X from the pair loop. But the seven pairs path never pushed an X — the PLA popped the return address low byte, corrupting the RTS destination. This would cause erratic behaviour (crash, incorrect return, or silent corruption) whenever a seven-pairs hand was detected.

**Root cause:** Both the pair-loop win path and the seven pairs win path shared the same `cw_win` label:
```asm
; Pair loop pushes X with TXA: PHA before JSR decompose_melds
; cw_win does PLA to clean up — correct for pair loop
; But check_seven_pairs never pushed anything — PLA corrupts return address
```

**Fix:** Split into two labels:
- `cw_win` (PLA + SEC: RTS) — for pair-loop wins, cleans up the pushed X
- `cw_win_nopair` (SEC: RTS) — for seven pairs wins, no stack cleanup needed

**Impact:** Low in practice — seven pairs is a rare winning pattern, so the bug was unlikely to trigger during normal play. But it would cause unpredictable behaviour whenever seven pairs was the winning hand.

## Chii Skip Draw Bug (Hand Inflation)

**Problem:** After making a chii (sequence claim), the calling player received a free extra draw before discarding. With 4 chiis, the hand had 6 tiles instead of the correct 4.

**Root cause:** The `ep_add_chii` routine intentionally did NOT set `skip_draw`:
```asm
; BEFORE (broken):
; Chii is always open - allow normal draw (don't set skip_draw)
RTS

; AFTER (fixed):
; After chii, player must discard without drawing
LDA #1
STA skip_draw
RTS
```

In Mahjong, after ANY open call (pon, chii, or kan), the calling player discards without drawing. Pon and kan correctly set `skip_draw = 1`, but chii did not — the old comment ("allow normal draw") was a misunderstanding of the rules.

**Impact:** Each chii inflated the hand by 1 tile. With 4 chiis:
- Correct: 13 - 3*4 = 1 tile in hand (after melds + discards)
- Buggy: 13 - 2*4 = 5 tiles in hand

The extra tiles distorted AI hand evaluation, made win detection less likely (incorrect hand shapes), and was visible as too many tiles in the hand display.

**Discovery:** User reported 6 tiles in hand with 4 open melds displayed on screen. Standard Mahjong dictates 13 - 2*4 = 5 tiles after 4 chiis (at discard point), or 4 tiles after the discard. 6 tiles indicated an extra draw per chii.

**Fix:** Added `skip_draw = 1` in `ep_add_chii`, matching the existing pon and kan code paths.

## Added Kan Tile Display

**Problem:** "Declare Added Kan? (Y/N)" prompt showed garbage instead of the tile name (e.g. should show "Declare Added Kan? (Y/N) 5m").

**Root cause:** `check_added_kan` loaded the tile value from `opn_melds` into A and Y, but never stored it to `tmp8`. The comment at `cak_show` said "tmp8 = tile value from scan. Save it." but the save was never implemented. The display code then read whatever stale value was in `tmp8`.

**Fix:** Added `STA tmp8` after `LDA opn_melds, X` (1 byte added).

## Ron Chombo Carry Flag

**Problem:** Ron wins were always rejected as chombo (invalid win). `dbg_ron_wins` incremented but the player was told "Wall Exhausted" instead of being declared winner.

**Root cause:** In `check_chombo_win`, the carry flag (C=1 for win, C=0 for no win) returned by `check_win_no_rebuild` was destroyed by the tile_counts restore operation (`SEC: SBC #1` always set carry for counts >= 2). Result was inverted: valid wins rejected, invalid hands passed.

**Fix:** Wrapped the restore in PHP/PLP to preserve the carry flag across the tile_counts restore.

## Disc Autoboot Filename

**Problem:** SHIFT+BREAK autoboot failed with "Bad command". Manual `*RUN MAHJONG` worked fine.

**Root cause:** BeebAsm generated a !Boot file containing `*RUN MaJong` (mixed case, missing the 'H') while the binary was saved as `MAHJONG`. DFS uppercases the `*RUN` argument, so it looked for `MAJONG` which doesn't match `MAHJONG`.

**Fix:** Use the correct `executable="MAHJONG"` parameter matching the `SAVE "MAHJONG"` statement in the source. BeebAsm then generates the correct !Boot content with `*RUN MAHJONG` and proper RETURN characters.

## Game Over Screen — Quit Option

**Problem:** The game over screen displayed "Press any key..." with no way to quit back to BASIC. Players had to use the BBC's ESCAPE key to exit.

**Fix:** Changed the game over screen string to "Press P to play again or Q to quit". Any key (including P) restarts the game; Q quits to BASIC. The existing score display still uses the original "Press any key..." string unchanged.
