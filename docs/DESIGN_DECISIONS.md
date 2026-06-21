# Design Decisions

## Tile Encoding (0–33 flat array)

**Decision:** Tiles are encoded as integers 0–33 (0–8 man, 9–17 pin, 18–26 sou, 27–30 winds, 31–33 dragons) rather than suit+rank pairs.

**Why:** This allows direct array indexing into a 34-byte `tile_counts` buffer for win detection. The `decompose_melds` algorithm iterates tile types 0–33 and checks sequences by looking at type+1 and type+2 — which naturally stays within suit boundaries when `type mod 9 ≤ 6`. This eliminates the need for suit-crossing checks in the core algorithm.

**Trade-off:** Tile display requires conversion routines (`tile_num_char`, `tile_suit_char`) rather than simple arithmetic. The display format is a two-row stacked layout (number/letter on top, suit letter on bottom) which is specific to this game.

## Display Format (Mode 7 stacked tiles)

**Decision:** Tiles are displayed as two rows — top row shows the number or honor letter, bottom row shows the suit letter.

**Why:** Mode 7 is 40 characters wide. A single-row format (e.g. "1m 2m 3m") would only fit ~13 tiles per row. The stacked format allows up to 14 tiles in a single hand display line, with the two rows taking only 2 screen rows instead of 1. This was chosen to fit all game information (hand, discards, CPU melds, status) on a single 25-row screen.

## Single Monolithic Binary

**Decision:** The entire game (code + data + strings) is a single assembly file compiled to a single binary.

**Why:** BBC Micro DFS disc images have limited directory structure. A single binary is simpler to manage, avoids cross-file linking issues with BeebAsm, and fits within the 32KB memory limit. The binary loads at `&3000` and runs from there.

**Trade-off:** The file is ~6,500 lines which makes navigation harder. The comment banners and label naming conventions mitigate this.

## Zero Page Usage

**Decision:** Zero page is confined to `&00–&8D` (safe zone), with `&70–&8F` used for temporary variables and `&80–&8D` for per-player flags.

**Why:** The BBC Micro's Econet system uses `&90–&9F`, and the OS uses `&A0–&FF`. Using these addresses causes unpredictable crashes. The safe zone provides 142 bytes of fast-access memory which is sufficient for all temporary variables and flags needed by the game's recursive algorithms.

## sort_hand in X Register

**Decision:** `sort_hand` takes the player number in the X register rather than reading `current_player`.

**Why:** After a critical bug where `check_win` left X=34 (TILE_TYPES) and `sort_hand` used it as the player number, reading from `hand_bases + 68` (past the 8-byte table), all `sort_hand` call sites now explicitly set `LDX current_player` before calling. This makes the contract explicit and prevents future regressions.

## Open Melds Storage (5-byte entries)

**Decision:** Each open meld is stored as 5 bytes: type (1=pon, 2=chii, 3=closed kan, 4=open kan, 5=added kan), player ID, tile1, tile2, tile3.

**Why:** The player ID byte was added to fix a display bug where `disp_open_melds` was showing ALL melds for ALL players instead of filtering by player. Storing the player byte directly in the meld entry avoids needing a separate per-player index system.

## Closed Kan Offset Calculation (×5)

**Decision:** Meld storage uses `opn_count[player] * 5` as the byte offset into `opn_melds`.

**Why:** A previous bug used `opn_count * 4` which caused closed kan melds to be written at wrong offsets, corrupting adjacent meld data and cascading into memory corruption. The ×5 multiplier matches the 5-byte meld format. Each player gets 20 bytes (4 melds × 5 bytes) in the 80-byte `opn_melds` buffer.

## LCG PRNG (seed * 5 + 7)

**Decision:** The PRNG uses a linear congruential generator with a=5, c=7, mod 256.

**Why:** Previous implementations used an xorshift with shifts (1,1) which had a period of only 15 — causing wall shuffles to repeat every 4 hands. The LCG has a full period of 256 (verified via Hull-Dobell criteria), which is sufficient for 136-tile wall shuffles. The seed is initialised from the hardware System VIA timer at startup for true randomness.

## Y/N Prompts (not single-key)

**Decision:** All interactive prompts use Y/N instead of single-letter shortcuts (e.g. "Declare Riichi? (Y/N)" instead of "Declare Riichi? (R)").

**Why:** Single-letter prompts looked strange on screen and the key mapping was inconsistent (R for riichi, K for kan, but Y/N for pon/chii). Standardising on Y/N across all prompts provides a consistent user experience. The Y key also works as lowercase y since `osrdch` returns the raw character.

## Clear Prompt Line

**Decision:** When a user declines a prompt, `clear_prompt_line` positions the cursor at row 24 and overwrites 39 spaces.

**Why:** Without clearing, multiple prompts would stack on screen (e.g. "Declare Closed Kan? (Y/N)" followed by "Declare Riichi? (Y/N)" both visible). The 39-space width (columns 0–38) prevents scrolling — printing 40 spaces from column 0 would push the cursor past the right edge, causing Mode 7 to scroll the entire display up by one row.

## CPU Turn Indicator

**Decision:** During AI turns, "CPU P2/P3/P4" is displayed instead of "YOUR MOVE", positioned before the delay loop.

**Why:** Without an indicator, the player had no visual feedback that it was an AI's turn — tiles would just appear in discards. The indicator appears before the delay so the player can see which AI is acting during the ~2 second pause.

## AI Delay (2 seconds)

**Decision:** A triple-nested loop provides approximately 2 seconds of delay between AI turns.

**Why:** The original delay (~1 second) was too fast to visually track which AI player was acting. The 2-second delay gives the player time to see each AI's action. The delay is implemented as a busy loop rather than OSWAIT because OSWAIT has minimum granularity issues on the BBC Micro.
