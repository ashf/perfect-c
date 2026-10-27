# PerfectC

A macOS menu bar app that listens to your microphone and tells you when someone is singing a perfect C.

- `🎯 C`: within ±15 cents of a C, in any octave
- `🎤 D +12¢`: the nearest note, and how far sharp or flat you are
- `🎤 …`: silence, or nothing with a clear pitch

## Build and run

Requires the Xcode command line tools (`xcode-select --install`).

```sh
./build.sh
open PerfectC.app
```

Allow microphone access when macOS asks. To quit, click the menu bar item and choose Quit.

On first launch the app adds itself to your login items, so it starts when you log in. Untick **Launch at Login** in its menu to stop that. Login items point at the app's location, so move `PerfectC.app` to `/Applications` before the first launch if you don't want it tied to this folder.

## Self-test

```sh
swiftc main.swift -o /tmp/perfectc && /tmp/perfectc --selftest
```

Build without `-O` here, or the assertions get compiled out.
