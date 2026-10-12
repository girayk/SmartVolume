# SmartVolume

Use your Mac's volume keys to control the speakers of a Samsung Smart Monitor (tested on the M7) connected over USB-C, HDMI or DisplayPort.

macOS can't change the volume of a monitor's speakers, and Samsung Smart Monitors ignore the usual monitor control commands (DDC/CI). SmartVolume talks to the monitor over your network instead, the same way Samsung's phone remote app does. When the monitor is your sound output, Volume Up, Volume Down and Mute change the monitor's own volume. When it isn't, or the monitor can't be reached, SmartVolume steps aside and your Mac's normal volume control works as usual.

## Install

SmartVolume is free on the Mac App Store.

## Setup

1. Allow Input Monitoring when asked, so SmartVolume can see the volume keys.
2. Pick your monitor from the list, or enter its IP address. The Mac and monitor must be on the same network.
3. Press **Allow** on the monitor's screen.
4. Select the monitor as your sound output and press a volume key.
5. Choose where SmartVolume lives: the Dock, the menu bar, or fully in the background. In Background mode, open SmartVolume again from Applications or Spotlight to see Settings.

macOS still shows its own grey volume overlay when you press a key, because App Store apps can't stop macOS from handling the volume keys. The monitor's volume is what changes.

## Develop

Open `SmartVolume.xcodeproj` in Xcode 16 or later. Run with ⌘R and test with ⌘U.

- `SmartVolume/` holds the app code, icon, Info.plist and entitlements.
- `SmartVolumeTests/` holds the unit tests.

## Release

1. Set the version and build number under the SmartVolume target's **General** tab.
2. Choose **Product > Archive**, then **Distribute App > App Store Connect**.
3. In App Store Connect, add the build to the version and submit it for review.

## Support

Report problems or ask questions in [Issues](https://github.com/girayk/SmartVolume/issues). See the [Privacy Policy](PRIVACY.md).

## License

MIT
