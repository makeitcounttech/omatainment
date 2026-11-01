import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// OmaTainment playback service: owns the YouTube and Movies/Series players and their
// floating windows. The shell keeps keepLoaded services alive across plugin hot
// reloads (a save in ANY local plugin reloads every bar widget), so video keeps
// playing while the bar widget is rebuilt. The bar widget finds this object with
// bar.shell.serviceFor("empire.omatainment") and only renders views onto these engines.
// A real shell restart still ends the process; the per-lane session file then
// resumes playback at the same second (see VideoEngine.restoreSession).
Item {
  id: service

  property var shell: null
  property var manifest: null

  readonly property string backendPath: Qt.resolvedUrl("oma-player").toString().replace(/^file:\/\//, "")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omatainment"

  // Lanes are created on first use (or straight away when a saved session exists).
  property bool videoLoaded: false
  property bool cinemaLoaded: false
  readonly property var video: videoEngine.item
  readonly property var cinema: cinemaEngine.item

  function load(lane) {
    if (lane === "video") videoLoaded = true
    else if (lane === "cinema") cinemaLoaded = true
  }

  // A session saved before a shell restart loads its engine at once, so the video
  // (and its floating window) comes back without opening the panel.
  FileView {
    id: videoSessionProbe
    path: service.stateDir + "/video-session.json"
    blockLoading: true
    printErrors: false
    Component.onCompleted: {
      try { if (JSON.parse(text() || "{}").url) service.videoLoaded = true } catch (e) {}
    }
  }
  FileView {
    id: cinemaSessionProbe
    path: service.stateDir + "/cinema-session.json"
    blockLoading: true
    printErrors: false
    Component.onCompleted: {
      try { if (JSON.parse(text() || "{}").url) service.cinemaLoaded = true } catch (e) {}
      // One-time migration: a Remux title saved by the old single engine moves to the cinema lane.
      try {
        var old = JSON.parse(videoSessionProbe.text() || "{}")
        if (old.url && old.url.indexOf("remux:") === 0) {
          setText(videoSessionProbe.text()); videoSessionProbe.setText("{}"); service.cinemaLoaded = true
        }
      } catch (e) {}
    }
  }

  // YouTube lane
  Loader {
    id: videoEngine
    active: service.videoLoaded
    source: "VideoEngine.qml"
    onLoaded: {
      item.sessionName = "video"
      item.backendPath = service.backendPath
    }
  }

  // Movies / Series lane (Remux) — separate player, can run alongside YouTube and music.
  Loader {
    id: cinemaEngine
    active: service.cinemaLoaded
    source: "VideoEngine.qml"
    onLoaded: {
      item.sessionName = "cinema"
      item.backendPath = service.backendPath
    }
  }

  // ---- Remote control of the YouTube (video) and Movies/Series (cinema) lanes -------------
  // omarchy-shell omatainment-lanes <method> <lane> [value]   (used by fold-link for the phone)
  // Every call returns a short text: "ok", or "error: <reason>"; state() returns JSON.
  function engineFor(lane) {
    if (lane === "video") return videoEngine.item
    if (lane === "cinema") return cinemaEngine.item
    return null
  }
  function laneState(lane) {
    var e = engineFor(lane)
    var s = { loaded: e !== null, hasVideo: false, playing: false, buffering: false, title: "", subtitle: "",
              url: "", kind: "", position: 0, duration: 0, volume: 0, muted: false, seekable: false,
              floating: false, fullscreen: false, hasNext: false, nextTitle: "", error: "" }
    if (!e) return s
    s.hasVideo = e.hasVideo
    s.playing = e.playing
    s.buffering = e.buffering
    s.title = e.videoTitle || ""
    s.subtitle = e.videoArtist || ""
    s.url = e.videoUrl || ""
    s.kind = e.mediaType || ""
    s.position = Math.max(0, Math.round(e.positionSec * 10) / 10)
    s.duration = Math.max(0, Math.round(e.durationSec * 10) / 10)
    s.volume = Math.round(e.audio.volume * 100)
    s.muted = e.audio.muted === true
    s.seekable = e.player.seekable === true
    s.floating = e.floating === true
    s.fullscreen = e.fullscreen === true
    s.hasNext = e.nextEpisode !== null && e.nextEpisode !== undefined
    s.nextTitle = s.hasNext ? ((e.nextEpisode.artist || e.nextEpisode.title) || "") : ""
    s.error = e.errorText || ""
    return s
  }
  function laneCall(lane, fn) {
    if (lane !== "video" && lane !== "cinema") return "error: lane must be video|cinema"
    var e = engineFor(lane)
    if (!e || !e.hasVideo) return "error: nothing loaded in this lane"
    var r = fn(e)
    return typeof r === "string" ? r : "ok"
  }

  IpcHandler {
    target: "omatainment-lanes"
    function state(): string { return JSON.stringify({ video: service.laneState("video"), cinema: service.laneState("cinema") }) }
    function play(lane: string): string { return service.laneCall(lane, function(e) { e.play() }) }
    function pause(lane: string): string { return service.laneCall(lane, function(e) { e.pause() }) }
    function toggle(lane: string): string { return service.laneCall(lane, function(e) { e.togglePlay() }) }
    function seek(lane: string, seconds: real): string {
      return service.laneCall(lane, function(e) {
        if (!isFinite(seconds) || seconds < 0) return "error: bad position"
        if (!e.player.seekable) return "error: not seekable"
        e.seek(seconds)
      })
    }
    function skip(lane: string, seconds: real): string {
      return service.laneCall(lane, function(e) {
        if (!isFinite(seconds) || Math.abs(seconds) > 3600) return "error: bad skip"
        if (!e.player.seekable) return "error: not seekable"
        e.skip(seconds)
      })
    }
    function volume(lane: string, percent: real): string {
      return service.laneCall(lane, function(e) {
        if (!isFinite(percent) || percent < 0 || percent > 100) return "error: volume must be 0-100"
        e.setVolume(percent / 100)
      })
    }
    function stop(lane: string): string { return service.laneCall(lane, function(e) { e.stopVideo() }) }
    function fullscreen(lane: string): string { return service.laneCall(lane, function(e) { e.toggleFullscreen() }) }
    // Float: docked -> corner window; fullscreen -> corner window; corner window -> back into the panel view.
    function float(lane: string): string {
      return service.laneCall(lane, function(e) {
        if (e.fullscreen) { e.fullscreenFromPanel = false; e.exitFullscreen(); if (!e.floating) e.popOut() }
        else if (e.floating) e.dock()
        else e.popOut()
      })
    }
    function next(lane: string): string {
      return service.laneCall(lane, function(e) {
        if (!e.nextEpisode) return "error: no next episode"
        e.playVideo(e.nextEpisode)
      })
    }
    // YouTube -> NewPipe at the same second; Movies/Series -> Moonfin (the engine picks by lane content).
    function toPhone(lane: string): string { return service.laneCall(lane, function(e) { e.sendToPhone() }) }
  }

  Loader {
    active: videoEngine.item !== null && videoEngine.item.floating
    sourceComponent: VideoFloat {
      engine: videoEngine.item
      windowTitle: "OmaTainment Video"
      accent: Color.accent
      fontFamily: Style.font.family
    }
  }

  Loader {
    active: cinemaEngine.item !== null && cinemaEngine.item.floating
    sourceComponent: VideoFloat {
      engine: cinemaEngine.item
      windowTitle: "OmaTainment Cinema"
      accent: Color.accent
      fontFamily: Style.font.family
    }
  }
}
