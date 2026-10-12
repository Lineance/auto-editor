import std/[json, os, strformat, strutils, tables]

import ../log

proc requiredObject(node: JsonNode, field: string): JsonNode {.raises: [AutoEditorError].} =
  result = node{field}
  if result == nil or result.kind != JObject:
    error &"Expected '{field}' to be an object"

proc requiredArray(node: JsonNode, field: string): JsonNode {.raises: [AutoEditorError].} =
  result = node{field}
  if result == nil or result.kind != JArray:
    error &"Expected '{field}' to be an array"

proc requiredString(node: JsonNode, field: string): string {.raises: [AutoEditorError].} =
  let value = node{field}
  if value == nil or value.kind != JString or value.getStr() == "":
    error &"Expected '{field}' to be a non-empty string"
  value.getStr()

proc requiredInt(node: JsonNode, field: string): int64 {.raises: [AutoEditorError].} =
  let value = node{field}
  if value == nil or value.kind != JInt:
    error &"Expected '{field}' to be an integer"
  value.getBiggestInt()

proc resolveAssetUri(uri, projectDir: string): string {.raises: [AutoEditorError].} =
  if uri == "" or isAbsolute(uri):
    error "Project asset URI must be a non-empty relative path"
  for part in uri.split({'/', '\\'}):
    if part == "..":
      error "Project asset URI cannot escape the project directory"
  let root = if projectDir == "": "." else: projectDir
  try:
    absolutePath(root / uri)
  except OSError as e:
    error &"Invalid Project asset URI '{uri}': {e.msg}"
  except ValueError as e:
    error &"Invalid Project asset URI '{uri}': {e.msg}"

proc projectToV3Json*(project: JsonNode, projectDir: string): JsonNode
    {.raises: [AutoEditorError].} =
  if project.kind != JObject:
    error "Project JSON must be an object"
  if project{"schemaVersion"}.getInt(-1) != 1:
    error "Unsupported Project schemaVersion"
  discard project.requiredString("projectId")

  let settings = project.requiredObject("settings")
  let width = settings.requiredInt("width")
  let height = settings.requiredInt("height")
  if width < 2 or height < 2 or width > high(int32).int64 or
      height > high(int32).int64 or ((width or height) and 1) != 0:
    error "Project resolution must be even and >= 2"

  let fps = settings.requiredObject("fps")
  let fpsNum = fps.requiredInt("num")
  let fpsDen = fps.requiredInt("den")
  if fpsNum <= 0 or fpsDen <= 0:
    error "Project fps numerator and denominator must be positive"

  let assetsNode = project.requiredArray("assets")
  var assets = initTable[string, string]()
  for asset in assetsNode:
    if asset.kind != JObject:
      error "Project assets must be objects"
    let id = asset.requiredString("id")
    let uri = asset.requiredString("uri")
    if assets.hasKey(id):
      error &"Duplicate Project asset id: {id}"
    assets[id] = resolveAssetUri(uri, projectDir)

  let timeline = project.requiredObject("timeline")
  let tracks = timeline.requiredArray("tracks")
  var trackIds = initTable[string, tuple[kind: string, index: int]]()
  var videoTracks = newJArray()
  var audioTracks = newJArray()
  var videoTrackIds: seq[string]
  var audioTrackIds: seq[string]
  var videoLangs: seq[string]
  var audioLangs: seq[string]

  for track in tracks:
    if track.kind != JObject:
      error "Project tracks must be objects"
    let trackId = track.requiredString("id")
    let kind = track.requiredString("kind")
    if trackIds.hasKey(trackId):
      error &"Duplicate Project track id: {trackId}"
    if kind notin ["video", "audio"]:
      error &"Unsupported Project track kind: {kind}"

    let clipsNode = track.requiredArray("clips")
    if clipsNode.len == 0:
      error &"Project track '{trackId}' must contain at least one clip"
    var clips = newJArray()
    for clip in clipsNode:
      if clip.kind != JObject:
        error "Project clips must be objects"
      let assetId = clip.requiredString("assetId")
      if not assets.hasKey(assetId):
        error &"Unknown Project asset id: {assetId}"

      let start = clip.requiredInt("startFrame")
      let duration = clip.requiredInt("durationFrames")
      let sourceInNode = clip{"sourceInFrame"}
      let sourceIn = if sourceInNode == nil: 0'i64 else:
        if sourceInNode.kind != JInt: error "Expected 'sourceInFrame' to be an integer"
        sourceInNode.getBiggestInt()
      let streamNode = clip{"stream"}
      let stream = if streamNode == nil: 0 else:
        if streamNode.kind != JInt: error "Expected 'stream' to be an integer"
        streamNode.getInt()
      if start < 0 or duration <= 0 or sourceIn < 0 or stream < 0 or stream > 1000:
        error "Invalid Project clip timing or stream"

      var clipJson = %*{
        "src": assets.getOrDefault(assetId),
        "start": start,
        "dur": duration,
        "offset": sourceIn,
        "stream": stream
      }
      let effectsNode = clip{"effects"}
      if effectsNode != nil:
        if effectsNode.kind != JArray:
          error "Project clip effects must be an array"
        for effect in effectsNode:
          if effect.kind != JString:
            error "Project clip effects must contain strings"
        clipJson["effects"] = effectsNode
      clips.add(clipJson)

    let languageNode = track{"language"}
    let language = if languageNode == nil: "und" else:
      if languageNode.kind != JString: error "Track language must be a string"
      languageNode.getStr()
    if kind == "video":
      trackIds[trackId] = (kind, videoTracks.len)
      videoTrackIds.add(trackId)
      videoLangs.add(language)
      videoTracks.add(clips)
    else:
      trackIds[trackId] = (kind, audioTracks.len)
      audioTrackIds.add(trackId)
      audioLangs.add(language)
      audioTracks.add(clips)

  let samplerateNode = settings{"samplerate"}
  let samplerate = if samplerateNode == nil: 48000 else:
    if samplerateNode.kind != JInt: error "Project samplerate must be an integer"
    samplerateNode.getInt()
  if samplerate < 100 or samplerate > high(cint).int:
    error "Project samplerate must be in the supported range"

  let layoutNode = settings{"layout"}
  let layout = if layoutNode == nil: "stereo" else:
    if layoutNode.kind != JString: error "Project layout must be a string"
    layoutNode.getStr()
  let backgroundNode = settings{"background"}
  let background = if backgroundNode == nil: "#000" else:
    if backgroundNode.kind != JString: error "Project background must be a string"
    backgroundNode.getStr()

  result = %*{
    "version": "3",
    "timebase": &"{fpsNum}/{fpsDen}",
    "background": background,
    "resolution": [width, height],
    "samplerate": samplerate,
    "layout": layout,
    "langs": videoLangs & audioLangs,
    "v": videoTracks,
    "a": audioTracks
  }
  if timeline{"transitions"} != nil:
    let transitionsNode = timeline.requiredArray("transitions")
    var videoTransitions = newJArray()
    var audioTransitions = newJArray()
    for _ in videoTrackIds: videoTransitions.add(newJArray())
    for _ in audioTrackIds: audioTransitions.add(newJArray())
    for transition in transitionsNode:
      if transition.kind != JObject:
        error "Project transitions must be objects"
      let trackId = transition.requiredString("trackId")
      if not trackIds.hasKey(trackId):
        error &"Unknown Project track id in transition: {trackId}"
      let trackRef = trackIds.getOrDefault(trackId)
      let kind = transition.requiredString("kind")
      if kind != "dissolve": error &"Unsupported Project transition kind: {kind}"
      let at = transition.requiredInt("atFrame")
      let duration = transition.requiredInt("durationFrames")
      if at < 0 or duration <= 0:
        error "Invalid Project transition timing"
      let alignmentNode = transition{"alignment"}
      let alignment = if alignmentNode == nil: "center" else:
        if alignmentNode.kind != JString: error "Transition alignment must be a string"
        alignmentNode.getStr()
      if alignment notin ["start", "center", "end"]:
        error "Invalid Project transition alignment"
      let transitionJson = %*{
        "kind": kind,
        "at": at,
        "dur": duration,
        "alignment": alignment
      }
      if trackRef.kind == "video":
        videoTransitions[trackRef.index].add(transitionJson)
      else:
        audioTransitions[trackRef.index].add(transitionJson)
    result["transitions"] = %*{"v": videoTransitions, "a": audioTransitions}