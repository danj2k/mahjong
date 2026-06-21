# Project Overview

## Purpose

A complete four-player Riichi Mahjong game for the BBC Micro, written in 6502 assembly language. One human player faces three AI opponents, with a full implementation of Japanese mahjong rules including all 19 standard yaku, 12 yakuman, and multiple AI difficulty levels.

## Goals

- Implement a faithful and complete Riichi Mahjong game on the BBC Micro platform
- Provide three distinct AI difficulty levels with increasing sophistication
- Include practice mode with discard hints to help players learn
- Run within the constraints of the BBC Micro's Mode 7 display and memory model
- Achieve a playable game with reasonable AI that can win hands

## Non-Goals

- Network multiplayer — single player only
- Graphics beyond Mode 7 teletext — the game uses text-mode display throughout
- Complete tenpai/hepai efficiency for the AI — the game is meant to be learnable
- Tenhou/Chiihou (instant win) detection in practice mode (noted as a missing feature)

## Constraints

- **Platform:** BBC Micro (Model B or Master), running BeebAsm 6502 assembler
- **Display:** Mode 7 (40×25 characters, teletext graphics mode)
- **Storage:** DFS disc image (.ssd format)
- **Memory:** Zero page confined to &00–&8D (safe zone); user scratch at &70–&8F; Econet zone &90–&9F is unsafe; OS zone &A0–&FF must not be used
- **Code size:** ~6,500 lines of assembly, ~12KB binary
- **CPU:** 65C02 — no PHX/PLX/PHY/PLY/BRA instructions, `.label:` syntax, semicolons for comments
- **No dynamic memory allocation** — all buffers are statically sized at assembly time
