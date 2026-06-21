# 🀄 Riichi Mahjong

A complete four-player Riichi Mahjong game for the BBC Micro, written in 6502 assembly language using [BeebAsm](https://github.com/stardot/beebasm). One human player faces three AI opponents, with a full implementation of Japanese mahjong rules including all 19 standard yaku, 12 yakuman, and multiple AI difficulty levels.

## 🔍 Transparency Notice

This game was developed entirely by AI tools. The 6502 assembly source code, game logic, AI routines, scoring system, and all game rules were written, tested, and debugged by AI assistants. No human programmer wrote or modified the assembly code. The BBC Micro platform constraints (Mode 7 teletext display, zero page memory management, DFS disc images) were managed entirely through AI-driven development.

## 🎮 How to Play

### 🚀 Getting Started

1. Load the disc image `mahjong.ssd` in a BBC Micro emulator (such as BeebEm or beebjit)
2. The game boots to a title screen — press any key to continue through the information pages
3. Select a difficulty level for the three AI opponents (Novice, Intermediate, or Expert)
4. Select Practice Mode (ON or OFF)
5. The first hand is dealt and you play as Player 1 (East)

### 🎲 Gameplay

Each hand begins with 13 tiles dealt to each player. On your turn you draw one tile (14 total), then discard one tile to return to 13. The game continues clockwise until someone wins or the wall is exhausted.

**Your turn:**
- Your tiles are displayed in order from left to right. To discard a tile, press the letter corresponding to its position: **Z** to **M** (bottom row of a QWERTY keyboard) for positions 1 to 7, then **A** to **J** (middle row) for positions 8 to 14
- If Practice Mode is on, the game will suggest the best discard — press the key shown to discard that tile
- The hint also shows **"wait for X tiles"** — this is how many tiles remain in the game (in the wall or in opponents' hands) that would complete your winning hand. A higher number means more chances to win after discarding
- Press **Q** to quit the game

**Between turns:**
- When an opponent discards a tile you can claim, you will be prompted with **Y/N** to accept or decline
- You may also be prompted to declare a **Closed Kan** (4 of a kind in your hand) or a **Riichi** (1-tile-away bet)

### 🏆 Winning

A winning hand consists of **4 [melds](#-melds) and 1 pair** (14 tiles total), or **7 pairs** (Chiitoitsu). There are two ways to win:

- **Tsumo** — draw the winning tile yourself
- **Ron** — claim a tile discarded by any opponent

After a win, your hand is scored by counting **han** (bonus points) and **fu** (base points). You need at least 1 han to win.

### 💡 Practice Mode

When Practice Mode is ON, the game provides helpful guidance on every turn:

- **Best discard recommendation** — shows the optimal tile to discard and how many tiles wait for a win (the "wait for X tiles" count indicates how many different tiles in the remaining wall could complete your hand — a higher count means a better chance of winning)
- **Yaku breakdown** — after a win, displays each scoring category (han, fu, and point totals)

This is useful for learning mahjong strategy and understanding which yaku are achievable.

## ⚙️ Difficulty Levels

The three AI opponents share a single difficulty setting:

### 🟢 Novice
- Basic tile selection — discards the least useful tile
- Simple open call logic — calls pon/chii when a meld is available
- No riichi declarations
- No defensive play

### 🟡 Intermediate
- Smarter tile selection — evaluates pairs, sequences, and near-complete melds
- Evaluates hand strength before making open calls
- Declares riichi when the hand has at least 3 pairs and meets a points threshold
- Avoids riichi when another player is already in riichi
- Basic defensive play — considers safe tiles (genbutsu) when an opponent declares riichi

### 🔴 Expert
- Full hand evaluation — scores melds, pairs, sequences, and dora
- Evaluates hand value before making open calls (minimum tile importance threshold)
- Carefully times riichi declarations — considers hand value, wall tiles remaining, and opponent riichi status
- Full defensive play — counts visible copies of each tile, identifies safe tiles (genbutsu), avoids discarding tiles that other players might claim

## 📜 Rules

### 🀇 Tiles

The game uses 136 tiles — 4 copies of each of 34 distinct tiles:

| Group | Tiles | Notation |
|-------|-------|----------|
| **Man** (Characters) | 1–9 of characters | 1m–9m |
| **Pin** (Circles) | 1–9 of circles | 1p–9p |
| **Sou** (Bamboo) | 1–9 of bamboo | 1s–9s |
| **Winds** | East, South, West, North | Ew, Sw, Ww, Nw |
| **Dragons** | Red (Chun), Green (Hatsu), White (Haku) | R, Gb, Tb |

### 🔗 Melds

- **Chi** — Three consecutive tiles of the same suit (e.g. 4m 5m 6m). Only the player to the left of the discarder may declare chi.
- **Pon** — Three identical tiles (e.g. three 5p). Any player may declare pon.
- **Kan** — Four identical tiles. Comes in three forms:
  - **Closed Kan** — All 4 tiles in your hand (not claimed from a discard)
  - **Open Kan** — Claim a discard with 3 matching tiles from your hand
  - **Added Kan** — Add a 4th tile to an existing open pon
- Each kan draws a replacement tile from the dead wall and reveals an additional dora indicator.

### 🎯 Riichi

When your hand is **one tile away from winning** (tenpai) and your hand is closed, you may declare riichi. This costs 1000 points from your score and **locks your hand** — you cannot change which tiles you hold or make any open calls (pon, chii, or kan). You must discard the tile you draw each turn. If you win while in riichi, you score bonus points. Ippatsu (winning within one full rotation of declaring riichi) adds an extra bonus.

### ⏸️ Abortive Draws

The hand is declared void and redealt without penalty if:
- **Four kans** are declared by all players combined
- **Four winds** (E, S, W, N) appear as the first discard from each player

### ⚠️ Chombo

A penalty of 8000 points (or 12000 for the dealer) is applied if an illegal call is attempted — for example, declaring chi when it is not your turn, or attempting to call a tile that does not form a valid meld.

## 📊 Scoring

### ⭐ Han (Bonus Points)

Each yaku in your hand contributes han. Common yaku and their values:

| Han | Yaku |
|-----|------|
| 1 | Menzen Tsumo, Riichi, Ippatsu, Iipeiko, Tanyao, Pinfu, Yakuhai, Tan Yao, Chanta |
| 1 | Sanshoku, Yakuhai, Round Wind, Seat Wind |
| 2 | Double Riichi, Ittsu, Toitoi, Sanankou, Sanshoku Doujun, Chanta (open), Shousangen |
| 3 | Honitsu, Ryanpeikou, Chanta (closed) |
| 6 | Chinitsu |

### 🔢 Fu (Base Points)

Fu starts at 30 for a basic hand and increases based on:
- **Pair** — +2 fu if yakuhai (seat wind, round wind, or dragon)
- **Closed melds** — +4 fu for terminal/honor sequences, +8 for terminal/honor triplets, +4 for simple triplets (when open: +2/+4/+4)
- **Meld type** — closed kan counts double compared to open
- **Wait** — +2 fu for a pair wait, +2 fu for an edge or pair wait on the final tile
- **Win type** — +20 fu for ron, +10 fu for menzen tsumo

Fu is rounded up to the nearest 10.

### 🧮 Point Calculation

Base points = fu × 2^(2+han). The score is then adjusted based on who wins and how:

- **Ron** (win from discard): Winner receives 4× base points from the discarder
- **Tsumo** (self-draw): Non-dealers pay 2× base points each; dealer pays 4× base points
- All payments are rounded up to the nearest 100

### 📈 Score Limits

| Limit | Han | Base Points |
|-------|-----|-------------|
| Mangan | 5+ han | 2,000 |
| Haneman | 6–7 han | 3,000 |
| Baiman | 8–10 han | 4,000 |
| Sanbaiman | 11–12 han | 6,000 |
| Yakuman | 13+ han | 8,000 |

## 🀄 Yaku

### 1️⃣ 1 Han (Open or Closed)

| Yaku | Japanese | Meaning |
|------|----------|---------|
| Riichi | 立直 | "Standing straight" — a declaration that you are one tile from winning; locks your hand and prevents open calls |
| Ippatsu | 一発 | "One shot" — winning within one full rotation after declaring riichi |
| Menzen Tsumo | 門前自摸 | "Closed hand self-draw" — winning by drawing the last tile yourself with a closed hand |
| Tanyao | 断幺九 | "Broken terminals" — a hand with only simples (tiles 2–8), no terminals or honors |
| Pinfu | 平和 | "Flat hand" — all sequences in a closed hand, pair is not yakuhai, and the winning wait is a two-sided sequence wait |
| Iipeiko | 一盃口 | "One cup" — two identical sequences in the same suit (closed only) |
| Yakuhai | 役牌 | "Value tile" — a triplet of the round wind, seat wind, or any dragon |
| Sanshoku | 三色同順 | "Three colour same sequence" — the same sequence in all three suits (e.g. 1-2-3 man, 1-2-3 pin, 1-2-3 sou) |
| Sanshoku Doujun | 三色同順 | "Three colour same sequence" — same as above but open (1 han instead of closed) |
| Ittsu | 一気通貫 | "Straight through" — sequences 123, 456, 789 in one suit |

### 2️⃣ 2 Han (Open or Closed)

| Yaku | Japanese | Meaning |
|------|----------|---------|
| Double Riichi | 二重立直 | "Double standing straight" — declaring riichi on your very first discard (a second riichi declaration) |
| Chanta | 混全帯幺九 | "Mixed outside" — all melds and the pair contain at least one terminal or honor tile (open: 1 han) |
| Chiitoitsu | 七対子 | "Seven pairs" — seven distinct pairs (closed only, counts as 2 han) |
| Toitoi | 対々和 | "All triplets" — all four melds are triplets (no sequences) |
| Sanankou | 三暗刻 | "Three concealed triplets" — three triplets entirely within your hand (not claimed from discards) |
| Honroutou | 混老頭 | "Mixed old man" — all tiles are terminals or honors (includes both triplets and pairs) |

### 3️⃣ 3 Han (Open or Closed)

| Yaku | Japanese | Meaning |
|------|----------|---------|
| Honitsu | 混一色 | "Mixed one colour" — tiles from only one suit plus honor tiles |
| Ryanpeikou | 両盃口 | "Two cups" — two pairs of identical sequences in the same suit (closed only) |

### 6️⃣ 6 Han

| Yaku | Japanese | Meaning |
|------|----------|---------|
| Chinitsu | 清一色 | "Pure one colour" — tiles from only one suit, no honor tiles |

## 👑 Yakuman

Yakuman hands score maximum points. This game implements all 12 standard yakuman:

| Yakuman | Japanese | Meaning |
|---------|----------|---------|
| Kokushi Musou | 国士無双 | "Thirteen Orphans" — one each of all 13 terminal and honor tiles, plus one duplicate of any |
| Suuankou | 四暗刻 | "Four Concealed Triplets" — four triplets entirely in your hand (winning tile completes a triplet by tsumo) |
| Daisangen | 大三元 | "Big Three Dragons" — triplets of all three dragon tiles |
| Tsuuiisou | 字一色 | "All Honors" — hand composed entirely of wind and dragon tiles |
| Chinroutou | 清老頭 | "All Terminals" — hand composed entirely of 1s and 9s in the three suits |
| Ryuuiisou | 緑一色 | "All Green" — hand composed entirely of green tiles (2s, 3s, 4s, 6s, 8s sou, and Hatsu) |
| Chuuren Poutou | 九蓮宝燈 | "Nine Gates" — a specific 1-1-1-2-3-4-5-6-7-8-9-9-9 sequence in one suit, plus any tile of that suit |
| Daisuushii | 大四喜 | "Big Four Winds" — triplets of all four wind tiles |
| Shousuushii | 小四喜 | "Little Four Winds" — three wind triplets plus a wind pair |
| Suukantsu | 四槓子 | "Four Kans" — four kans (open, closed, or added) declared by a single player |
| Tenhou | 天和 | "Heavenly Hand" — dealer wins on the very first draw |
| Chiihou | 地和 | "Earthly Hand" — non-dealer wins on the very first draw (before their first discard) |

## 📋 Tile Notation Reference

Tiles are displayed in two rows in the game:

```
Top row:    1 2 3 4 5 6 7 8 9 E S W N T H C
Bottom row: m m m p p p s s s w w w w g b r
```

- **m** = Man (Characters): 1m–9m
- **p** = Pin (Circles): 1p–9p
- **s** = Sou (Bamboo): 1s–9s
- **w** = Wind: Ew (East), Sw (South), Ww (West), Nw (North)
- **g** = Hatsu (Green Dragon)
- **b** = Haku (White Dragon)
- **r** = Chun (Red Dragon)

## 🔧 Technical Details

- **Platform:** BBC Micro (Model B or Master)
- **Language:** 6502/65C02 assembly (BeebAsm)
- **Display:** Mode 7 (40×25 teletext)
- **Storage:** DFS disc image (.ssd)
- **Code size:** ~6,300 lines of assembly
- **Memory:** Zero page confined to &00–&8D; user scratch at &70–&8F; page 2 for tile and meld data

### ▶️ Running

```bash
# Assemble with BeebAsm
beebasm -i src/mahjong.asm -boot MAHJONG -do build/mahjong.ssd

# Or use the build script
cd src && beebasm -i mahjong.asm -boot MAHJONG -o ../build/MAHJONG -do ../build/mahjong.ssd
```

### ⌨️ Controls

| Key | Action |
|-----|--------|
| Z–M / A–J | Discard the tile at position 1–7 (Z–M, bottom QWERTY row) or 8–14 (A–J, middle row) |
| Y | Accept a prompt (declare riichi, pon, chii, or kan) |
| N | Decline a prompt |
| Q | Quit the game |
