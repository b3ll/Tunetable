# Turntable.fm

A simple app that lets you stream your vinyl records over AirPlay using an iPhone or iPad.

It also has the neat feature of automatically matching the song played with Shazam and updating Now Playing accordingly.

## Why'd you call it Turntable.fm?

It was mostly a personal joke since I originally had my records streaming throughout my house using Icecast + DarkIce, which is effectively spinning up my own radiostation, but that didn't work as well so I made this app and called it Turntable.fm.

The name probably won't stick, so I'm open to other ideas, RecordPlay / VinylPlay / AirLP, etc. sounded not so great 🙃

# Installation

## Requirements

- iOS 15+
- Swift 5.0 or higher
- An iPhone or iPad running iOS 15 or later (didn't test anything prior).
- A usb audio interface that works with iOS (you'll want a camera connection kit). I'm currently using [this one](https://www.behringer.com/behringer/product?modelCode=P0A12).

## Usage

It'll be published on the App Store at some point, but for now, you'll have to build and run yourself.

**Note**: Be sure to register the appropriate App ID and give it the Shazam entitlement so it can use ShazamKit properly.

1. Connect your turntable to the audio interface
2. Connect the audio interface to your iOS device
3. Open the app, pick your AirPlay destinations
4. Drop the needle and then you're good to go!

# TODO

- Figure out why setting a samplerate higher than 441000hz doesn't work, though this is probably useless since AirPlay streams at 44100hz anyways.
- Add an icon.
- Filter out garbage audio data / make stream more reliable. For some reason you'll get a second of crackly audio sporadically, I still have no idea why this happens, it's just dumping whatever's coming in to AirPlay with barely any CPU usage.
- Deal with "arbitrary" rate limits for ShazamKit

# License

Turntable.fm is licensed under the [BSD 2-clause license](https://github.com/b3ll/Turntable.fm/blob/main/LICENSE).

Please don't just re-package this up and sell it, it's meant to be free.

# Contact Info

If you have any questions, or want to learn more, feel free to ask me anything!

Feel free to follow me on twitter: [@b3ll](https://www.twitter.com/b3ll)!
