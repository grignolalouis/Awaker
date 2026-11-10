# Backdrop

- `backdrop.jpg`: illustration used with its author's permission (confirmed by the app's owner), rotated to landscape.
  Shown until the video's first frame, and instead of the video when Reduce Motion is on.
- `backdrop-source.mp4`: 5 s animation of that illustration, generated with Higgsfield (Kling 3.0, start image only).
- `backdrop.mp4`: the loop the app plays, made from the source with `swift Scripts/make-loop.swift backdrop-source.mp4 backdrop.mp4 2.5`
  (forward then backward, so it loops without a jump). The app plays it at 40 % speed to keep the scene calm, and computes the ASCII art from its frames. The blur (radius 2.5) is baked into the file, because blurring a playing layer live is expensive.

Giving the model the same image as start and end frame produces an almost static clip: use a start image only.
