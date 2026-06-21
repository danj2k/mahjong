# Implementation Notes

## Win Detection Algorithm

The win detection is the most critical subsystem. It uses a recursive backtracking algorithm (`decompose_melds`) that:

1. Finds the first tile type with count > 0
2. Tries a triplet (subtract 3 from that type's count, recurse)
3. If triplet fails, tries a sequence (subtract 1 from type, type+1, type+2 — only if type mod 9 ≤ 6 to stay within suit)
4. If both fail, backtracks by restoring the counts

The `check_win` function wraps this by first trying every possible pair (subtract 2 from each type with count ≥ 2), then calling `decompose_melds` on the remaining 12 tiles.

**Invariant:** `decompose_melds` expects `tile_counts` to be a valid count array where the sum of all counts equals a multiple of 3. It modifies `tile_counts` in place and restores it on backtracking.

**Edge case:** The `no_seq_flag` (ZP `&81`) is set during the toitoi check to prevent sequences when the hand has no sequences. This flag is only set inside `check_yaku` and must be cleared before returning.

## Hand Sorting

`sort_hand` uses a bubble sort on the hand array. It takes the player number in X, calls `set_hand_ptr` to get the pointer, then reads `num_tiles[player]` for the count. The sort must be called with the correct player number — calling with a garbage X value (e.g. 34, left over from `check_win`) reads from `hand_bases + 68`, producing a random 16-bit pointer that corrupts arbitrary memory.

**This was a critical bug:** Before the fix, `sort_hand` was called after `check_win` without setting X to `current_player`. The random pointer caused bubble-sorting of arbitrary memory, corrupting hands, discards, wall arrays, and open meld data. This explained symptoms including wrong tiles in discards, wall corruption, and impossible meld counts.

## Wall Integrity Check

`check_wall_integrity` runs on every tile draw. It zeros a 34-byte count buffer, scans all 122 positions in the wall array (0 to DORA_START-1), and increments the count for each tile type. If any type reaches 5 copies, it triggers a BRK instruction.

The check adds ~1.4ms per tile draw (136 iterations × ~20 cycles each at 2MHz). This is imperceptible during gameplay but provides early detection of memory corruption.

**Known limitation:** The check only validates the live wall (positions 0–121). It does not check the dead wall (positions 122–135) or the discard buffers.

## Discard Display (last 8 only)

`calc_disc_start` calculates the start index for displaying the last 8 discards. Mode 7 is 40 characters wide, and each tile takes 2 characters, so only 8 tiles fit per display line. When a player has more than 8 discards, older ones scroll off.

The discards are stored in a circular-like buffer of 24 bytes per player (`MAX_DISC`). The display reads from position `num_discards - 8` (or 0 if fewer than 8) to `num_discards - 1`.

## Meld Display Filtering

`disp_open_melds` iterates through ALL melds in the global `opn_melds` buffer, filtering by the current player's ID stored in byte 0 of each meld entry. This replaced an earlier implementation that showed all melds for all players, causing CPU players to display 5+ melds (the total across all players).

## RIICHI MAHJONG Title on Row 0

The title string is fixed at 40 characters (padded with trailing spaces) to prevent Mode 7 wrapping. In Mode 7, writing exactly 40 characters to a row positions the cursor at column 0 of the next row. Writing 41 characters causes a wrap that pushes the cursor to column 1 of the next row, offsetting all subsequent display by one column. The title is positioned at row 0 via `VDU 31,0,0` before printing.

## Practice Mode Hint Algorithm

`practice_hint` evaluates each tile in the human hand by:
1. Temporarily removing tile at position Y from the hand (shifts remaining tiles left)
2. Building `tile_counts` from the 13-tile hand
3. For each tile type in `tile_counts`, trying it as a pair and calling `decompose_melds`
4. If a winning decomposition is found, incrementing a counter for this position
5. Restoring the tile (shifts back)

The position with the highest count is recommended as the best discard. The count represents how many different tiles would complete a winning hand.

**Performance concern:** This runs on every human turn and evaluates up to 14 positions × 34 tile types × recursive decomposition. On the 2MHz 6502 this may cause a brief pause (~1-2 seconds) which is acceptable for practice mode.

## Key Mapping

The discard key mapping uses QWERTY keyboard rows:
- Z=1, X=2, C=3, V=4, B=5, N=6, M=7 (bottom row, positions 1–7)
- A=8, S=9, D=10, F=11, G=12, H=13, J=14 (middle row, positions 8–14)

Both uppercase and lowercase are accepted — the `parse_disc_key` routine converts lowercase to uppercase before the lookup table.

The table is stored as pairs of (BBC key code, position) with 0 terminator. The lookup is O(n) linear scan, which is fine for 14 entries.

## CPU Turn Flow

Each CPU player's turn follows this sequence:
1. `player_draw` — draws tile from wall
2. `check_tsumo` — checks for tsumo win
3. `sort_hand` — sorts hand for consistent display
4. `check_closed_kan` / `check_added_kan` — kan opportunities
5. `game_display` — shows board BEFORE discard (so player sees the new tile)
6. Kan/riichi declarations if applicable
7. `ai_choose_discard` — selects best discard
8. `player_discard` — discards selected tile
9. `check_ron` — checks if any player can claim the discard
10. `check_open_calls` — checks pon/chii/kan from discard
11. `game_display` — shows board AFTER discard
12. `ai_delay` — 2 second pause for visibility
13. `advance_player` — moves to next player

## Abortive Draw Detection

Three abortive draw conditions are checked:
- **Four winds:** Each player's first discard is a wind tile
- **Four kans:** Total kans across all players reaches 4
- **Triple ron:** Multiple players declare ron on the same discard (currently not implemented as abortive — would need simultaneous win detection)

Nine Gates (a specific 13-tile hand that wins with any tile of the same suit) is checked as a yakuman, not an abortive draw.

## Chombo Penalty

Chombo is applied when an illegal action is detected. The penalty is 8000 points (or 12000 for the dealer). Currently, chombo is only triggered by the `check_chombo_win` routine, which appears to be a simplified check. A full implementation would need to validate that open calls are legal, that riichi conditions are met, and that tile declarations are valid.

## DFS Disc Image

The disc image is created by BeebAsm with:
```
beebasm -i src/mahjong.asm -boot MAHJONG -do build/mahjong.ssd
```

The `-boot MAHJONG` flag creates a `!Boot` file that auto-runs the binary. The binary is saved as `MAHJONG` on the disc. The disc image contains just the boot file and the binary — no other files.
