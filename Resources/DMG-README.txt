Sunrise — beta
==============

A sunrise alarm for macOS: the window is a lava lamp whose brightness is the alarm light.

Install
-------
1. Drag Sunrise into Applications and open it.
2. Only if macOS says it can't verify the app (unsigned test builds), run once:

       xattr -dr com.apple.quarantine /Applications/Sunrise.app

Requires macOS 14+. Universal: Apple Silicon and Intel.

Try it
------
- The main screen is a list of alarms: + adds one, click one to edit it.
  "Go to sleep" puts the Mac into night mode (dark screen, pill in the corner).
  Stop brings you back to the list at full light; the alarm stays on for its next day.
- Debug → Ring Now (⌘R): a 10-second sunrise, no need to wait for the alarm.
- Preview button (in the alarm editor): 8-second sunrise demo.
- View → palettes (Ember / Aurora / Glacier), Max Brightness at Sunrise, Dim Screen While Armed.
- Spotify row → paste a playlist/album/track link (or leave empty). Needs the Spotify desktop app;
  macOS asks once for permission to control it. Music starts at volume 0 and fades up to 75
  with the light.

Things to know (it's a beta)
----------------------------
- Alarms ring only while the app is running and the lid is open; closing the window just hides it.
  Use "Go to sleep" at night: outside night mode the screen may lock, and the alarm window
  can't show above the lock screen.
- It drives the screen backlight (private DisplayServices API): down to 1/16 while armed and
  in front, up to 100% during the sunrise, back to your level otherwise. If the app crashes,
  your level is restored on the next launch.
- If the Mac is muted or below 50% volume, it's raised to 50% while the alarm rings.

Settings live in UserDefaults (com.stvl.sunrise). To reset:

    defaults delete com.stvl.sunrise
