import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "empire.omatainment"
  ipcTarget: "empire.omatainment"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color muted: Qt.darker(foreground, 1.85)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string backendPath: Qt.resolvedUrl("oma-player").toString().replace(/^file:\/\//, "")
  readonly property string statusPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omatainment/status.json"
  readonly property string prefsPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omatainment/preferences.json"

  // Player State
  property bool isPlaying: false
  property bool isPaused: false
  property bool isBusy: false
  property string currentTitle: ""
  property string currentArtist: ""
  property string currentUrl: ""
  property int currentPositionSec: 0
  property int totalDurationSec: 0
  property bool seekable: false
  property int volume: 70

  // User Preferences
  property string mode: "music"
  // Players live in the keepLoaded service (Service.qml) so a plugin hot reload, which
  // rebuilds every bar widget, never stops a video. This widget only renders views.
  readonly property var media: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("empire.omatainment") : null
  function loadLane(lane) { if (media) media.load(lane) }
  property string activeTab: "search"
  property bool soundEnabled: true
  property bool autoPlayQueue: true
  property bool visualizerEnabled: true
  property int cosmicTheme: 0

  // Search State
  property var searchResults: []
  property bool isSearching: false
  property string lastQuery: ""

  // Queue State
  property var queueTracks: []
  property int queueIndex: -1

  // Favorites State
  property var favorites: []

  function playSound(name) {
    // Sound disabled globally - no audio feedback from button clicks
    return
    if (!soundEnabled) return
    soundProc.command = [root.backendPath, "sound", name]
    soundProc.running = true
  }

  function refreshStatus() {
    if (statusProc.running) return
    statusProc.running = true
  }

  function refreshQueue() {
    if (queueProc.running) return
    queueProc.running = true
  }

  function refreshFavorites() {
    if (favProc.running) return
    favProc.running = true
  }

  function refreshPrefs() {
    if (prefsProc.running) return
    prefsProc.running = true
  }

  // Music, YouTube and Movies/Series are independent lanes: they can all play at once.
  function togglePlayPause() {
    isBusy = true
    execAction("toggle")
  }

  function nextTrack() {
    isBusy = true
    execAction("next")
  }

  function prevTrack() {
    isBusy = true
    execAction("prev")
  }

  function playTrack(item) {
    if (!item || !item.url) return
    isBusy = true
    currentTitle = item.title || "Loading..."
    currentArtist = item.artist || ""
    currentUrl = item.url
    isPlaying = true
    isPaused = false
    actionProc.command = [root.backendPath, "play-url", item.url, item.title || "", item.artist || "", item.duration || ""]
    actionProc.running = true
  }

  function setQueue(items) {
    queueTracks = items || []
    queueIndex = -1
    setQueueProc.command = [root.backendPath, "set-queue", JSON.stringify(items || [])]
    setQueueProc.running = true
  }

  function playFromFavorites(index) {
    if (index < 0 || index >= favorites.length) return
    var item = favorites[index]
    playTrack(item)

    if (autoPlayQueue) {
      // Smart Autoplay Queue: follow with subsequent favorites, wrapping around
      var newQueue = []
      for (var i = index + 1; i < favorites.length; i++) {
        newQueue.push(favorites[i])
      }
      for (var j = 0; j < index; j++) {
        newQueue.push(favorites[j])
      }
      setQueue(newQueue)
    }
  }

  function playFromSearch(index) {
    if (index < 0 || index >= searchResults.length) return
    var item = searchResults[index]
    playTrack(item)

    if (autoPlayQueue) {
      // Smart Autoplay Queue: follow with subsequent search results
      var newQueue = []
      for (var i = index + 1; i < searchResults.length; i++) {
        newQueue.push(searchResults[i])
      }
      if (newQueue.length > 0) {
        setQueue(newQueue)
      }
    }
  }

  function playFromQueue(index) {
    if (index < 0 || index >= queueTracks.length) return
    var item = queueTracks[index]
    playTrack(item)

    var newQueue = []
    for (var i = index + 1; i < queueTracks.length; i++) {
      newQueue.push(queueTracks[i])
    }
    setQueue(newQueue)
  }

  function queueTrack(item) {
    if (!item || !item.url) return
    isBusy = true
    actionProc.command = [root.backendPath, "queue-url", item.url, item.title || "", item.artist || "", item.duration || ""]
    actionProc.running = true
    Qt.callLater(root.refreshQueue)
  }

  function clearQueue() {
    execAction("queue-clear")
    queueTracks = []
    queueIndex = -1
  }

  function restartSession() {
    isBusy = true
    currentTitle = ""
    currentArtist = ""
    isPlaying = false
    isPaused = false
    execAction("restart-session")
    root.refreshQueue()
    root.refreshFavorites()
    root.refreshPrefs()
  }

  function toggleFavorite(item) {
    if (!item) return
    var jsonStr = JSON.stringify(item)
    favToggleProc.command = [root.backendPath, "favorites-toggle", jsonStr]
    favToggleProc.running = true
  }

  function isTrackFavorite(item) {
    if (!item) return false
    var key = item.id || item.url || ""
    for (var i = 0; i < favorites.length; i++) {
      if ((favorites[i].id || favorites[i].url) === key) return true
    }
    return false
  }

  function setVolume(pct) {
    volume = Math.max(0, Math.min(100, Math.round(pct)))
    execActionWithArg("volume", String(volume))
  }

  function seekTo(seconds) {
    var requested = Number(seconds)
    if (!seekable || totalDurationSec <= 0 || !isFinite(requested) || seekProc.running) return
    var target = Math.max(0, Math.min(totalDurationSec, Math.round(requested)))
    currentPositionSec = target
    seekProc.command = [root.backendPath, "seek", String(target)]
    seekProc.running = true
  }

  function setMode(newMode) {
    if (mode === newMode) return
    mode = newMode
    if (newMode === "video") loadLane("video")
    if (newMode === "movie" || newMode === "series") loadLane("cinema")
    setPrefProc.command = [root.backendPath, "set-pref", "mode", JSON.stringify(newMode)]
    setPrefProc.running = true
  }

  function setActiveTab(tabId) {
    if (activeTab === tabId) return
    activeTab = tabId
    setPrefProc.command = [root.backendPath, "set-pref", "activeTab", JSON.stringify(tabId)]
    setPrefProc.running = true
    if (tabId === "queue") root.refreshQueue()
    if (tabId === "favorites") root.refreshFavorites()
  }

  function toggleSound() {
    soundEnabled = !soundEnabled
    setPrefProc.command = [root.backendPath, "set-pref", "soundEnabled", JSON.stringify(soundEnabled)]
    setPrefProc.running = true
  }

  function toggleAutoPlay() {
    autoPlayQueue = !autoPlayQueue
    setPrefProc.command = [root.backendPath, "set-pref", "autoPlayQueue", JSON.stringify(autoPlayQueue)]
    setPrefProc.running = true
  }

  function toggleVisualizer() {
    visualizerEnabled = !visualizerEnabled
    setPrefProc.command = [root.backendPath, "set-pref", "visualizerEnabled", JSON.stringify(visualizerEnabled)]
    setPrefProc.running = true
  }

  function startSearch(query) {
    var trimmed = (query || "").trim()
    if (!trimmed || trimmed === lastQuery) return
    lastQuery = trimmed
    isSearching = true
    searchProc.query = trimmed
    searchProc.running = true
  }

  function execAction(action) {
    actionProc.command = [root.backendPath, action]
    actionProc.running = true
  }

  function execActionWithArg(action, arg) {
    actionProc.command = [root.backendPath, action, arg]
    actionProc.running = true
  }

  function parseStatus(raw) {
    try {
      if (!raw || typeof raw !== "string") return
      var data = JSON.parse(raw)
      root.isPlaying = data.state === "playing"
      root.isPaused = data.state === "paused"
      root.isBusy = false

      if (data.track) {
        root.currentTitle = data.track.title || ""
        root.currentArtist = data.track.artist || ""
        root.currentUrl = data.track.path || data.track.url || ""
      }

      root.totalDurationSec = Math.max(0, Math.round(Number(data.duration) || 0))
      root.seekable = data.seekable === true && root.totalDurationSec > 0
      if (data.position !== undefined && !seekProc.running) {
        root.currentPositionSec = Math.round(data.position)
      }
      if (data.volume !== undefined) {
        root.volume = Math.round(data.volume)
      }
      if (data.preferences) {
        applyPrefs(data.preferences)
      }
    } catch (e) {
      // Ignored
    }
  }

  function applyPrefs(prefs) {
    if (!prefs) return
    if (prefs.volume !== undefined && !volSlider.dragging) {
      root.volume = Math.round(prefs.volume)
    }
    if (prefs.activeTab && (prefs.activeTab === "search" || prefs.activeTab === "queue" || prefs.activeTab === "favorites")) {
      root.activeTab = prefs.activeTab
    }
    if (["music", "video", "movie", "series"].indexOf(prefs.mode) >= 0) {
      root.mode = prefs.mode
      if (prefs.mode === "video") root.loadLane("video")
      if (prefs.mode === "movie" || prefs.mode === "series") root.loadLane("cinema")
    }
    if (prefs.soundEnabled !== undefined) {
      root.soundEnabled = prefs.soundEnabled === true
    }
    if (prefs.autoPlayQueue !== undefined) {
      root.autoPlayQueue = prefs.autoPlayQueue === true
    }
    if (prefs.visualizerEnabled !== undefined) {
      root.visualizerEnabled = prefs.visualizerEnabled === true
      root.pinned = prefs.pinned !== false
    }
    if (prefs.cosmicTheme !== undefined) {
      root.cosmicTheme = parseInt(prefs.cosmicTheme) || 0
    }
  }

  function parsePrefs(raw) {
    try {
      if (!raw || typeof raw !== "string") return
      applyPrefs(JSON.parse(raw))
    } catch (e) {
      // Ignored
    }
  }

  function formatTime(secs) {
    if (!secs || secs < 0) return "0:00"
    var h = Math.floor(secs / 3600)
    var m = Math.floor(secs / 60) % 60
    var s = Math.floor(secs % 60)
    return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "")
      + m + ":" + (s < 10 ? "0" : "") + s
  }

  visible: true
  implicitWidth: iconContainer.width
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  // Power-conscious reactive polling: runs only when open or active
  Timer {
    interval: root.opened ? 1500 : (root.isPlaying ? 3500 : 12000)
    running: root.opened || root.isPlaying
    repeat: true
    onTriggered: {
      root.refreshStatus()
      if (root.opened) {
        if (root.activeTab === "queue") root.refreshQueue()
        if (root.activeTab === "favorites") root.refreshFavorites()
      }
    }
  }

  // File watchers for real-time status and preferences updates
  FileView {
    path: root.statusPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.parseStatus(text())
    onFileChanged: reload()
  }

  FileView {
    path: root.prefsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.parsePrefs(text())
    onFileChanged: reload()
  }

  Process {
    id: statusProc
    command: [root.backendPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onTextChanged: if (text) root.parseStatus(text)
    }
  }

  // Output-monitor audio only; no microphone fallback for the bar indicator.
  Process {
    command: [root.backendPath.replace(/oma-player$/, "oma-visualizer-engine"), "--monitor"]
    running: root.isPlaying && !root.isBusy
    stdout: SplitParser {
      onRead: function(line) { playbackWave.feedAudioData(line) }
    }
  }

  Process {
    id: prefsProc
    command: [root.backendPath, "get-prefs"]
    stdout: StdioCollector {
      waitForEnd: true
      onTextChanged: if (text) root.parsePrefs(text)
    }
  }

  Process {
    id: setPrefProc
    command: []
  }

  Process {
    id: actionProc
    command: []
    onExited: root.refreshStatus()
  }

  Process {
    id: seekProc
    command: []
    onExited: root.refreshStatus()
  }

  Process {
    id: soundProc
    command: []
  }

  Process {
    id: queueProc
    command: [root.backendPath, "queue-list"]
    stdout: StdioCollector {
      id: queueOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && queueOut.text) {
        try {
          var parsed = JSON.parse(queueOut.text)
          root.queueTracks = parsed.tracks || []
          root.queueIndex = parsed.currentIndex !== undefined ? parsed.currentIndex : -1
        } catch (e) {
          root.queueTracks = []
        }
      }
    }
  }

  Process {
    id: favProc
    command: [root.backendPath, "favorites-list"]
    stdout: StdioCollector {
      id: favOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && favOut.text) {
        try {
          root.favorites = JSON.parse(favOut.text) || []
        } catch (e) {
          root.favorites = []
        }
      }
    }
  }

  Process {
    id: favToggleProc
    command: []
    stdout: StdioCollector {
      id: favToggleOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && favToggleOut.text) {
        try {
          root.favorites = JSON.parse(favToggleOut.text) || []
        } catch (e) {
          // Ignored
        }
      }
    }
  }

  Process {
    id: prefetchProc
    command: []
  }

  Process {
    id: setQueueProc
    command: []
  }

  function prefetchTrack(url) {
    if (!url || prefetchProc.running) return
    prefetchProc.command = [root.backendPath, "prefetch", url]
    prefetchProc.running = true
  }

  Process {
    id: searchProc
    property string query: ""
    command: [root.backendPath, "search", query, "20"]
    stdout: StdioCollector {
      id: searchOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.isSearching = false
      if (exitCode === 0 && searchOut.text) {
        try {
          var parsed = JSON.parse(searchOut.text)
          root.searchResults = parsed.results || []
          if (root.searchResults.length > 0 && root.searchResults[0].url) {
            root.prefetchTrack(root.searchResults[0].url)
          }
        } catch (e) {
          root.searchResults = []
        }
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function play(): void { root.togglePlayPause() }
    function next(): void { root.nextTrack() }
    function browse(): void { root.openBrowse(root.mode === "series" ? "series" : "movie") }
    // Phone -> OmaTainment: YouTube links shared from the phone (via oma-open) play in the YouTube lane,
    // alongside whatever else is playing.
    function playUrl(url: string): void { root.playIncoming(url) }
    // OmaTainment -> phone: hand the current YouTube video to the phone.
    function sendToPhone(): void { if (videoEngine.item) videoEngine.item.sendToPhone() }
    // Fold -> OmaTainment: continue what NewPipe/Moonfin is playing on the Fold here, pause it there.
    function pullFromPhone(): void { root.pullFromPhone() }
    function prev(): void { root.prevTrack() }
  }

  // Views onto the service's engines (same names as the old Loaders, so the panel code
  // below is unchanged). Popping a video out closes the panel.
  QtObject { id: videoEngine; readonly property var item: root.media ? root.media.video : null }
  QtObject { id: cinemaEngine; readonly property var item: root.media ? root.media.cinema : null }
  Connections {
    target: videoEngine.item
    ignoreUnknownSignals: true
    function onFloatingChanged() { if (videoEngine.item && videoEngine.item.floating) root.close() }
  }
  Connections {
    target: cinemaEngine.item
    ignoreUnknownSignals: true
    function onFloatingChanged() { if (cinemaEngine.item && cinemaEngine.item.floating) root.close() }
  }

  // "Continue from Fold": read the Fold's media notification (KDE Connect), find the exact video/title,
  // pause the Fold, play here in the floating window at the same second.
  property bool pulling: false
  property string pullNotice: ""
  function pullFromPhone() {
    if (pulling) return
    pulling = true
    pullNotice = "Reading the Fold…"
    pullProc.command = [root.backendPath.replace(/oma-player$/, "oma-phone"), "pull"]
    pullProc.running = true
  }
  Process { id: pullNotify }
  Timer { id: pullNoticeClear; interval: 5000; onTriggered: root.pullNotice = "" }
  Process {
    id: pullProc
    stdout: StdioCollector { id: pullOut; waitForEnd: true }
    onExited: {
      root.pulling = false
      var d = null
      try { d = JSON.parse(pullOut.text) } catch (e) {}
      if (!d || !d.ok) {
        root.pullNotice = (d && d.error) || "Couldn't read the Fold"
        pullNoticeClear.restart()
        pullNotify.command = ["notify-send", "-a", "OmaTainment", "-i", "phone", "Continue from Fold", root.pullNotice]
        pullNotify.running = true
        return
      }
      root.pullNotice = ""
      root.playIncoming(d.target, d.position, d.title)
    }
  }

  // Phone shares always land in the floating window (never the panel, never the browser).
  // YouTube -> YouTube lane; "remux:ID:TYPE" (resolved by oma-open via oma-remux lookup) -> cinema lane.
  function playIncoming(url, seconds, title) {
    var remux = /^remux:([0-9a-f]+)(?::(movie|episode))?$/i.exec(url || "")
    var youtube = /^https?:\/\/((www|m|music)\.)?(youtube\.com\/(watch|shorts\/|live\/)|youtu\.be\/)/i.test(url || "")
    if (!remux && !youtube) return
    loadLane(remux ? "cinema" : "video")
    Qt.callLater(function() {
      var engine = remux ? cinemaEngine.item : videoEngine.item
      if (!engine) return
      if (engine.fullscreen) engine.exitFullscreen()
      var item = remux ? { provider: "remux", id: remux[1], url: "remux:" + remux[1],
                           type: remux[2] === "episode" ? "episode" : "movie", title: title || "From phone…" }
                       : { url: url, title: title || "From phone…" }
      if (seconds > 0) engine.playVideoAt(item, seconds); else engine.playVideo(item)
      engine.floating = true
      close()
    })
  }

  // Browse window: streaming-style home for Movies / Series. Play goes to the cinema lane.
  property bool browseLoaded: false
  property string browseKind: "movie"
  function openBrowse(kind) {
    loadLane("cinema")
    browseKind = kind || "movie"
    if (browseWindow.item && browseWindow.item.visible) {
      browseWindow.item.kind = browseKind
      return
    }
    // Fresh window each time: a window closed by the compositor can't be shown again.
    browseLoaded = false
    browseLoaded = true
  }
  function closeBrowse() { browseLoaded = false }
  Loader {
    id: browseWindow
    active: root.browseLoaded
    sourceComponent: BrowseWindow {
      backendPath: root.backendPath.replace(/oma-player$/, "oma-remux")
      accent: root.accent
      foreground: root.foreground
      fontFamily: root.fontFamily
      kind: root.browseKind
      visible: true
      onVisibleChanged: if (!visible) Qt.callLater(root.closeBrowse)
      onClosed: Qt.callLater(root.closeBrowse)
      onQualityChanged: if (cinemaEngine.item && cinemaEngine.item.maxQuality !== quality) cinemaEngine.item.maxQuality = quality
      onPlayRequested: function(item) {
        if (!cinemaEngine.item) return
        cinemaEngine.item.maxQuality = quality
        if (cinemaEngine.item.floating) cinemaEngine.item.dock()
        cinemaEngine.item.playVideo(item)
        // Plays inside the OmaTainment panel: switch to the matching section and open it.
        visible = false
        root.setMode(item.type === "episode" ? "series" : "movie")
        root.open()
      }
    }
  }

  // Bar Widget: Icon ONLY
  Item {
    id: iconContainer
    width: Style.bar.statusSlot
    height: Style.bar.statusSlot
    anchors.verticalCenter: parent.verticalCenter

    // Animated mark (OpusMark.qml); the hidden playbackWave keeps the audio feed + phase.
    OpusMark {
      id: opusMark
      anchors.centerIn: parent
      width: Math.round(Style.font.icon * 1.05)
      height: width
      accent: root.accent
      foreground: root.bar ? root.bar.barForeground : Color.foreground
      hovered: barMouse.containsMouse
      busy: root.isBusy || (videoEngine.item !== null && videoEngine.item.resolving)
        || (cinemaEngine.item !== null && cinemaEngine.item.resolving)
      musicPlaying: root.isPlaying
      videoPlaying: videoEngine.item !== null && videoEngine.item.playing
      cinemaPlaying: cinemaEngine.item !== null && cinemaEngine.item.playing
      energy: playbackWave.energy
      pulse: playbackWave.pulse
      phase: playbackWave.phase
    }

    Item {
      id: playbackWave
      visible: false
      property real phase: 0
      property real energy: 0
      property real pulse: 0

      Behavior on energy { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
      Behavior on pulse { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

      function feedAudioData(line) {
        if (!root.isPlaying || root.isBusy) return
        try {
          var data = JSON.parse(line)
          energy = Math.max(0, Math.min(1, Number(data.energy) || 0))
          pulse = data.beat > 0.5 ? 1 : 0
          audioFreshness.restart()
        } catch (e) {}
      }

      Timer {
        id: audioFreshness
        interval: 600
        onTriggered: { playbackWave.energy = 0; playbackWave.pulse = 0 }
      }

      // Continuous phase: audio changes the flow, never resets its position.
      Timer {
        interval: 33
        running: root.isPlaying && !root.isBusy
        repeat: true
        onTriggered: playbackWave.phase = (playbackWave.phase + 0.055
          + playbackWave.energy * 0.035 + playbackWave.pulse * 0.025) % (Math.PI * 2)
      }
    }

    MouseArea {
      id: barMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor

      onEntered: {
        if (root.bar) {
          var lines = []
          if (root.isPlaying) lines.push("󰝚 " + (root.currentTitle || "Music"))
          var v = videoEngine.item, c = cinemaEngine.item
          if (v && v.playing) lines.push("󰗃 " + v.videoTitle)
          if (c && c.playing) lines.push("󰿎 " + c.videoTitle + (c.videoArtist && c.mediaType === "episode" ? " · " + c.videoArtist : ""))
          var tip = lines.length ? lines.join("\n")
            : (root.isPaused ? "Paused: " + root.currentTitle : "OmaTainment · Music · YouTube · Movies · Series")
          root.bar.showTooltip(root, tip)
        }
      }
      onExited: {
        if (root.bar) root.bar.hideTooltip(root)
      }

      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          root.togglePlayPause()
        } else {
          root.toggle()
        }
      }
    }
  }

  // Interactive Dropdown Panel
  // Pinned (default): the panel stays open while you use other apps. Only the card
  // takes input; clicks elsewhere go straight to the windows below.
  property bool pinned: true
  function togglePinned() {
    pinned = !pinned
    setPrefProc.command = [root.backendPath, "set-pref", "pinned", JSON.stringify(pinned)]
    setPrefProc.running = true
  }
  QtObject {
    id: panelOwner
    readonly property bool popoutSwitchClosing: root.popoutSwitchClosing
    function close() { if (!root.pinned) root.close() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: iconContainer
    owner: panelOwner
    bar: root.bar
    open: root.opened
    readonly property Item cardItem: mainColumn.parent ? mainColumn.parent.parent : null
    mask: Region {
      item: root.pinned ? panel.cardItem : null
      width: root.pinned ? 0 : panel.screenW
      height: root.pinned ? 0 : panel.screenH
    }
    WlrLayershell.keyboardFocus: !root.opened ? WlrKeyboardFocus.None
      : (root.pinned || panel.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    readonly property var modeLoader: root.mode === "video" ? videoLoader : root.mode === "movie" ? movieLoader : root.mode === "series" ? seriesLoader : null
    focusTarget: modeLoader && modeLoader.item ? modeLoader.item.searchField : searchField
    contentWidth: panel.fittedContentWidth(Style.space(root.mode === "music" ? 480 : 600))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(root.mode === "music" ? 680 : 900))

    // List sizing reserves controls, tab headers, footer and card insets.
    // Measure siblings rather than implicitHeight to avoid a binding loop.
    function heightWithout(column, excluded) {
      var height = column.topPadding + column.bottomPadding
      var count = 0
      for (var i = 0; i < column.children.length; i++) {
        var child = column.children[i]
        if (child === excluded) {
          count++
        } else if (child.visible && child.height > 0) {
          height += child.height
          count++
        }
      }
      return height + Math.max(0, count - 1) * column.spacing
    }

    // Space a mode pane may fill: the panel's max height minus the header/switch chrome.
    function paneRoom(loader) {
      return Math.max(Style.space(200), panel.fittedContentHeight(Style.space(2000), Style.space(900))
        - panel.verticalContentInset - heightWithout(mainColumn, loader))
    }

    function listHeight(list) {
      var tab = list.parent
      var chrome = heightWithout(mainColumn, tab) + heightWithout(tab, list)
      var available = panel.fittedContentHeight(Style.space(680), Style.space(680))
        - panel.verticalContentInset - chrome
      var rowHeight = list === resultsList ? Style.space(76) : Style.space(46)
      var cap = list === resultsList ? Style.space(310) : Style.space(190)
      return Math.max(0, Math.min(cap, available,
        Math.max(Style.space(48), list.count * rowHeight)))
    }


    // DÆMON-style surface: slightly translucent (Hyprland blurs the layer behind it),
    // larger radius and a faint accent wash. The card is Omarchy's internal BorderSurface.
    function styleCard() {
      // mainColumn -> contentHolder -> card (BorderSurface)
      var card = mainColumn.parent ? mainColumn.parent.parent : null
      if (!card || card.borderSpec === undefined) return
      card.color = Qt.binding(function() { return Qt.alpha(Color.popups.background, 1.0) })
      card.radius = Style.space(16)
    }
    Component.onCompleted: Qt.callLater(styleCard)

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Style.space(140)
      radius: Style.space(14)
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.alpha(root.accent, 0.07) }
        GradientStop { position: 1; color: "transparent" }
      }
    }

    onOpenChanged: {
      if (open) {
        root.refreshStatus()
        root.refreshPrefs()
        if (root.activeTab === "queue") root.refreshQueue()
        if (root.activeTab === "favorites") root.refreshFavorites()
      }
    }

    Column {
      id: mainColumn
      width: parent.width
      spacing: Style.space(10)
      topPadding: Style.space(12)
      bottomPadding: Style.space(10)
      leftPadding: Style.space(14)
      rightPadding: Style.space(14)

      // Header row
      Row {
        width: parent.width - Style.space(28)
        spacing: Style.space(8)

        Text {
          text: "󱑽 OmaTainment"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Item {
          width: parent.width - x - pullBtn.width - pinBtn.width - visualizerToggleBtn.width - autoplayToggleBtn.width - soundToggleBtn.width - restartBtn.width - closeBtn.width - Style.space(24)
          height: 1
        }

        PanelActionButton {
          id: pullBtn
          objectName: "omatainment-pull"
          iconText: root.pulling ? "󰑓" : "󰄜"
          tooltipText: root.pullNotice || "Continue from Fold: play what NewPipe/Moonfin is playing there, pause it on the Fold"
          foreground: root.pulling ? root.accent : root.foreground
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.pullFromPhone()
        }

        PanelActionButton {
          id: pinBtn
          objectName: "omatainment-pin"
          iconText: root.pinned ? "󰐃" : "󰤰"
          tooltipText: root.pinned ? "Pinned: stays open while you use other apps (click to unpin)" : "Closes on outside click (click to pin)"
          foreground: root.pinned ? root.accent : root.foreground
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.togglePinned()
        }

        // Spectrum Equalizer Visualizer Toggle Button
        PanelActionButton {
          id: visualizerToggleBtn
          iconText: root.visualizerEnabled ? "󰺢" : "󰺠"
          tooltipText: root.visualizerEnabled ? "Spectrum Visualizer: ON (click to toggle)" : "Spectrum Visualizer: OFF"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.toggleVisualizer()
        }

        // Autoplay Queue Toggle Button
        PanelActionButton {
          id: autoplayToggleBtn
          iconText: root.autoPlayQueue ? "󰈑" : "󰈒"
          tooltipText: root.autoPlayQueue ? "Autoplay Queue: ON" : "Autoplay Queue: OFF"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.toggleAutoPlay()
        }

        // Sound Toggle Button
        PanelActionButton {
          id: soundToggleBtn
          iconText: root.soundEnabled ? "󰕾" : "󰝟"
          tooltipText: root.soundEnabled ? "Mute audio cues" : "Enable audio cues"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.toggleSound()
        }

        // Restart Instance Button
        PanelActionButton {
          id: restartBtn
          iconText: "󰑐"
          tooltipText: "Restart Session (resets daemon and network stream)"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.restartSession()
        }

        // Close dropdown
        PanelActionButton {
          id: closeBtn
          iconText: "󰅖"
          tooltipText: "Close Panel"
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.close()
        }
      }

      // Music | Video mode switch — segmented pill in DÆMON's Local | Cloud language.
      Rectangle {
        id: modeSwitch
        objectName: "mode-switch"
        width: parent.width - Style.space(28)
        height: Style.space(34)
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

        Row {
          anchors.fill: parent
          anchors.margins: Style.space(3)

          Repeater {
            model: [
              { id: "music", name: "󰝚  Music" },
              { id: "video", name: "󰗃  YouTube" },
              { id: "movie", name: "󰿎  Movies" },
              { id: "series", name: "󰔂  Series" }
            ]

            Rectangle {
              width: parent.width / 4
              height: parent.height
              radius: height / 2
              color: root.mode === modelData.id ? root.accent
                : (modeMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent")
              Behavior on color { ColorAnimation { duration: 140 } }

              Text {
                anchors.centerIn: parent
                text: modelData.name
                color: root.mode === modelData.id ? Color.background : (modeMouse.containsMouse ? root.foreground : root.dim)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: root.mode === modelData.id
                font.letterSpacing: 0.4
                Behavior on color { ColorAnimation { duration: 140 } }
              }

              MouseArea {
                id: modeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setMode(modelData.id)
              }
            }
          }
        }
      }

      // VIDEO MODE view (engine above owns playback)
      Loader {
        id: videoLoader
        width: parent.width - Style.space(28)
        active: videoEngine.item !== null
        visible: root.mode === "video"
        sourceComponent: VideoPane {
          engine: videoEngine.item
          bar: root.bar
          foreground: root.foreground
          dim: root.dim
          muted: root.muted
          accent: root.accent
          fontFamily: root.fontFamily
          panelOpened: root.opened && root.mode === "video"
          listCap: Style.space(220)
          onCloseRequested: root.close()
        }
      }

      // MOVIES / SERIES views (Remux)
      Loader {
        id: movieLoader
        width: parent.width - Style.space(28)
        // Latches on first visit (assigned imperatively, so no binding loop).
        property bool used: false
        active: used && cinemaEngine.item !== null
        Connections {
          target: root
          function onModeChanged() { if (root.mode === "movie") movieLoader.used = true }
        }
        Component.onCompleted: if (root.mode === "movie") used = true
        visible: root.mode === "movie"
        sourceComponent: RemuxPane {
          kind: "movie"
          engine: cinemaEngine.item
          bar: root.bar
          foreground: root.foreground
          dim: root.dim
          muted: root.muted
          accent: root.accent
          fontFamily: root.fontFamily
          panelOpened: root.opened && root.mode === "movie"
          maxHeight: panel.paneRoom(movieLoader)
          onCloseRequested: root.close()
          onBrowseRequested: function(kind) { root.close(); root.openBrowse(kind) }
        }
      }

      Loader {
        id: seriesLoader
        width: parent.width - Style.space(28)
        // Latches on first visit (assigned imperatively, so no binding loop).
        property bool used: false
        active: used && cinemaEngine.item !== null
        Connections {
          target: root
          function onModeChanged() { if (root.mode === "series") seriesLoader.used = true }
        }
        Component.onCompleted: if (root.mode === "series") used = true
        visible: root.mode === "series"
        sourceComponent: RemuxPane {
          kind: "series"
          engine: cinemaEngine.item
          bar: root.bar
          foreground: root.foreground
          dim: root.dim
          muted: root.muted
          accent: root.accent
          fontFamily: root.fontFamily
          panelOpened: root.opened && root.mode === "series"
          maxHeight: panel.paneRoom(seriesLoader)
          onCloseRequested: root.close()
          onBrowseRequested: function(kind) { root.close(); root.openBrowse(kind) }
        }
      }

      // Tab switcher bar (Search | Queue | Favorites)
      Row {
        visible: root.mode === "music"
        width: parent.width - Style.space(28)
        spacing: Style.space(6)

        Repeater {
          model: [
            { id: "search", name: "󰍉 Search" },
            { id: "queue", name: "󰒮 Queue (" + root.queueTracks.length + ")" },
            { id: "favorites", name: "󰋑 Favorites (" + root.favorites.length + ")" }
          ]

          Rectangle {
            width: (parent.width - Style.space(12)) / 3
            height: Style.space(28)
            radius: Style.cornerRadius
            color: root.activeTab === modelData.id
              ? Style.selectedFillFor(root.foreground, root.accent)
              : (tabMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent")

            border.color: root.activeTab === modelData.id ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: modelData.name
              color: root.activeTab === modelData.id ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: root.activeTab === modelData.id
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setActiveTab(modelData.id)
            }
          }
        }
      }

      // Now Playing Hero Card
      Rectangle {
        visible: root.mode === "music"
        width: parent.width - Style.space(28)
        height: nowPlayingContent.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Style.selectedFillFor(root.foreground, root.accent)
        clip: true

        Column {
          id: nowPlayingContent
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(4)

          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width - (root.currentTitle ? favHeaderBtn.width + Style.space(6) : 0)
              text: root.currentTitle ? root.currentTitle : "No song playing"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelActionButton {
              id: favHeaderBtn
              visible: root.currentTitle !== ""
              iconText: root.isTrackFavorite({ id: root.currentUrl, url: root.currentUrl }) ? "󰋑" : "󰋔"
              tooltipText: "Favorite track"
              size: Style.space(22)
              anchors.verticalCenter: parent.verticalCenter
              onClicked: {
                root.toggleFavorite({
                  id: root.currentUrl,
                  title: root.currentTitle,
                  artist: root.currentArtist,
                  url: root.currentUrl,
                  duration: root.formatTime(root.totalDurationSec)
                })
              }
            }
          }

          Text {
            width: parent.width
            text: root.currentArtist || "Search tracks or pick from favorites below"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          // Track timeline: preview locally; seek only once on release.
          Row {
            visible: root.currentTitle !== ""
            width: parent.width
            spacing: Style.space(6)

            Text {
              id: elapsedTime
              width: Style.space(58)
              text: root.formatTime(seekSlider.dragging ? seekSlider.liveValue : root.currentPositionSec)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            PanelSlider {
              id: seekSlider
              objectName: "track-timeline"
              bar: root.bar
              width: parent.width - elapsedTime.width - durationTime.width - parent.spacing * 2
              minimum: 0
              maximum: Math.max(1, root.totalDurationSec)
              value: root.currentPositionSec
              integer: true
              step: 5
              enabled: root.seekable && !seekProc.running
              opacity: enabled ? 1 : 0.4
              onReleased: function(val) { root.seekTo(val) }
            }

            Text {
              id: durationTime
              width: Style.space(58)
              text: root.totalDurationSec > 0 ? root.formatTime(root.totalDurationSec) : "LIVE"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Transport controls
          Row {
            visible: root.currentTitle !== ""
            spacing: Style.space(14)
            anchors.horizontalCenter: parent.horizontalCenter

            PanelActionButton {
              iconText: "󰒮"
              tooltipText: "Previous / Restart track"
              onClicked: root.prevTrack()
            }

            PanelActionButton {
              iconText: root.isBusy ? "󰑮" : (root.isPlaying ? "󰏤" : "󰐊")
              tooltipText: root.isPlaying ? "Pause" : "Play"
              onClicked: root.togglePlayPause()
            }

            PanelActionButton {
              iconText: "󰒭"
              tooltipText: "Next"
              onClicked: root.nextTrack()
            }
          }
        }
      }

      // 32-Band Spectrum Equalizer Visualizer
      CosmicVisualizer {
        id: cosmicVis
        visible: root.visualizerEnabled && root.mode === "music"
        width: parent.width - Style.space(28)
        height: Style.space(82)
        isPlaying: root.isPlaying
        isPaused: root.isPaused
        panelOpened: root.opened
        volume: root.volume
        colorTheme: root.cosmicTheme
        enginePath: root.backendPath.replace(/oma-player$/, "oma-visualizer-engine")
        onThemeToggled: {
          root.cosmicTheme = colorTheme
          setPrefProc.command = [root.backendPath, "set-pref", "cosmicTheme", String(colorTheme)]
          setPrefProc.running = true
        }
      }

      // Volume Slider
      Row {
        visible: root.mode === "music"
        width: parent.width - Style.space(28)
        spacing: Style.space(8)

        Text {
          text: root.volume === 0 ? "󰝟" : (root.volume < 50 ? "󰕿" : "󰕾")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelSlider {
          id: volSlider
          bar: root.bar
          minimum: 0
          maximum: 100
          value: root.volume
          width: parent.width - Style.space(70)
          anchors.verticalCenter: parent.verticalCenter
          onMoved: function(val) { root.setVolume(val) }
        }

        Text {
          text: root.volume + "%"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      PanelSeparator {
        visible: root.mode === "music"
        width: parent.width - Style.space(28)
      }

      // TAB 1: SEARCH
      Column {
        visible: root.activeTab === "search" && root.mode === "music"
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: parent.width - Style.space(28)
          spacing: Style.space(8)

          TextField {
            id: searchField
            width: parent.width - searchActionBtn.width - Style.space(8)
            placeholderText: "Search YouTube Music..."
            font.family: root.fontFamily
            font.pixelSize: Style.font.body

            onAccepted: root.startSearch(text)
            Keys.onDownPressed: {
              if (resultsList.count > 0) {
                resultsList.forceActiveFocus()
                resultsList.currentIndex = 0
              }
            }
            Keys.onEscapePressed: root.close()
          }

          PanelActionButton {
            id: searchActionBtn
            iconText: root.isSearching ? "󰑮" : "󰍉"
            tooltipText: "Search"
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.startSearch(searchField.text)
          }
        }

        ListView {
          id: resultsList
          width: parent.width - Style.space(28)
          height: panel.listHeight(resultsList)
          clip: true
          model: root.searchResults

          Keys.onUpPressed: {
            if (currentIndex === 0) searchField.forceActiveFocus()
            else currentIndex--
          }
          Keys.onDownPressed: {
            if (currentIndex < count - 1) currentIndex++
          }
          Keys.onReturnPressed: {
            root.playFromSearch(currentIndex)
          }
          Keys.onEscapePressed: root.close()

          delegate: Rectangle {
            width: resultsList.width
            height: Style.space(76)
            radius: Style.cornerRadius
            color: resultsList.currentIndex === index
              ? Style.selectedFillFor(root.foreground, root.accent)
              : (mouseArea.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent")

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: {
                if (containsMouse && modelData && modelData.url) {
                  root.prefetchTrack(modelData.url)
                }
              }
              onClicked: {
                resultsList.currentIndex = index
                root.playFromSearch(index)
              }
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                id: resultPlayIcon
                text: "󰐊"
                color: resultsList.currentIndex === index ? root.foreground : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - resultPlayIcon.width - queueBtn.width - favRowBtn.width - parent.spacing * 3
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  objectName: "search-result-title"
                  text: modelData.title || ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: modelData.artist || ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: (modelData.duration || "")
                    + (modelData.views > 0 ? ((modelData.duration ? "  ·  " : "")
                      + Number(modelData.views).toLocaleString(Qt.locale(), "f", 0) + " views") : "")
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              PanelActionButton {
                id: favRowBtn
                iconText: root.isTrackFavorite(modelData) ? "󰋑" : "󰋔"
                tooltipText: "Favorite"
                size: Style.space(24)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.toggleFavorite(modelData)
              }

              PanelActionButton {
                id: queueBtn
                iconText: "󰐍"
                tooltipText: "Queue Next"
                size: Style.space(24)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.queueTrack(modelData)
              }
            }
          }
        }

        Text {
          visible: !root.isSearching && root.searchResults.length === 0
          text: "Type a track name above and press Enter."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          width: parent.width - Style.space(28)
        }
      }

      // TAB 2: QUEUE
      Column {
        visible: root.activeTab === "queue" && root.mode === "music"
        width: parent.width
        spacing: Style.space(8)

        Row {
          width: parent.width - Style.space(28)
          Text {
            text: "NOW PLAYING QUEUE"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Item {
            width: parent.width - x - clearQBtn.width
            height: 1
          }
          PanelActionButton {
            id: clearQBtn
            iconText: "󰅖"
            tooltipText: "Clear Queue"
            size: Style.space(22)
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.clearQueue()
          }
        }

        ListView {
          id: queueList
          width: parent.width - Style.space(28)
          height: panel.listHeight(queueList)
          clip: true
          model: root.queueTracks

          delegate: Rectangle {
            width: queueList.width
            height: Style.space(44)
            radius: Style.cornerRadius
            color: root.queueIndex === index
              ? Style.selectedFillFor(root.foreground, root.accent)
              : (qMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent")

            MouseArea {
              id: qMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: {
                if (containsMouse && modelData && modelData.url) {
                  root.prefetchTrack(modelData.url)
                }
              }
              onClicked: root.playFromQueue(index)
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                text: root.queueIndex === index ? "󰐊" : String(index + 1)
                color: root.queueIndex === index ? root.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(40)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: modelData.title || ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: modelData.artist || ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        Text {
          visible: root.queueTracks.length === 0
          text: "Queue is empty. Search tracks and click 󰐍 to add."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          width: parent.width - Style.space(28)
        }
      }

      // TAB 3: FAVORITES
      Column {
        visible: root.activeTab === "favorites" && root.mode === "music"
        width: parent.width
        spacing: Style.space(8)

        ListView {
          id: favList
          width: parent.width - Style.space(28)
          height: panel.listHeight(favList)
          clip: true
          model: root.favorites

          delegate: Rectangle {
            width: favList.width
            height: Style.space(44)
            radius: Style.cornerRadius
            color: favMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"

            MouseArea {
              id: favMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: {
                if (containsMouse && modelData && modelData.url) {
                  root.prefetchTrack(modelData.url)
                }
              }
              onClicked: root.playFromFavorites(index)
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                text: "󰋑"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - favDelBtn.width - Style.space(36)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: modelData.title || ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: modelData.artist || ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              PanelActionButton {
                id: favDelBtn
                iconText: "󰅖"
                tooltipText: "Remove Favorite"
                size: Style.space(22)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.toggleFavorite(modelData)
              }
            }
          }
        }

        Text {
          visible: root.favorites.length === 0
          text: "No favorites yet. Click the 󰋔 icon on any track to favorite it."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          width: parent.width - Style.space(28)
        }
      }

      // Minimal Shortcuts Hint Bar
      PanelSeparator {
        visible: root.mode === "music"
        width: parent.width - Style.space(28)
      }

      Row {
        visible: root.mode === "music"
        width: parent.width - Style.space(28)
        spacing: Style.space(12)
        anchors.horizontalCenter: parent.horizontalCenter

        Text {
          text: "↵ Play"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption * 0.9
        }

        Text {
          text: "↑/↓ Navigate"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption * 0.9
        }

        Text {
          text: "󰍉 Enter to search"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption * 0.9
        }

        Text {
          text: "Esc Close"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption * 0.9
        }
      }
    }
  }

  Component.onCompleted: {
    root.refreshStatus()
    root.refreshFavorites()
    root.refreshPrefs()
  }
}
