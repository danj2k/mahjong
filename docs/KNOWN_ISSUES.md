# Known Issues

## AI Hand-Building Quality

**Status:** Likely the primary remaining issue

The AI discard logic scores tiles based on connectivity (pairs, sequences, gaps) but does not evaluate hand value or tenpai state. With the recent outer-loop fix, the AI now evaluates all tiles in its hand, but the scoring heuristics may still be too basic to consistently build winning hands. Debug counters from gameplay show 70+ tsumo checks with 0 wins, suggesting the AI is not progressing toward winning hands efficiently.

**Impact:** Games frequently end in wall exhaustion with no winner.

**Suggested improvement:** Implement a tenpai check in the AI — after each discard, check if the hand is one tile away from winning. If so, keep the hand in tenpai and only discard drawn tiles that don't complete the hand. This would dramatically improve the AI's ability to win.

## Chombo Detection is Incomplete

**Status:** Partially implemented

The chombo penalty system exists but only detects a simplified set of illegal actions. A full implementation would need to:
- Validate that open calls are legal (correct turn, correct tile, valid meld)
- Validate that riichi conditions are met (closed hand, tenpai, sufficient points)
- Detect illegal tile declarations
- Handle chombo scoring correctly (8000 points, or 12000 for dealer)

## Triple Ron Not Implemented

**Status:** Not implemented

The `check_ron` routine checks each non-discarder player for a win, but does not handle the case where multiple players can claim the same discard (triple ron). In standard Riichi Mahjong, triple ron is an abortive draw. The code has a placeholder `abortive_triple_ron_str` but the detection logic is not wired in.

## Tenhou/Chiihou Detection Missing

**Status:** Not implemented

The `first_turn` flag exists in the data section but is never set or checked. Tenhou (dealer wins on first draw) and Chiihou (non-dealer wins on first draw before first discard) are listed as yakuman in the README but are not detected.

## Practice Mode Display

**Status:** Works but limited

The practice mode shows the best discard and wait count, but the display area (row 7) is small and can only show one line of hint text. More detailed information (e.g. which yaku are achievable, how many tiles needed for each) would require rethinking the screen layout.

## Wall Count Display for Values ≥ 100

**Status:** Fixed but may reappear

The hundreds digit display was added to handle values ≥ 100 (which occur if `wall_pos` is corrupted). In normal gameplay, the wall count never exceeds 70 (after dealing). If this display issue recurs, it indicates memory corruption in `wall_pos`.

## Screen Layout Crowding

**Status:** Known limitation

Mode 7's 40×25 character limit means the screen is tightly packed. With 4 CPU players each showing open melds and discards, the display can feel cramped. The current layout allocates specific rows for each player's information, but there is no scrollback — if a player has many discards, older ones are lost from view.

## No Undo/Discard Confirmation

**Status:** By design but potentially frustrating

Once a tile is discarded, the action is immediate with no confirmation prompt. Players who accidentally press the wrong key have no way to undo. The invalid key beep (VDU 7) helps prevent typos, but a confirmation step before discarding would be more robust.

## Debug Counters in Production

**Status:** Active

The current build includes debug counters (`dbg_tsumo_calls`, `dbg_tsumo_wins`, `dbg_ron_calls`, `dbg_ron_wins`) that are visible in memory. These should be removed or disabled before a final release build, as they consume data section space and could confuse players who inspect memory.

## Wall Corruption (Investigating)

**Status:** Under investigation

Memory dumps showed the wall array contained 5 copies of 1m and 1s, with only 3 copies of Nw and Cr. This suggests two wall positions were overwritten during gameplay. BRK-based debug traps have been added at the wall integrity check and wall count display to catch this at the source if it recurs. The sort_hand fix may have resolved this, as it was the most likely source of random memory writes.
