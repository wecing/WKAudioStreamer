### First of all

This is still an on-going project; it doesn't support seeking yet. Also it's not tested enough.

---

### About WKAudioStreamer

I know you have no idea how Cocoa's Audio File Stream Services and Audio Queue Services work -- no problem! You can avoid getting your hands dirty by using WKAudioStreamer.

(PS: This project is inspired by [Matt Gallagher](http://www.cocoawithlove.com/2010/03/streaming-mp3aac-audio-again.html)'s [AudioStreamer](https://github.com/mattgallagher/AudioStreamer). I read his code to learn how to use Audio File Stream Services and Audio Queue Services, but rewrote everything independently.)

#### So, what does WKAudioStreamer do?

WKAudioStreamer assumes the files you ask it to stream are audio files; it allows you to control the process of both streaming and playing. You can stream files in background, and play them when necessary. Doing both in the same time is also ok.

This class is contributed to fixed-width audio files encoded in formats supported by Cocoa.

#### Sounds great. How can I get started?

I'm trying to provide as less APIs as possible. See WKAudioStreamer.h for the APIs. Fetch the whole project to see a fully functioning example.

To use WKAudioStreamer, Just copy WKAudioStreamer.[hm] into your source tree.

#### Anything else?

My code is under public domain. Maybe one day I will licence it under WTFPL.