---
title: Project v1
---

## Overview

Project v1 is a project container with a stable project id, an asset table, settings, and typed timeline tracks. Timeline clips refer to asset ids instead of repeating media paths. Auto-Editor resolves project-relative asset URIs, translates the supported timeline subset to its existing v3 timeline, then uses the normal render path.

This is distinct from timeline v1/v2/v3. Existing timeline JSON files continue to use their `version` field and are imported unchanged.

## Project JSON

```json
{
  "schemaVersion": 1,
  "projectId": "weekly-example",
  "settings": {
    "width": 1920,
    "height": 1080,
    "fps": { "num": 30, "den": 1 },
    "samplerate": 48000,
    "layout": "stereo",
    "background": "#000"
  },
  "assets": [
    { "id": "main-video", "uri": "assets/media/main.mp4" },
    { "id": "voiceover", "uri": "assets/media/voice.wav" }
  ],
  "timeline": {
    "tracks": [
      {
        "id": "picture",
        "kind": "video",
        "clips": [
          {
            "assetId": "main-video",
            "startFrame": 0,
            "durationFrames": 300,
            "sourceInFrame": 0,
            "stream": 0,
            "effects": []
          }
        ]
      },
      {
        "id": "narration",
        "kind": "audio",
        "clips": [
          {
            "assetId": "voiceover",
            "startFrame": 0,
            "durationFrames": 300,
            "sourceInFrame": 0,
            "stream": 0
          }
        ]
      }
    ],
    "transitions": [
      {
        "trackId": "picture",
        "kind": "dissolve",
        "atFrame": 149,
        "durationFrames": 30,
        "alignment": "center"
      }
    ]
  }
}
```

Load it through the regular CLI input path:

```sh
auto-editor my-project/project.json -o output.mp4
```

`settings.fps` is a rational frame rate. Clip start, duration, source in-point, and transition timing are integer frames in that timebase. Tracks are `video` or `audio`; still images and rendered alpha overlays use video tracks. `language` is optional on a track and defaults to `und`. `sourceInFrame` and `stream` default to zero. `samplerate`, `layout`, and `background` default to 48000, `stereo`, and `#000`.

`tracks` array order is semantic: video tracks are composited bottom-to-top in that order, while audio tracks retain their declared order. Each asset id must be unique and every clip's `assetId` must exist. Asset `uri` values are relative to the directory containing `project.json`; absolute paths and `..` path components are rejected. The initial importer supports existing Auto-Editor action strings in `effects` and `dissolve` transitions.

## Current Scope

The importer currently compiles Project JSON into the existing v3 timeline model. It does not yet save/edit Project JSON, migrate project schema versions, or implement datasets, templates, subtitles, text/shape clips, or project export. Complex HTML/CSS/GSAP scenes should first be rendered by the separate `@hyperframes/producer` adapter and referenced as video assets.

For timeline-only interchange formats, see [v1](./v1.md), [v2](./v2.md), and [v3](./v3.md).
