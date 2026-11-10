<p align="center">
  <img src="Assets/banner.png" alt="Awaker" width="800">
</p>

Awaker keeps your Mac awake with the lid closed, and shows what your Claude Code agents are doing.
Start a task, close the lid, the work goes on.

## Install

Requires an Apple Silicon Mac on macOS 26.

1. Download `Awaker.dmg` from the [latest release](https://github.com/grignolalouis/Awaker/releases/latest) and drag Awaker to Applications.
2. On first launch, allow it in System Settings > Privacy & Security > "Open Anyway". The app isn't signed with an Apple developer account.
3. In Awaker, click "Install authorization…" and enter your password.

Awaker then updates itself from Settings.

## Develop

```sh
Scripts/build.sh --install    # build and install
Scripts/test.sh               # run the tests
```

To release, change the number in `VERSION` and push to `main`.
