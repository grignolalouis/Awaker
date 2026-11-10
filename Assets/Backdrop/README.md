# Backdrops

The user picks one in Settings. Each is a still and a loop made from it; the list is `Backdrop.scenes` in `Sources/Awaker/Backdrop/Backdrop.swift`.

- `<name>.jpg`: the still. Shown until the video's first frame, in the Settings picker, and instead of the video when Reduce Motion is on.
- `<name>.mp4`: the loop the app plays, made with `swift Scripts/make-loop.swift <name>-source.mp4 <name>.mp4 2.5 [bits per second]`
  (forward then backward, so it loops without a jump). The app plays it at 40 % speed to keep the scene calm, and computes the ASCII art from its frames. The blur (radius 2.5) is baked into the file, because blurring a playing layer live is expensive.
- `<name>-source.mp4`: the 5 s clip the loop was made from, generated with Higgsfield (Kling 3.0, start image only, no sound). Not in the app; only the first one is in the repository.

Where the pictures come from:

- `backdrop` ("Meadow"): an illustration used with its author's permission (confirmed by the app's owner), rotated to landscape.
- `beach`, `sunflowers`, `wheat`: original pictures generated with Higgsfield (GPT Image) from a text description, all with the same
  style prompt ("hand-painted anime film background art, gouache and soft visible brushwork…") so they belong together.
  The owner supplied three reference pictures for the subjects; they were not used as inputs, since their rights were unknown.

Giving the video model the same image as start and end frame produces an almost static clip: use a start image only.
