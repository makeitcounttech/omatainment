import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell.Io
import qs.Commons
import qs.Ui

// Movies / Series view of the OmaTainment popup, backed by Remux (oma-remux). Playback goes
// through the shared VideoEngine, so pop-out, panel-close and restart-resume all apply.
Column {
  id: pane

  required property var engine
  property string kind: "movie"            // "movie" | "series"
  property QtObject bar: null
  property color foreground: Color.foreground
  property color dim: foreground
  property color muted: foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool panelOpened: false
  property real listCap: Style.space(320)
  // Height the whole pane may use (set by the bar panel); the list takes what is left.
  property real maxHeight: 0

  readonly property string backend: engine.remuxBackendPath
  readonly property bool playingHere: engine.hasVideo && engine.isRemux
    && (kind === "series" ? engine.mediaType === "episode" : engine.mediaType === "movie")

  // Browse state
  property bool browseOpen: !playingHere
  property string subTab: "continue"       // continue | favorites | results
  property var results: []
  property var continueItems: []
  property var favoriteItems: []
  property bool loading: false
  property string errorText: ""
  property string lastQuery: ""

  // Series drill-down
  property var show: null                   // selected series card
  property var seasons: []
  property string seasonId: ""
  property var episodes: []
  property string wantSeasonId: ""          // season to land on when opening a show from an episode

  property alias searchField: searchBox

  signal closeRequested()
  signal browseRequested(string kind)

  spacing: Style.space(8)

  readonly property var listModel: (show ? episodes
    : subTab === "results" ? results
    : subTab === "favorites" ? favoriteItems
    : continueItems).filter(function(i) { return !pane.engine || !pane.engine.deadIds[i.id] })

  function call(proc, args) { proc.command = [backend].concat(args); proc.running = true }

  function refresh() {
    if (!backend) return
    if (!continueProc.running) call(continueProc, ["continue"])
    if (!favoritesProc.running) call(favoritesProc, ["favorites"])
  }

  function submit() {
    var text = searchBox.text.trim()
    if (!text) return
    show = null
    subTab = "results"
    if (text === lastQuery && results.length) return
    lastQuery = text
    loading = true
    errorText = ""
    call(searchProc, ["search", kind, text])
  }

  function play(item) {
    if (!item) return
    engine.playVideo({ provider: "remux", id: item.id, url: "remux:" + item.id,
      type: item.type === "episode" ? "episode" : "movie",
      title: item.title, artist: item.subtitle, poster: item.poster, backdrop: item.backdrop })
  }

  function open(item) {
    if (!item) return
    if (item.type === "series") { openShow(item); return }
    play(item)
  }

  // Episode (or series) -> its show, on the episode's season. Used from Continue rows and
  // the now-playing row, so autoplay never strands you without an episode list.
  function openEpisodesOf(item) {
    if (!item) return
    browseOpen = true
    if (item.type === "series") { openShow(item); return }
    loading = true
    errorText = ""
    call(showProc, ["show", item.id])
  }

  function openShow(item, seasonHint) {
    wantSeasonId = seasonHint || ""
    show = item
    seasons = []
    episodes = []
    seasonId = ""
    loading = true
    call(seasonsProc, ["seasons", item.id])
  }

  function pickSeason(id) {
    seasonId = id
    episodes = []
    loading = true
    call(episodesProc, ["episodes", show.id, id])
  }

  function toggleFavorite(item) {
    call(favoriteProc, ["favorite", item.seriesId || item.id, item.favorite ? "off" : "on"])
  }

  onPanelOpenedChanged: {
    if (panelOpened) { refresh(); engine.panelOutput = screen.output }
    else if (engine.panelOutput === screen.output) engine.panelOutput = null
  }
  Component.onCompleted: { if (panelOpened) { refresh(); engine.panelOutput = screen.output } }
  Component.onDestruction: if (engine.panelOutput === screen.output) engine.panelOutput = null
  onBackendChanged: Qt.callLater(refresh)
  onPlayingHereChanged: browseOpen = !playingHere

  Connections {
    target: pane.engine
    function onRemuxProgressSaved() { if (pane.panelOpened && !continueProc.running) pane.call(continueProc, ["continue"]) }
  }

  // ---------------------------------------------------------------- processes
  function parse(text) { try { return JSON.parse(text) } catch (e) { return { ok: false, error: "Bad response" } } }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchOut; waitForEnd: true }
    onExited: {
      pane.loading = false
      var d = pane.parse(searchOut.text)
      if (d.ok) pane.results = d.items; else pane.errorText = d.error
    }
  }
  Process {
    id: continueProc
    stdout: StdioCollector { id: continueOut; waitForEnd: true }
    onExited: {
      var d = pane.parse(continueOut.text)
      if (!d.ok) { pane.errorText = d.error; return }
      pane.continueItems = d.items.filter(function(i) {
        return pane.kind === "series" ? i.type === "episode" : i.type === "movie"
      })
    }
  }
  Process {
    id: favoritesProc
    stdout: StdioCollector { id: favoritesOut; waitForEnd: true }
    onExited: {
      var d = pane.parse(favoritesOut.text)
      if (d.ok) pane.favoriteItems = d.items.filter(function(i) { return i.type === pane.kind })
    }
  }
  Process {
    id: seasonsProc
    stdout: StdioCollector { id: seasonsOut; waitForEnd: true }
    onExited: {
      var d = pane.parse(seasonsOut.text)
      pane.loading = false
      if (!d.ok) { pane.errorText = d.error; return }
      pane.seasons = d.items
      // The episode's own season when opened from an episode, else the first with unwatched episodes.
      var target = d.items.find(function(s) { return pane.wantSeasonId !== "" && s.id === pane.wantSeasonId })
        || d.items.find(function(s) { return s.number > 0 && s.unplayed !== 0 }) || d.items[0]
      if (target) pane.pickSeason(target.id)
    }
  }
  Process {
    id: showProc
    stdout: StdioCollector { id: showOut; waitForEnd: true }
    onExited: {
      var d = pane.parse(showOut.text)
      pane.loading = false
      if (!d.ok || !d.item) { pane.errorText = d.error || "Show not found"; return }
      pane.openShow(d.item, d.seasonId)
    }
  }
  Process {
    id: episodesProc
    stdout: StdioCollector { id: episodesOut; waitForEnd: true }
    onExited: {
      var d = pane.parse(episodesOut.text)
      pane.loading = false
      if (d.ok) pane.episodes = d.items; else pane.errorText = d.error
    }
  }
  Process {
    id: favoriteProc
    onExited: { pane.refresh(); if (pane.subTab === "results" && pane.lastQuery) { pane.lastQuery = ""; pane.submit() } }
  }

  // ---------------------------------------------------------------- player
  VideoScreen {
    id: screen
    width: parent.width
    // While browsing with a video loaded, the screen gives up height so the list
    // keeps at least ~2.5 rows (and the panel never grows past maxHeight).
    readonly property real browseNeed: browseColumn.visible && pane.maxHeight > 0
      ? searchRow.height + (pane.show ? showHeader.height : tabsBar.height) + Style.space(220) + Style.space(8) * 3
        + nowRow.height + pane.spacing * 2
      : 0
    height: browseNeed > 0
      ? Math.max(Style.space(140), Math.min(Math.round(width * 9 / 16), pane.maxHeight - browseNeed))
      : Math.round(width * 9 / 16)
    visible: pane.engine.hasVideo
    engine: pane.engine
    foreground: pane.foreground
    accent: pane.accent
    fontFamily: pane.fontFamily
    placeholder: pane.kind === "series" ? "Pick a show and an episode" : "Search a movie or continue where you left off"
  }

  // Now playing + browse toggle
  Item {
    id: nowRow
    visible: pane.engine.hasVideo
    width: parent.width
    height: Math.max(nowColumn.implicitHeight, browseToggle.height)

    Column {
      id: nowColumn
      anchors.left: parent.left
      anchors.right: episodesPill.visible ? episodesPill.left : browseToggle.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        text: pane.engine.videoTitle
        color: pane.foreground
        font.family: pane.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: pane.engine.notice !== "" ? pane.engine.notice
          : [pane.engine.videoArtist, pane.engine.mediaType === "episode" ? pane.engine.quality : ""].filter(Boolean).join("  ·  ")
        color: pane.engine.notice !== "" ? pane.accent : pane.dim
        font.family: pane.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Pill {
      id: episodesPill
      objectName: "remux-now-episodes"
      visible: pane.engine.mediaType === "episode" && pane.engine.videoId !== ""
      anchors.right: browseToggle.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      label: "󰒺  Episodes"
      active: pane.browseOpen && !!pane.show
      onClicked: pane.openEpisodesOf({ id: pane.engine.videoId, type: "episode" })
    }
    Pill {
      id: browseToggle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      label: pane.browseOpen ? "󰅃  Hide" : "󰍉  Browse"
      active: pane.browseOpen
      onClicked: { pane.browseOpen = !pane.browseOpen; if (pane.browseOpen) searchBox.forceActiveFocus() }
    }
  }

  // ---------------------------------------------------------------- browse
  Column {
    id: browseColumn
    visible: pane.browseOpen || !pane.engine.hasVideo
    width: parent.width
    spacing: Style.space(8)

    Row {
      id: searchRow
      width: parent.width
      spacing: Style.space(8)
      TextField {
        id: searchBox
        width: parent.width - searchBtn.width - browseBtn.width - Style.space(16)
        placeholderText: pane.kind === "series" ? "Search series…" : "Search movies…"
        font.family: pane.fontFamily
        font.pixelSize: Style.font.body
        onAccepted: pane.submit()
        Keys.onEscapePressed: pane.closeRequested()
      }
      PanelActionButton {
        id: searchBtn
        iconText: pane.loading ? "󰑮" : "󰍉"
        tooltipText: "Search"
        anchors.verticalCenter: parent.verticalCenter
        onClicked: pane.submit()
      }
      PanelActionButton {
        id: browseBtn
        objectName: "remux-browse"
        iconText: "󰕮"
        tooltipText: "Browse " + (pane.kind === "series" ? "series" : "movies")
        anchors.verticalCenter: parent.verticalCenter
        onClicked: pane.browseRequested(pane.kind)
      }
    }

    // Tabs, or the show header when drilled into a series.
    Rectangle {
      id: tabsBar
      visible: !pane.show
      width: parent.width
      height: Style.space(30)
      radius: height / 2
      color: Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.05)
      Row {
        anchors.fill: parent
        anchors.margins: Style.space(2)
        Repeater {
          model: [
            { id: "continue", name: "󰋚  Continue" + (pane.continueItems.length ? "  " + pane.continueItems.length : "") },
            { id: "favorites", name: "󰋑  Favorites" + (pane.favoriteItems.length ? "  " + pane.favoriteItems.length : "") },
            { id: "results", name: "󰍉  Results" + (pane.results.length ? "  " + pane.results.length : "") }
          ]
          Rectangle {
            width: parent.width / 3
            height: parent.height
            radius: height / 2
            color: pane.subTab === modelData.id ? pane.accent
              : (tabMouse.containsMouse ? Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.06) : "transparent")
            Behavior on color { ColorAnimation { duration: 140 } }
            Text {
              anchors.centerIn: parent
              text: modelData.name
              color: pane.subTab === modelData.id ? Color.background : (tabMouse.containsMouse ? pane.foreground : pane.dim)
              font.family: pane.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: pane.subTab === modelData.id
            }
            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { pane.subTab = modelData.id; if (modelData.id !== "results") pane.refresh() }
            }
          }
        }
      }
    }

    // Series header: backdrop, title, seasons.
    Rectangle {
      id: showHeader
      visible: !!pane.show
      width: parent.width
      height: Style.space(112)
      radius: Style.space(12)
      color: Qt.rgba(0, 0, 0, 0.4)
      clip: true

      Image {
        anchors.fill: parent
        source: pane.show ? pane.show.backdrop : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.55
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.85) }
          GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.15) }
        }
      }
      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(12)
        spacing: Style.space(4)
        Row {
          spacing: Style.space(8)
          Pill { label: "󰁍"; onClicked: { pane.show = null; pane.episodes = [] } }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pane.show ? pane.show.title : ""
            color: "white"
            font.family: pane.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pane.show ? [pane.show.year, pane.show.rating ? "★ " + pane.show.rating : ""].filter(Boolean).join("  ·  ") : ""
            color: Qt.rgba(1, 1, 1, 0.7)
            font.family: pane.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          width: parent.width
          text: pane.show ? pane.show.overview : ""
          color: Qt.rgba(1, 1, 1, 0.75)
          font.family: pane.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }
      Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(10)
        height: Style.space(26)
        contentWidth: seasonRow.width
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        Row {
          id: seasonRow
          spacing: Style.space(6)
          Repeater {
            model: pane.seasons
            Pill {
              label: modelData.number === 0 ? "Specials" : "S" + modelData.number
              active: pane.seasonId === modelData.id
              onClicked: pane.pickSeason(modelData.id)
            }
          }
        }
      }
    }

    // Results / continue / favorites / episodes
    ListView {
      id: list
      objectName: "remux-list"
      width: parent.width
      // Everything else in the pane is subtracted, so the list scrolls instead of overflowing.
      readonly property real room: pane.maxHeight > 0
        ? pane.maxHeight
          - (screen.visible ? screen.height + pane.spacing : 0)
          - (nowRow.visible ? nowRow.height + pane.spacing : 0)
          - searchRow.height - parent.spacing
          - (pane.show ? showHeader.height : tabsBar.height) - parent.spacing
          - (emptyText.visible ? emptyText.height + parent.spacing : 0)
        : pane.listCap
      height: Math.max(Style.space(60), Math.min(room, count * Style.space(88) + Math.max(0, count - 1) * spacing))
      clip: true
      spacing: Style.space(4)
      model: pane.listModel

      delegate: Rectangle {
        id: row
        width: list.width
        height: Style.space(84)
        radius: Style.space(12)
        readonly property bool episode: modelData.type === "episode"
        readonly property bool current: pane.engine.videoUrl === "remux:" + modelData.id
        readonly property real progress: modelData.runtime > 0 ? Math.min(1, modelData.position / modelData.runtime) : 0
        color: current ? Qt.rgba(pane.accent.r, pane.accent.g, pane.accent.b, 0.14)
          : (rowMouse.containsMouse ? Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.06) : "transparent")
        Behavior on color { ColorAnimation { duration: 110 } }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: pane.open(modelData)
        }

        Row {
          anchors.fill: parent
          anchors.margins: Style.space(6)
          spacing: Style.space(10)

          // Poster (movies/series) or 16:9 still (episodes)
          Rectangle {
            id: art
            width: row.episode && pane.show ? Math.round(height * 16 / 9) : Math.round(height * 2 / 3)
            height: parent.height
            radius: Style.space(8)
            color: Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.08)
            clip: true
            Image {
              id: artImage
              anchors.fill: parent
              source: row.episode && pane.show ? (modelData.thumb || modelData.backdrop) : modelData.poster
              sourceSize.height: 240
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              visible: false
            }
            MultiEffect {
              anchors.fill: parent
              source: artImage
              maskEnabled: true
              maskSource: artMask
              visible: artImage.status === Image.Ready
            }
            Item {
              id: artMask
              anchors.fill: parent
              layer.enabled: true
              visible: false
              Rectangle { anchors.fill: parent; radius: art.radius }
            }
            Text {
              anchors.centerIn: parent
              visible: artImage.status !== Image.Ready
              text: row.episode ? "󰕧" : "󰿎"
              color: pane.dim
              font.family: pane.fontFamily
              font.pixelSize: Style.font.title
            }
            Rectangle {
              visible: row.progress > 0 && !modelData.played
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              height: 3
              width: parent.width * row.progress
              color: pane.accent
            }
          }

          Column {
            width: parent.width - art.width - actions.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Row {
              width: parent.width
              spacing: Style.space(6)
              Rectangle {
                id: typeBadge
                visible: !row.episode && modelData.type !== pane.kind
                anchors.verticalCenter: parent.verticalCenter
                width: badgeText.implicitWidth + Style.space(12)
                height: badgeText.implicitHeight + Style.space(4)
                radius: height / 2
                color: Qt.rgba(pane.accent.r, pane.accent.g, pane.accent.b, 0.2)
                Text {
                  id: badgeText
                  anchors.centerIn: parent
                  text: modelData.type === "series" ? "Series" : "Movie"
                  color: pane.accent
                  font.family: pane.fontFamily
                  font.pixelSize: Style.font.caption * 0.85
                  font.bold: true
                }
              }
            Text {
              width: parent.width - (typeBadge.visible ? typeBadge.width + parent.spacing : 0)
              text: row.episode && pane.show ? modelData.subtitle : modelData.title
              color: pane.foreground
              font.family: pane.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            }
            Text {
              width: parent.width
              text: row.episode && !pane.show ? modelData.subtitle
                : [modelData.year && !row.episode ? modelData.year : "",
                   modelData.rating ? "★ " + modelData.rating : "",
                   modelData.runtime ? Math.round(modelData.runtime / 60) + " min" : "",
                   (modelData.genres || []).slice(0, 2).join(", ")].filter(Boolean).join("  ·  ")
              color: pane.dim
              font.family: pane.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: modelData.played ? "󰄬 Watched"
                : row.progress > 0 ? pane.engine.formatTime(modelData.position) + " / " + pane.engine.formatTime(modelData.runtime) + " watched"
                : modelData.overview
              color: modelData.played || row.progress > 0 ? pane.accent : pane.muted
              font.family: pane.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
          }

          Row {
            id: actions
            anchors.verticalCenter: parent.verticalCenter
            opacity: rowMouse.containsMouse || actionHover.hovered ? 1 : 0.5
            Behavior on opacity { NumberAnimation { duration: 120 } }
            HoverHandler { id: actionHover }
            PanelActionButton {
              visible: !(row.episode && pane.show)
              iconText: modelData.favorite ? "󰋑" : "󰋔"
              tooltipText: modelData.favorite ? "Remove favorite" : "Favorite"
              size: Style.space(28)
              onClicked: pane.toggleFavorite(modelData)
            }
            PanelActionButton {
              objectName: "remux-row-episodes"
              visible: row.episode && !pane.show
              iconText: "󰒺"
              tooltipText: "Seasons & episodes"
              size: Style.space(28)
              onClicked: pane.openEpisodesOf(modelData)
            }
            PanelActionButton {
              iconText: modelData.type === "series" ? "󰅂" : "󰐊"
              tooltipText: modelData.type === "series" ? "Seasons & episodes" : "Play"
              size: Style.space(28)
              onClicked: pane.open(modelData)
            }
          }
        }
      }
    }

    Text {
      id: emptyText
      visible: list.count === 0
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: pane.errorText !== "" ? "󰀦  " + pane.errorText
        : pane.loading ? "Loading…"
        : pane.show ? "No episodes found."
        : pane.subTab === "results" ? "Search above and press Enter."
        : pane.subTab === "favorites" ? "Favorite " + (pane.kind === "series" ? "a series" : "a movie") + " with 󰋔 to keep it here."
        : "Nothing in progress yet."
      color: pane.errorText !== "" ? Color.urgent : pane.muted
      font.family: pane.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component Pill: Rectangle {
    id: pill
    property string label: ""
    property bool active: false
    signal clicked()
    width: pillText.implicitWidth + Style.space(22)
    height: Style.space(26)
    radius: height / 2
    color: active ? Qt.rgba(pane.accent.r, pane.accent.g, pane.accent.b, 0.22)
      : pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
      id: pillText
      anchors.centerIn: parent
      text: pill.label
      color: pill.active ? pane.accent : pane.foreground
      font.family: pane.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: pill.active
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }
}
