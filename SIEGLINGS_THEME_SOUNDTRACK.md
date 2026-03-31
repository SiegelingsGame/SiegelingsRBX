# Sieglings Theme Soundtrack

## Goal

Create a gameplay loop that feels heroic, elemental, and slightly mysterious without becoming tiring over long play sessions.

## Musical direction

- Heroic fantasy first, light mystical shimmer second
- Noble and adventurous, not grimdark
- Steady motion for exploration, base building, and creature battles
- Enough lift to support the "siege knight" identity, but mixed softly enough that combat and UI sounds still read clearly

## Loop structure

- Total export length: `72 seconds`
- Intro: `0:00 - 0:08`
- Gameplay loop body: `0:08 - 1:12`
- Export with a clean seam so `0:08` can jump back from `1:12` during gameplay

## Suggested palette

- Frame drums or light taiko pulse
- Low strings with occasional staccato drive
- Hammered dulcimer or cimbalom shimmer for the card-and-sigil feel
- French horn or warm brass swells for the knight motif
- Airy choir pad or elemental synth bed
- Soft metallic impacts and reversed breath transitions

## Motif notes

- Build the main phrase around a four-note rise that hints at the Four Houses
- Answer it with a steadier descending line so the loop feels grounded
- Save the biggest brass hit for the intro; keep the main body smoother so repetition stays pleasant

## AI composer prompt

Compose a seamless gameplay soundtrack for a Roblox creature-collection fantasy game called Sieglings. Blend heroic medieval adventure with elemental mysticism. Use steady frame drums, low strings, horn swells, dulcimer shimmer, airy choir, and subtle magical pulses. Keep it uplifting, noble, and slightly mysterious rather than dark. Write an 8-second intro followed by a 64-second loop body that can repeat cleanly without a noticeable seam. Medium energy, around 92 BPM, instrumental only, no vocals, no hard ending, leave room for combat and UI sound effects.

## Roblox implementation notes

- Upload the final track and replace `GameConfig.GameplayMusic.SoundId`
- Keep `LoopStartTime = 8.0` and `LoopEndTime = 72.0` if the export matches this brief
- If the final file is fully seamless from the first beat, set both loop values to `0` and let Roblox's built-in looping handle it
