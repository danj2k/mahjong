# Architecture

## System Overview

The game is a single-file 6502 assembly program (`src/mahjong.asm`) that compiles to a DFS disc image. It runs as a monolithic binary starting at `&3000`, with data appended at the end. There is no separation between code and data at the file level — the assembler handles layout.

## Code Structure

The assembly file is organised into logical sections, each separated by comment banners:

### 1. Entry Point & Main Loop (~lines 92–420)

`start` initialises the display, shows the splash screen, selects difficulty and practice mode, seeds the RNG, and enters `mainloop`. The main loop is the central game driver:

- Handles skip_draw flag (for pon/kan where player discards without drawing)
- Calls `player_draw` for AI turns, `check_tsumo` for win detection
- Calls `sort_hand`, `check_closed_kan`, `check_added_kan`, `check_four_kans`
- Calls `check_riichi_human` / `check_riichi_ai` for riichi declarations
- AI turn: `ai_choose_discard` → `player_discard` → `check_ron` → `check_open_calls` → `game_display` → `ai_delay`
- Human turn: `human_input` → `player_discard` → `check_ron` → `check_open_calls` → `game_display`

### 2. Human Input (~lines 422–488)

`human_input` reads a key via `osrdch`. Handles Q (quit) and tile discard keys (Z–M for positions 1–7, A–J for positions 8–14). Includes bounds checking against `num_tiles` and beeps (VDU 7) on invalid input.

### 3. Practice Mode (~lines 489–600)

`practice_hint` scores each tile type in the human player's hand by connectivity: pairs and sequence neighbours get higher scores, isolated tiles get lower. Recommends discarding the most isolated tile.

### 4. Game Init & New Round (~lines 601–1650)

`game_init` zeros all state and sets initial scores to 25000. `new_round` builds the wall (136 tiles — 4 copies each of 34 tile types), shuffles it using an LCG PRNG, and deals 13 tiles to each player. Contains the full screen initialisation for each new hand.

### 5. Pointer Helpers (~lines 1697–1718)

`set_hand_ptr` and `set_disc_ptr` set `ptr` to point at a given player's hand or discard buffer using the base pointer tables (`hand_bases`, `disc_bases`).

### 6. Player Operations (~lines 1719–1821)

- `player_draw`: draws a tile from the wall, includes wall integrity check
- `check_wall_integrity`: counts all tile types in the live wall, triggers BRK if any type appears more than 4 times
- `player_discard`: removes tile from hand (shifts array left), stores in discard buffer, sets `disc_tile_val` and `disc_tile_player`

### 7. Sort Hand (~lines 1822–1858)

`sort_hand` implements a bubble sort on a player's hand array. Takes the player number in X register.

### 8. AI Logic (~lines 1860–2145)

`ai_choose_discard` scores each tile in the AI player's hand and discards the least connected one. Three difficulty tiers:

- **Novice:** Scores pairs (+3), adjacent tiles (+2), gaps (+1). No defensive play.
- **Intermediate:** Adds hand strength evaluation, riichi timing (3+ pairs, points threshold, opponent riichi avoidance), and basic defensive play (genbutsu — safe tile detection).
- **Expert:** Full hand evaluation including dora, more careful riichi timing, and full defensive play (counts visible copies of tiles to assess safety).

Helper routines: `is_tile_safe` (checks if tile has been discarded by anyone), `is_part_of_sequence`, `has_tile_in_hand`, `count_visible_copies`.

### 9. Open Call Detection (~lines 2146–2257)

`check_open_calls` is called after every discard. For each non-discarder player, it:
1. Calls `count_tiles_for_player` to build tile counts for the hand
2. Checks for pon (2+ matching tiles), chii (sequence possible), or kan (3 matching tiles)
3. For human players, prompts with Y/N; for AI, evaluates based on difficulty
4. Calls the appropriate execute routine if a call is made

### 10. Human Open Call Prompts (~lines 2258–2340)

Routines that display "Declare Pon? (Y/N)", "Declare Chii? (Y/N)", etc. with the discarded tile name, then wait for `osrdch`.

### 11. Execute Routines (~lines 2400–2704)

- `execute_pon`: removes 2 tiles from hand, records open meld (type 1)
- `execute_chii`: removes 2 tiles, records sequence meld (type 2)
- `execute_kan`: removes 3 tiles, records kan meld (type 4), draws rinshan tile
- `execute_closed_kan`: removes 4 tiles from hand, records closed kan (type 1), draws rinshan tile
- `execute_added_kan`: upgrades existing pon to kan (type 4), draws rinshan tile

All execute routines set `current_player` to the claiming player and set `skip_draw` where appropriate.

### 12. Display (~lines 2705–2998)

`game_display` clears the screen (VDU 12) and redraws everything:
1. Title line (row 0) — "RIICHI MAHJONG"
2. Points line (row 1) — all 4 players' scores with riichi/dealer indicators
3. Human hand (rows 3–5) — tile numbers and suit letters
4. Practice hint (row 7) — best discard and connectivity score (if practice mode on)
5. Human discards (row 8) — last 8 discards with meld labels
6. CPU player areas (rows 10–20) — each showing open melds, discards
7. Turn indicator (row 21) — "YOUR MOVE" or "CPU P2/P3/P4"
8. Controls help (row 22)
9. Status line (row 23) — dora, wall count, dealer, riichi sticks, honba

### 13. Point Display (~lines 2999–3087)

`disp_points_line` prints all 4 players' scores with indicators (F=first dealer, R=riichi, C=current dealer). Uses a 16-bit division routine for 5-digit score display.

### 14. Tile Character Routines (~lines 3088–3143)

`tile_num_char` and `tile_suit_char` convert tile values (0–33) to display characters. Suited tiles show digit+suit letter; honor tiles show letter+unique identifier.

### 15. Meld Decomposition Engine (~lines 3144–3340)

The core win detection algorithm:
- `build_tile_counts`: builds a 34-byte count array from the hand
- `decompose_melds`: recursively decomposes tiles into triplets and sequences using backtracking
- `check_win`: tries each possible pair, then calls `decompose_melds` on remaining tiles
- `check_win_no_rebuild`: for ron — adds the discarded tile to existing counts and checks

### 16. Scoring (~lines 3340–4600)

- `check_yaku`: evaluates all 19 standard yaku against the hand
- `check_yakuman`: evaluates all 12 yakuman hands
- `calc_fu`: calculates fu (base points) from melds and wait type
- `calc_score`: converts han/fu to point values with mangan/haneman/baiman limits
- `count_fu_melds`: counts fu for each meld type

### 17. Ron Detection (~lines 4600–4700)

`check_ron` iterates over non-discarder players, adds the discarded tile to their tile counts, and calls `check_win_no_rebuild`. The `tsumo_flag` (ZP `&80`) is set before calling `check_chombo_win` to distinguish tsumo from ron — for ron, `check_chombo_win` must temporarily add `disc_tile_val` to tile_counts before calling `check_win`, since the discarded tile is not in the hand array.

### 18. Riichi Logic (~lines 4700–4900)

- `check_riichi_human`: evaluates human hand for tenpai, prompts to declare riichi
- `check_riichi_ai`: evaluates AI hand strength, declares riichi based on difficulty

### 19. Kan Prompts (~lines 4900–5100)

`check_closed_kan` and `check_added_kan` scan the hand for 4-of-a-kind or existing pon+1, prompting the human with Y/N (showing the tile name).

### 20. Win Display & Score Application (~lines 5100–5600)

Shows the winner's hand, applies scores, displays tsumo/ron payments, and handles abortive draw displays.

### 21. New Round Setup (~lines 5600–5900)

`new_round` builds the wall, shuffles, deals tiles, and initialises round state. Includes dora indicator setup.

### 22. Data Section (~lines 5960–6490)

All persistent game state is stored here:

| Label | Size | Purpose |
|-------|------|---------|
| `hand_bases` | 8 bytes | Pointer table to each player's hand |
| `disc_bases` | 8 bytes | Pointer table to each player's discards |
| `wall` | 136 bytes | The tile wall array |
| `hands` | 56 bytes | 4 players × 14 tiles |
| `num_tiles` | 4 bytes | Tiles in each player's hand |
| `discards` | 96 bytes | 4 players × 24 max discards |
| `num_discards` | 4 bytes | Discard count per player |
| `wall_pos` | 1 byte | Current position in wall |
| `current_player` | 1 byte | Active player index (0–3) |
| `rng_seed` | 1 byte | PRNG seed (initialised from VIA timer) |
| `player_points` | 8 bytes | 16-bit scores for all 4 players |
| `riichi_sticks` | 4 bytes | Riichi stick count per player |
| `honba` | 1 byte | Consecutive draw counter |
| `riichi_on_table` | 1 byte | Total riichi sticks on table |
| `opn_melds` | 80 bytes | Open meld storage (4×4×5 bytes) |
| `opn_count` | 4 bytes | Open meld count per player |
| `tile_counts` | 34 bytes | Tile type counts for win detection |

## Data Flow

```
wall → player_draw → hand → sort_hand → check_tsumo/check_ron → check_win
hand → ai_choose_discard → player_discard → discards
discards → check_open_calls → execute_pon/chii/kan → opn_melds
hand + opn_melds → check_yaku → check_yakuman → calc_fu → calc_score
```

## Dependencies

- **BeebAsm** assembler (no runtime dependencies)
- **BBC MOS** (OSWRCH, OSRDCH, OSBYTE, OSNEWL, OSCLI)
- **BeebEm or beebjit** emulator for testing and running
