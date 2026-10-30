# Kind Mirror — desktop camera

A native macOS window: choose a camera, then click **Take picture & compliment**. No browser or web server needed. Pictures are kept in memory and sent only to Ollama on your own machine.

## Open

Double-click `build/Kind Mirror.app`, or run:

```sh
open "build/Kind Mirror.app"
```

Allow camera access when macOS asks. Keep Ollama running. The app discovers installed Gemma 3 models; choose a vision-capable model (`gemma3:latest` on this machine). Gemma 3 1B and 270M cannot read photos.

## Build again

Requires macOS and the Xcode command line tools:

```sh
./native/build.sh
```

The preview and Ollama request run separately so generation doesn't block the camera. Snapshots have a maximum edge of 384 pixels and replies are capped at 60 tokens. Gemma stays loaded for five minutes to avoid repeated model loading; this uses memory between requests. Image inference itself still depends on your hardware and model size.

Closing the window stops the camera and exits. No photos are saved. Camera permission can be changed in System Settings → Privacy & Security → Camera.

The earlier browser prototype remains in `public/` and `server.js`, but isn't used by the desktop app. `npm start` now opens the desktop app (run `./native/build.sh` first).
