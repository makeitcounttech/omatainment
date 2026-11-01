import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// Persistent OmaTainment video engine. Lives in the always-loaded bar widget, so playback
// survives the popup closing. The popup and the floating window are only views: they
// register a VideoOutput and the single MediaPlayer renders into whichever is active.
Item {
  id: engine

  property string backendPath: ""
  readonly property string videoBackendPath: backendPath.replace(/oma-player$/, "oma-video")
  readonly property string remuxBackendPath: backendPath.replace(/oma-player$/, "oma-remux")

  // Remux (movies/series) playback state: progress goes to Remux, not the YouTube history.
  readonly property bool isRemux: videoUrl.indexOf("remux:") === 0
  property string mediaType: ""          // "movie" | "episode" | "" (YouTube)
  property string mediaSourceId: ""
  property string playSessionId: ""
  property string quality: ""
  // Maximum stream resolution for Movies/Series (oma-remux pref streamQuality).
  property int maxQuality: 1080
  readonly property var qualityOptions: [720, 1080, 1440, 2160]
  function qualityName(q) { return q === 2160 ? "4K" : q === 1440 ? "2K" : q + "p" }
  // Change the cap; a playing Remux title reloads at the new quality and resumes in place.
  function setQuality(q) {
    if (qualityOptions.indexOf(q) < 0) return
    maxQuality = q
    qualityProc.exec([remuxBackendPath, "quality", String(q)])
    if (!isRemux || !hasVideo || resolving) return
    var at = positionSec, wasPlaying = playing
    if (player.duration > 0) remuxReport("stopped")
    player.stop()
    player.source = ""
    remuxStarted = false
    restoreResume = Math.max(0, Math.floor(at))
    restoreAutoplay = wasPlaying
    resolving = true
    notice = "Switching to " + qualityName(q) + "…"
    run(resolveProc, [remuxBackendPath, "resolve", videoUrl])
  }
  property string poster: ""
  property string backdrop: ""
  property bool remuxStarted: false
  property bool autoNext: true
  property var nextEpisode: null
  // Sources for the current Remux title (from oma-remux resolve/sources): [{id,label,provider,bad,...}]
  property var sourceList: []
  property bool switchingSource: false
  // The title's real runtime from Remux (seconds). The player's own duration can be a 2-minute
  // AIOStreams status clip ("being downloaded to your debrid"), so decisions use this one.
  property real expectedRuntime: 0
  readonly property bool placeholderPlaying: isRemux && expectedRuntime > 600 && durationSec > 0 && durationSec < 200
  // Set when autoplay moved on to the next episode: one tap goes back to where it was.
  property var previousEpisode: null
  // Where the current stream was meant to start (resume point); survives a placeholder that ate the seek.
  property real intendedStart: 0
  signal remuxProgressSaved()

  // Video sinks registered by the views.
  property var panelOutput: null
  property var floatOutput: null
  property bool floating: false

  // Current video
  property string videoId: ""
  property string videoUrl: ""
  property string videoTitle: ""
  property string videoArtist: ""
  property real pendingResume: 0
  property bool resolving: false
  property string errorText: ""
  // Stream recovery: a dropped connection (demux I/O error, or a false "end" long before the
  // real end) re-resolves the title and resumes at the same second. Bounded retries.
  property int recoverAttempts: 0
  property real lastGoodPosition: 0
  function recoverStream(reason, skipSource) {
    if (!hasVideo || resolving || recoverAttempts >= 4) return false
    recoverAttempts++
    var at = placeholderPlaying ? Math.max(lastGoodPosition, intendedStart)
                                : Math.max(lastGoodPosition, positionSec, pendingResume)
    var url = videoUrl, wasRemux = isRemux
    // Same source failed twice (or played a placeholder): let the backend pick another one.
    var skip = wasRemux && mediaSourceId && (skipSource || recoverAttempts >= 2) ? mediaSourceId : ""
    if (wasRemux && player.duration > 0 && !placeholderPlaying) remuxReport("progress")
    player.stop()
    player.source = ""
    if (wasRemux) remuxStarted = false
    restoreResume = Math.max(0, Math.floor(at) - 2)
    restoreAutoplay = true
    resolving = true
    errorText = ""
    notice = skip ? "That source isn't ready — trying another…"
               : "Connection dropped — reconnecting at " + formatTime(at) + "…"
    var args = [wasRemux ? remuxBackendPath : videoBackendPath, "resolve", url]
    if (skip) args = args.concat(["", "--skip", skip])
    run(resolveProc, args)
    return true
  }
  // Pick a specific source from the in-player list. The current stream keeps playing until the
  // new one is confirmed playable; a refused pick only shows a notice.
  function switchSource(id) {
    if (!isRemux || !id || switchingSource) return
    if (resolving && errorText === "") return
    if (id === mediaSourceId) return
    switchingSource = true
    notice = "Checking that source…"
    run(switchProc, [remuxBackendPath, "resolve", videoUrl, id])
  }
  function refreshSources() {
    if (isRemux && !sourcesProc.running) run(sourcesProc, [remuxBackendPath, "sources", videoUrl])
  }
  function goBackEpisode() {
    var prev = previousEpisode
    if (!prev) return
    unplayedProc.exec([remuxBackendPath, "unplayed", prev.url])
    playVideoAt(prev, prev.position || 0)
  }
  // Recovery triggered from the player's own signals must run after the handler returns:
  // stopping/re-sourcing the FFmpeg backend inside mediaStatusChanged/durationChanged crashes it.
  property string pendingRecoverReason: ""
  property bool pendingRecoverSkip: false
  function recoverLater(reason, skipSource) {
    if (pendingRecoverReason !== "") { pendingRecoverSkip = pendingRecoverSkip || !!skipSource; return }
    pendingRecoverReason = reason
    pendingRecoverSkip = !!skipSource
    recoverTimer.restart()
  }
  Timer {
    id: recoverTimer
    interval: 0
    onTriggered: {
      var reason = engine.pendingRecoverReason, skip = engine.pendingRecoverSkip
      engine.pendingRecoverReason = ""
      engine.pendingRecoverSkip = false
      if (reason === "placeholder" && !engine.placeholderPlaying) return
      if (!engine.recoverStream(reason, skip) && reason !== "placeholder") {
        engine.errorText = engine.errorText || "Playback stopped — pick another source"
        engine.resolving = false
        engine.refreshSources()
      }
    }
  }
  // Stuck buffering (debrid/proxy stopped sending): reconnect instead of spinning forever.
  Timer {
    id: stallWatch
    interval: 25000
    running: engine.hasVideo && !engine.resolving && player.playbackState === MediaPlayer.PlayingState
      && (player.mediaStatus === MediaPlayer.StalledMedia || player.mediaStatus === MediaPlayer.BufferingMedia
          || player.mediaStatus === MediaPlayer.LoadingMedia)
    onTriggered: engine.recoverStream("stalled", player.position <= 0)
  }
  Timer {
    // Healthy playback for a while resets the retry budget and remembers the spot.
    interval: 4000; repeat: true; running: engine.playing
    onTriggered: {
      if (player.position > 0 && !engine.placeholderPlaying) engine.lastGoodPosition = player.position / 1000
      if (player.mediaStatus === MediaPlayer.BufferedMedia) engine.recoverAttempts = Math.max(0, engine.recoverAttempts - 1)
    }
  }
  // Remux titles that turned out to have no streams (hidden from lists this session).
  property var deadIds: ({})
  signal noStreams(string id)
  property string notice: ""

  // Lists
  property var results: []
  property bool searching: false
  property string lastQuery: ""
  property var history: []

  readonly property alias player: player
  readonly property alias audio: audioOut
  readonly property bool hasVideo: videoUrl !== ""
  readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
  readonly property real positionSec: player.position / 1000
  readonly property real durationSec: player.duration / 1000
  readonly property bool buffering: resolving || player.mediaStatus === MediaPlayer.LoadingMedia
    || player.mediaStatus === MediaPlayer.BufferingMedia || player.mediaStatus === MediaPlayer.StalledMedia

  signal videoStarted()

  // ---- Survive a Quickshell restart / plugin hot reload --------------------------
  // The MediaPlayer lives inside the shell and dies with it, so a tiny session file
  // remembers what was on screen; the next engine resumes it (same position, same
  // floating window and geometry). Music needs none of this: it is an external mpv.
  // One engine per lane ("video" = YouTube, "cinema" = Movies/Series) so both can run at once.
  property string sessionName: "video"
  readonly property string sessionPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omatainment/" + sessionName + "-session.json"
  readonly property int sessionMaxAgeMs: 12 * 3600 * 1000
  property var floatGeometry: null      // {x, y, w, h} of the floating window, global px
  property bool restoreAutoplay: true   // false: restored video is cued but stays paused
  property bool restoring: false

  // Debounced: a save requested while the shell is tearing down (the player stopping
  // fires playingChanged) dies with the timer and never overwrites the session.
  function saveSession() { if (!restoring) sessionSaveTimer.restart() }

  function writeSession() {
    if (restoring) return
    if (!hasVideo) { sessionFile.setText("{}"); return }
    sessionFile.setText(JSON.stringify({
      url: videoUrl, id: videoId, title: videoTitle, artist: videoArtist,
      position: player.duration > 0 ? positionSec : pendingResume,
      playing: playing || resolving, floating: floating,
      floatGeometry: floatGeometry, saved_at: Date.now()
    }))
  }

  function clearSession() { if (!restoring) sessionFile.setText("{}") }

  function restoreSession() {
    var saved
    try { saved = JSON.parse(sessionFile.text() || "{}") } catch (e) { return }
    if (!saved || !saved.url || !backendPath) return
    if (!saved.saved_at || Date.now() - saved.saved_at > sessionMaxAgeMs) { clearSession(); return }
    restoring = true
    floatGeometry = saved.floatGeometry || null
    restoreAutoplay = saved.playing === true
    playVideo({ url: saved.url, id: saved.id, title: saved.title, artist: saved.artist })
    restoreResume = Math.max(0, Number(saved.position) || 0)
    floating = saved.floating === true
    restoring = false
  }
  property real restoreResume: -1

  Timer { id: sessionSaveTimer; interval: 400; onTriggered: engine.writeSession() }

  FileView {
    id: sessionFile
    path: engine.sessionPath
    atomicWrites: true
    blockLoading: true
    printErrors: false
  }

  function formatTime(secs) {
    if (!secs || secs < 0) return "0:00"
    var h = Math.floor(secs / 3600)
    var m = Math.floor(secs / 60) % 60
    var s = Math.floor(secs % 60)
    return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s
  }

  function run(proc, args) {
    proc.command = args
    proc.running = true
  }

  function refreshHistory() {
    if (!backendPath || historyProc.running) return
    run(historyProc, [videoBackendPath, "history"])
  }

  onBackendPathChanged: {
    Qt.callLater(refreshHistory); Qt.callLater(restoreSession)
    if (sessionName === "cinema") run(qualityRead, [remuxBackendPath, "quality"])
  }
  onPlayingChanged: saveSession()
  onFloatGeometryChanged: saveSession()

  function remuxReport(kind) {
    var body = JSON.stringify({ id: videoUrl.slice(6), source: mediaSourceId, session: playSessionId,
      position: positionSec, length: durationSec, runtime: expectedRuntime, paused: !playing, start: !remuxStarted })
    remuxStarted = true
    if (placeholderPlaying) return          // never report a status clip's position/length
    if (kind === "stopped") stopProc.exec([remuxBackendPath, "stopped", body])
    else if (!saveProc.running) run(saveProc, [remuxBackendPath, "progress", body])
  }

  function saveProgress() {
    if (!hasVideo || player.duration <= 0) return
    if (isRemux) { remuxReport("progress"); saveSession(); return }
    if (saveProc.running) return
    run(saveProc, [videoBackendPath, "history-update", JSON.stringify({
      url: videoUrl, title: videoTitle, artist: videoArtist,
      position: positionSec, length: durationSec
    })])
    saveSession()
  }

  function playVideo(item) {
    if (!item || !(item.url || item.id)) return
    if (isRemux && player.duration > 0) remuxReport("stopped"); else saveProgress()
    player.stop()
    player.source = ""
    remuxStarted = false
    recoverAttempts = 0
    lastGoodPosition = 0
    nextEpisode = null
    previousEpisode = null
    sourceList = []
    mediaSourceId = ""
    expectedRuntime = 0
    switchingSource = false
    mediaType = item.provider === "remux" || (item.url || "").indexOf("remux:") === 0 ? (item.type || "movie") : ""
    quality = ""
    poster = item.poster || ""
    backdrop = item.backdrop || ""
    videoUrl = item.url || (item.provider === "remux" ? "remux:" + item.id : "https://www.youtube.com/watch?v=" + item.id)
    videoId = item.id || ""
    videoTitle = item.title || "Loading..."
    videoArtist = item.artist || ""
    errorText = ""
    notice = ""
    resolving = true
    pendingResume = 0
    run(resolveProc, [isRemux ? remuxBackendPath : videoBackendPath, "resolve", videoUrl])
  }

  // Start at an exact second (hand-off from the phone), overriding the saved resume point.
  function playVideoAt(item, seconds) {
    playVideo(item)
    restoreResume = Math.max(0, Math.floor(seconds || 0))
    restoreAutoplay = true
  }

  function play() { if (hasVideo && !resolving) { player.play(); videoStarted() } }
  function pause() { if (playing) { player.pause(); saveProgress() } }
  function togglePlay() { if (playing) pause(); else play() }

  function stopVideo() {
    if (isRemux && player.duration > 0) remuxReport("stopped"); else saveProgress()
    player.stop()
    player.source = ""
    videoUrl = ""
    videoTitle = ""
    videoArtist = ""
    mediaType = ""
    nextEpisode = null
    previousEpisode = null
    sourceList = []
    fullscreen = false
    floating = false
    clearSession()
    refreshHistory()
  }

  function seek(seconds) {
    if (!player.seekable) return
    player.position = Math.max(0, Math.min(player.duration, seconds * 1000))
  }

  function skip(seconds) { seek(positionSec + seconds) }

  function setVolume(value) {
    audioOut.volume = Math.max(0, Math.min(1, value))
    if (audioOut.volume > 0) audioOut.muted = false
  }

  // Seamless pop-out: same player, just a different video sink.
  function popOut() {
    if (!hasVideo) return
    floating = true
  }

  function dock() { fullscreen = false; tiled = false; floating = false }

  // Fullscreen = the floating window, fullscreened by Hyprland (same player, no reload).
  property bool fullscreen: false
  // The pop-out window was turned into an ordinary tiled window (Super+O over it).
  property bool tiled: false
  signal floatRequested()
  function backToFloating() { if (tiled) floatRequested() }
  // Where fullscreen was entered from: exiting goes back there (panel or corner window).
  property bool fullscreenFromPanel: false
  function toggleFullscreen() {
    if (!hasVideo) return
    if (fullscreen) { exitFullscreen(); return }
    fullscreenFromPanel = !floating
    if (!floating) floating = true
    fullscreen = true
  }
  function exitFullscreen() {
    if (!fullscreen) return
    fullscreen = false
    if (fullscreenFromPanel) { fullscreenFromPanel = false; floating = false }
  }

  function openYouTube(item) {
    var target = item || { url: videoUrl }
    if (!target.url) return
    var position = (!item || target.url === videoUrl) ? Math.floor(positionSec) : Math.floor(item.position || 0)
    if (!item || target.url === videoUrl) pause()
    notice = "Opening on YouTube…"
    run(handoffProc, [videoBackendPath, "youtube", target.url, String(position)])
  }

  // Hand the current YouTube video to the phone (continues at the same second).
  readonly property string phoneBackendPath: backendPath.replace(/oma-player$/, "oma-phone")
  readonly property bool canSendToPhone: hasVideo
  // YouTube: same video at the same second in NewPipe. Movies/Series: the exact title/episode in Moonfin
  // (position stored on the configured remote Remux server for resume).
  function sendToPhone() {
    if (!canSendToPhone) return
    pause()
    notice = "Sending to phone…"
    if (isRemux) {
      if (isRemux && player.duration > 0) remuxReport("progress")
      run(foldProc, [remuxBackendPath, "handoff", videoUrl, String(Math.floor(positionSec))])
    } else {
      run(phoneProc, [phoneBackendPath, "send", videoUrl, String(Math.floor(positionSec))])
    }
  }
  // Copy a link for any other device: YouTube with time, Movies/Series as an IMDb page.
  function copyLink() {
    if (!hasVideo) return
    if (isRemux) { copyAfterShare = true; run(shareProc, [remuxBackendPath, "share", videoUrl]); return }
    var t = Math.floor(positionSec)
    copyText(videoUrl.replace(/([?&])t=\d+s?&?/, "$1").replace(/[?&]$/, "") + (t > 5 ? (videoUrl.indexOf("?") >= 0 ? "&" : "?") + "t=" + t + "s" : ""))
  }
  property bool copyAfterShare: false
  function copyText(text) {
    copyProc.command = ["wl-copy", "--", text]
    copyProc.running = true
    notice = "Link copied"
  }
  Process { id: copyProc }
  Process {
    id: shareProc
    stdout: StdioCollector { id: shareOut; waitForEnd: true }
    onExited: {
      try {
        var d = JSON.parse(shareOut.text)
        if (!d.ok) { engine.notice = d.error || "Can't share this title"; engine.copyAfterShare = false; return }
        if (engine.copyAfterShare) { engine.copyAfterShare = false; engine.copyText(d.imdb); return }
        engine.run(phoneProc, [engine.phoneBackendPath, "send", d.stremio, "0"])
      } catch (e) { engine.notice = "Can't share this title"; engine.copyAfterShare = false }
    }
  }
  Process {
    id: foldProc
    stdout: StdioCollector { id: foldOut; waitForEnd: true }
    onExited: {
      try {
        var d = JSON.parse(foldOut.text)
        if (!d.ok) { engine.notice = d.error || "Can't hand this title to the Fold"; return }
        engine.run(phoneProc, [engine.phoneBackendPath, "send", d.moonfin, "0"])
      } catch (e) { engine.notice = "Can't hand this title to the Fold" }
    }
  }
  Process {
    id: phoneProc
    stdout: StdioCollector { id: phoneOut; waitForEnd: true }
    onExited: {
      try {
        var d = JSON.parse(phoneOut.text)
        engine.notice = d.ok ? "Continuing on " + d.device : (d.error || "Could not reach the phone")
      } catch (e) { engine.notice = "Could not reach the phone" }
    }
  }

  function removeHistory(id) { run(removeProc, [videoBackendPath, "history-remove", id]) }

  function startSearch(query) {
    var trimmed = (query || "").trim()
    if (!trimmed) return false
    if (trimmed === lastQuery && results.length > 0) return true
    lastQuery = trimmed
    searching = true
    run(searchProc, [backendPath, "search", trimmed, "20"])
    return true
  }

  // Exactly one sink at a time; floating wins while its window exists.
  function syncOutput() {
    var target = floating && floatOutput ? floatOutput : panelOutput
    if (player.videoOutput !== target) player.videoOutput = target
  }
  onFloatingChanged: { syncOutput(); saveSession() }
  onFloatOutputChanged: syncOutput()
  onPanelOutputChanged: syncOutput()

  // End of stream, handled after the player's signal returns (see recoverLater).
  function handleEnd() {
    if (engine.placeholderPlaying) { engine.recoverStream("placeholder", true); return }
    var dur = engine.expectedRuntime > 0 ? engine.expectedRuntime : player.duration / 1000
    var at = Math.max(engine.lastGoodPosition, player.position / 1000)
    // A dropped connection reports "end" too: only the last 3 minutes (credits) count as finished.
    if (dur > 120 && at < dur - 180) {
      if (engine.recoverStream("early end")) return
      if (engine.isRemux) engine.remuxReport("progress")
      engine.errorText = "Playback stopped at " + engine.formatTime(at) + " — pick another source"
      engine.refreshSources()
      return
    }
    if (engine.isRemux) {
      if (engine.nextEpisode && engine.autoNext) {
        var prev = { provider: "remux", id: engine.videoUrl.slice(6), url: engine.videoUrl, type: engine.mediaType,
          title: engine.videoTitle, artist: engine.videoArtist, poster: engine.poster, backdrop: engine.backdrop,
          position: Math.max(0, Math.floor(at) - 5) }
        engine.playVideo(engine.nextEpisode)       // reports "stopped" for the finished episode once
        engine.previousEpisode = prev
        engine.notice = "Next episode — ↶ to go back to " + (prev.artist || prev.title)
      } else engine.remuxReport("stopped")
    } else { engine.saveProgress(); engine.refreshHistory() }
  }
  Timer { id: endTimer; interval: 0; onTriggered: engine.handleEnd() }

  MediaPlayer {
    id: player
    audioOutput: AudioOutput { id: audioOut; volume: 0.8 }
    onMediaStatusChanged: {
      if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && engine.placeholderPlaying) {
        engine.recoverLater("placeholder", true)
        return
      }
      if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia)
          && engine.pendingResume > 0 && seekable) {
        position = engine.pendingResume * 1000
        engine.pendingResume = 0
      }
      if (mediaStatus === MediaPlayer.EndOfMedia) endTimer.restart()
    }
    onDurationChanged: if (engine.placeholderPlaying && !engine.resolving) engine.recoverLater("placeholder", true)
    onErrorOccurred: function(error, message) {
      if (error === MediaPlayer.ResourceError || error === MediaPlayer.NetworkError
          || error === MediaPlayer.FormatError) {
        // Failing before the first frame = this source is broken; skip it right away.
        if (engine.recoverAttempts < 4 && engine.hasVideo) {
          engine.errorText = ""
          engine.recoverLater(message || "stream error", engine.isRemux && player.position <= 0)
          return
        }
      }
      engine.errorText = message || "Playback failed"
      engine.resolving = false
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: engine.playing
    onTriggered: engine.saveProgress()
  }

  Timer {
    id: noticeTimer
    interval: 2500
    onTriggered: engine.notice = ""
  }
  onNoticeChanged: if (notice) noticeTimer.restart()

  function applyResolved(data) {
        engine.videoId = data.id
        engine.videoUrl = data.url
        engine.videoTitle = data.title
        engine.videoArtist = data.artist
        engine.mediaSourceId = data.mediaSourceId || ""
        engine.playSessionId = data.playSessionId || ""
        engine.quality = data.quality || ""
        engine.sourceList = data.sourceList || []
        engine.expectedRuntime = Number(data.duration) || 0
        if (data.poster) engine.poster = data.poster
        if (data.backdrop) engine.backdrop = data.backdrop
        if (data.provider === "remux") {
          engine.mediaType = data.type || "movie"
          if (data.type === "episode" && !engine.nextEpisode) engine.run(nextProc, [engine.remuxBackendPath, "next", data.id])
        }
        engine.pendingResume = engine.restoreResume >= 0 ? engine.restoreResume : (data.resume || 0)
        engine.intendedStart = engine.pendingResume
        var autoplay = engine.restoreResume < 0 || engine.restoreAutoplay
        engine.restoreResume = -1
        engine.restoreAutoplay = true
        engine.syncOutput()
        player.source = data.source
        if (autoplay) { player.play(); engine.videoStarted() } else player.pause()
        if (data.skipped > 0) engine.notice = "Skipped " + data.skipped + (data.skipped === 1 ? " source that wasn't" : " sources that weren't") + " ready"
        else if (engine.pendingResume > 0) engine.notice = "Resuming at " + engine.formatTime(engine.pendingResume)
  }

  Process {
    id: switchProc
    stdout: StdioCollector { id: switchOut; waitForEnd: true }
    onExited: function(exitCode) {
      engine.switchingSource = false
      var data
      try { data = JSON.parse(switchOut.text) } catch (e) { data = { ok: false, error: "Couldn't check that source" } }
      if (!data.ok) { engine.notice = data.error || "That source isn't playable"; engine.refreshSources(); return }
      if (engine.videoUrl !== data.url) return      // title changed meanwhile
      var at = engine.placeholderPlaying ? Math.max(engine.lastGoodPosition, engine.intendedStart)
        : engine.errorText !== "" || engine.positionSec <= 0
        ? Math.max(engine.lastGoodPosition, engine.pendingResume, engine.positionSec) : engine.positionSec
      // Picking a source after a failure means "play this": only a paused title stays paused.
      var wasPlaying = engine.playing || engine.buffering || engine.errorText !== "" || engine.placeholderPlaying
      engine.errorText = ""
      if (player.duration > 0) engine.remuxReport("stopped")
      player.stop()
      player.source = ""
      engine.remuxStarted = false
      engine.recoverAttempts = 0
      engine.restoreResume = Math.max(0, Math.floor(at))
      engine.restoreAutoplay = wasPlaying
      engine.applyResolved(data)
      engine.notice = "Switched to " + (data.sourceList || []).filter(function(s) { return s.id === data.mediaSourceId })
        .map(function(s) { return s.provider }).join("") + " at " + engine.formatTime(at)
    }
  }
  Process {
    id: sourcesProc
    stdout: StdioCollector { id: sourcesOut; waitForEnd: true }
    onExited: { try { var d = JSON.parse(sourcesOut.text); if (d.ok && "remux:" + d.id === engine.videoUrl) engine.sourceList = d.sources } catch (e) {} }
  }
  Process {
    id: unplayedProc
    function exec(args) { command = args; running = true }
  }

  Process {
    id: resolveProc
    stdout: StdioCollector { id: resolveOut; waitForEnd: true }
    onExited: function(exitCode) {
      engine.resolving = false
      try {
        var data = JSON.parse(resolveOut.text)
        if (!data.ok) {
          engine.errorText = data.error || "Could not load video"
          if (engine.isRemux && /no streams/i.test(engine.errorText)) {
            var gone = engine.videoUrl.slice(6), m = engine.deadIds
            m[gone] = true
            engine.deadIds = m
            engine.noStreams(gone)
          }
          if (engine.isRemux) engine.refreshSources()
          return
        }
        engine.applyResolved(data)
      } catch (e) {
        engine.errorText = "Could not load video"
      }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchOut; waitForEnd: true }
    onExited: function(exitCode) {
      engine.searching = false
      try { engine.results = JSON.parse(searchOut.text).results || [] } catch (e) { engine.results = [] }
    }
  }

  Process {
    id: historyProc
    stdout: StdioCollector { id: historyOut; waitForEnd: true }
    onExited: function(exitCode) {
      try { engine.history = JSON.parse(historyOut.text).items || [] } catch (e) {}
    }
  }

  Process { id: qualityProc }
  Process {
    id: qualityRead
    stdout: StdioCollector { id: qualityReadOut; waitForEnd: true }
    onExited: { try { var q = JSON.parse(qualityReadOut.text).quality; if (q) engine.maxQuality = q } catch (e) {} }
  }
  Process { id: saveProc; onExited: engine.isRemux ? engine.remuxProgressSaved() : engine.refreshHistory() }

  Process {
    id: handoffProc
    stdout: StdioCollector { id: handoffOut; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var data = JSON.parse(handoffOut.text)
        if (!data.ok) engine.notice = data.error || "Could not open video"
      } catch (e) {}
      engine.refreshHistory()
    }
  }

  Process { id: removeProc; onExited: engine.refreshHistory() }

  // Final Remux report must not be dropped while a progress call is in flight.
  Process {
    id: stopProc
    property var queue: []
    function exec(args) { queue = queue.concat([args]); if (!running) drain() }
    function drain() { if (queue.length) { command = queue[0]; queue = queue.slice(1); running = true } }
    onExited: { engine.remuxProgressSaved(); drain() }
  }

  Process {
    id: nextProc
    stdout: StdioCollector { id: nextOut; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var item = JSON.parse(nextOut.text).item
        engine.nextEpisode = item ? { provider: "remux", id: item.id, url: "remux:" + item.id, type: "episode",
          title: item.title, artist: item.subtitle, poster: item.poster, backdrop: item.backdrop } : null
      } catch (e) { engine.nextEpisode = null }
    }
  }
}
