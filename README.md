# README

## Crazy Streamer Tool for OBS Studio

Single-file OBS Lua control panel for silhouette FX, automation, media/chat controls, natural-language commands, presets, and diagnostics.

Now includes a built-in Voice Changer (pitch shift) with low-to-high and high-to-low quick buttons.

## Setup

1. Open OBS.
2. Go to Tools -> Scripts.
3. Add the Lua file and select Multi-tool.lua.
4. In the script panel:
   1. Choose Webcam Source.
   2. Choose Audio Source (for sound-reactive features).
   3. Optionally choose Media Source and Chat Overlay Source.
   4. Pick Talking and Waiting scenes if you want voice scene switching.
5. Press Health Check once.
6. Optional: press Assign All Recommended Hotkeys, then open Settings -> Hotkeys and bind the listed CST actions.

## Natural Language Command Examples

- make my silhouette electric purple and pulse to the beat
- switch to gaming mode with green outline and chat overlay
- cycle colors every 8 seconds and enable sound reactive glow
- enable strobe flash and random burst
- disable glow and disable strobe
- enable voice changer high pitch
- set voice changer high to low
- reset voice to normal

## Voice Changer Setup

1. Select your mic in Audio Source.
2. Open the Voice Changer group in the script panel.
3. Enable Voice Changer.
4. Use one of these options:
  1. Pitch Shift slider from -12 to +12 semitones
  2. Low -> High Voice button
  3. High -> Low Voice button
5. Use Reset Voice Pitch to return to normal.

If your OBS build does not expose the pitch shift filter, the script will fail gracefully and keep everything else working.

## Recommended Filter Order (on webcam source)

If all features are enabled, keep this order from top to bottom:

1. CST Auto Color
2. CST Outline Sharpness
3. CST Glow A
4. CST Glow B
5. CST Strobe
6. CST Background Removal (if plugin available)
7. CST Silhouette Tint

The script will try to keep tint as the final style pass automatically.

## Background Removal Plugin Support

- The script auto-detects common background-removal filter IDs.
- If plugin is missing, the script continues safely and logs a warning.
- Threshold presets:
  - Soft
  - Balanced
  - Aggressive

## Notes on Diagnostics

- CPU/GPU values are best-effort estimates from OBS frame timing APIs.
- Audio diagnostics indicate whether true meter mode is active or fallback pulse mode is used.

## Stability and Safety

- Pure Lua, no external dependencies.
- Cross-platform (Windows/macOS/Linux).
- Defensive checks and graceful fallback paths.
- Hotkeys persist across OBS restarts.
- Source/filter references are properly released to avoid leaks.


## Guide for using
- Open OBS and load the script

Go to Tools -> Scripts.

Click + and select Multi-tool.lua.

Keep the Scripts window open so you can configure everything.

Pick your core sources

Webcam Source: your camera.

Audio Source: your mic (or mic + desktop audio source if you want strong beat reaction).

- Optional:

Media Source: music/video source for quick controls.
Chat Overlay Source: browser/text chat source you want to toggle.
Build a fun baseline look

- In Silhouette and Effects:

Color Preset: start with Electric Purple or Neon Green.
Opacity: 15 to 35 (recommended for transparent color overlays).
Enable Glow: on.
Enable Outline: on.
Enable Sound Reactive Pulse: on.
Enable Auto Color Cycle: on, set 6 to 10 seconds.
If you have background removal plugin installed:

Enable Background Removal: on.
Threshold Preset: Balanced first, then try Aggressive.
Make automation feel alive

- In Automation:

Enable Voice Activity Scene Switch: on.
Talking Scene: your camera-focused scene.
Waiting Scene: your BRB/idle scene.
Voice Threshold: around -35 dB to start.
Silence Delay: 3 to 5 seconds.
Optional motion trigger:

Enable Motion Trigger.
Pick Motion Trigger Source and Motion Scene.
Use the magic command box

In Natural Language Command Box, try:

make my silhouette electric purple and pulse to the beat
switch to gaming mode with green outline and chat overlay
cycle colors every 8 seconds and enable sound reactive glow
Click Apply Magic after each.

Add quick controls

Click Assign All Recommended Hotkeys.

Go to Settings -> Hotkeys.

Bind at least:

Cycle Color
Random Crazy Mode
Apply Magic
Toggle Chat Overlay
Health Check
Save reusable vibes

- In Presets, type a name like High Energy Friday or Chill Night.

Click Save Preset.

Create 2 to 4 moods so you can switch instantly during stream.

Final tune before going live

Click Health Check.

Watch OBS logs for any warnings.

If effect order looks odd play around with it till you get something you like.

If colors still feel too solid on your camera, reduce Opacity to 10 to 20.

Fun starter combo:

Preset: Gaming
Reactive: on
Cycle: on at 8s
Random Burst: on
Strobe: on only if you want high-energy moments and your audience is okay with flashes