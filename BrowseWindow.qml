import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// OmaTainment Browse: a streaming-style home for Movies / Series, backed by Remux (oma-remux).
// Rows of poster cards (Continue, catalogs, Top rated, New releases, genres); hovering a
// card previews its metadata in the hero; click opens details; Play sends it to OmaTainment.
FloatingWindow {
  id: win

  required property string backendPath          // oma-remux
  property string kind: "movie"                 // movie | series
  property color accent: Color.accent
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int quality: 1080

  signal playRequested(var item)
  signal kindRequested(string kind)

  title: "OmaTainment Browse"
  implicitWidth: 1280
  implicitHeight: 800
  minimumSize: Qt.size(820, 560)
  color: "transparent"

  function u(n) { return Style.space(n) }
  function fg(a) { return Qt.rgba(foreground.r, foreground.g, foreground.b, a) }
  function hhmm(sec) {
    if (!sec) return ""
    var m = Math.round(sec / 60), h = Math.floor(m / 60)
    return h ? h + "h " + (m % 60) + "m" : m + "m"
  }
  function metaLine(it) {
    if (!it) return ""
    return [it.year ? String(it.year) : "", it.rating ? "★ " + it.rating : "", it.certification || "",
            it.type === "movie" ? hhmm(it.runtime) : "", (it.genres || []).join(" · ")]
      .filter(function(p) { return p }).join("   ")
  }

  // ---------------------------------------------------------------- state
  property var rows: []
  property var featured: null      // featured fallback
  property var hovered: null       // previewed by hover
  property var preview: hovered || featured
  property bool loading: false
  property string errorText: ""
  property var detail: null        // item in the detail sheet
  property var seasons: []
  property string seasonId: ""
  property var episodes: []
  property string wantSeasonId: ""
  property var grid: null          // {title, id, sort, items, next, total, search}
  property var tiers: []           // qualities the detail title really has
  property bool tiersLoading: false
  readonly property bool noStreams: !!detail && detail.type === "movie" && !tiersLoading && tiersChecked && tiers.length === 0
  property bool tiersChecked: false
  property var deadIds: ({})       // titles found to have no streams this session (hidden from rows)
  function isDead(item) { return !!item && !!deadIds[item.id] }
  property var rowViews: ({})      // rowKey -> row delegate (for paging)
  property var pageQueue: []

  function reload() {
    loading = true; errorText = ""; detail = null; grid = null; hovered = null
    run(browseProc, ["browse", kind])
  }
  function setKind(k) { if (k === kind) return; kind = k; kindRequested(k); rows = []; featured = null; reload() }
  function cycleQuality() {
    var order = [720, 1080, 1440, 2160]
    var next = order[(order.indexOf(quality) + 1) % order.length]
    quality = next
    run(qualityProc, ["quality", String(next)])
  }

  function run(proc, args) {
    if (proc.running) proc.running = false
    proc.command = [backendPath].concat(args)
    proc.running = true
  }
  function parse(t) { try { return JSON.parse(t) } catch (e) { return { ok: false, error: "Bad response" } } }

  // Episode -> its series sheet on the episode's season (Continue cards, hero).
  function openEpisodesOf(item) {
    if (!item) return
    if (item.type === "series") { open(item); return }
    run(showProc, ["show", item.id])
  }
  function open(item, seasonHint) {
    if (!item) return
    if (item.type === "episode") { play(item); return }
    wantSeasonId = seasonHint || ""
    detail = item
    seasons = []; episodes = []; seasonId = ""; tiers = []; tiersChecked = false
    if (item.type === "series") run(seasonsProc, ["seasons", item.id])
    else { tiersLoading = true; run(tiersProc, ["tiers", item.id]) }
  }
  function play(item) {
    if (!item) return
    playRequested({ provider: "remux", id: item.id, url: "remux:" + item.id,
      type: item.type === "episode" ? "episode" : "movie",
      title: item.title, artist: item.subtitle, poster: item.poster, backdrop: item.backdrop })
  }
  // Play at a chosen quality (sets the cap the player uses, then plays).
  function playAt(tier) {
    if (tier) { quality = tier; run(qualityProc, ["quality", String(tier)]) }
    playDetail()
  }
  function playDetail() {
    if (!detail) return
    if (detail.type !== "series") { play(detail); return }
    var next = episodes.find(function(e) { return !e.played }) || episodes[0]
    if (next) play(next)
  }
  function seeAll(r) {
    grid = { title: r.title, id: r.id, sort: r.sort || "featured", items: r.items.slice(), next: r.items.length,
             total: r.total, search: false, sortable: r.id !== "continue" }
    if (r.id !== "continue" && r.items.length < 48) loadGridPage()
  }
  function setGridSort(sort) {
    if (!grid || grid.search) return
    grid = { title: grid.title, id: grid.id, sort: sort, items: [], next: 0, total: grid.total, search: false, sortable: true }
    loadGridPage()
  }
  function loadGridPage() {
    if (!grid || grid.search || gridProc.running || grid.next >= grid.total) return
    run(gridProc, ["row", kind, grid.id, grid.sort, String(grid.next)])
  }
  function search(text) {
    text = (text || "").trim()
    if (!text) { grid = null; return }
    grid = { title: "Results for “" + text + "”", id: "", sort: "", items: [], next: 0, total: 0, search: true, sortable: false }
    run(searchProc, ["search", kind, text])
  }
  function requestPage(key, r, start) {
    pageQueue = pageQueue.concat([{ key: key, id: r.id, sort: r.sort, start: start }])
    pumpPages()
  }
  function pumpPages() {
    if (pageProc.running || !pageQueue.length) return
    var job = pageQueue[0]
    pageQueue = pageQueue.slice(1)
    pageProc.job = job
    run(pageProc, ["row", kind, job.id, job.sort, String(job.start)])
  }
  function toggleFavorite(item) {
    if (!item) return
    var on = !item.favorite
    run(favoriteProc, ["favorite", item.seriesId || item.id, on ? "on" : "off"])
    var copy = Object.assign({}, item); copy.favorite = on
    if (detail && detail.id === item.id) detail = copy
  }

  onVisibleChanged: if (visible && !rows.length) reload()
  Component.onCompleted: if (visible) reload()
  onClosed: { detail = null; grid = null }

  Shortcut {
    sequence: "Escape"
    onActivated: {
      if (win.detail) win.detail = null
      else if (win.grid) win.grid = null
      else win.visible = false
    }
  }
  Shortcut { sequence: "Ctrl+F"; onActivated: searchBox.forceActiveFocus() }

  // ---------------------------------------------------------------- processes
  Process {
    id: browseProc
    stdout: StdioCollector { id: browseOut; waitForEnd: true }
    onExited: {
      win.loading = false
      var d = win.parse(browseOut.text)
      if (!d.ok) { win.errorText = d.error || "Could not load"; return }
      win.rowViews = ({})
      win.rows = d.rows
      win.featured = d.hero
      if (d.quality) win.quality = d.quality
    }
  }
  Process {
    id: pageProc
    property var job: null
    stdout: StdioCollector { id: pageOut; waitForEnd: true }
    onExited: {
      var d = win.parse(pageOut.text), view = pageProc.job ? win.rowViews[pageProc.job.key] : null
      if (d.ok && view) view.appendPage(d)
      win.pumpPages()
    }
  }
  Process {
    id: gridProc
    stdout: StdioCollector { id: gridOut; waitForEnd: true }
    onExited: {
      var d = win.parse(gridOut.text)
      if (!d.ok || !win.grid || d.id !== win.grid.id || d.sort !== win.grid.sort) return
      var g = Object.assign({}, win.grid)
      g.items = g.items.concat(d.items); g.next = d.next || (g.next + d.items.length); g.total = d.total
      win.grid = g
    }
  }
  Process {
    id: searchProc
    stdout: StdioCollector { id: searchOut; waitForEnd: true }
    onExited: {
      var d = win.parse(searchOut.text)
      if (!win.grid || !win.grid.search) return
      var g = Object.assign({}, win.grid)
      g.items = d.ok ? d.items : []; g.total = g.items.length; g.next = g.total
      win.grid = g
      if (!d.ok) win.errorText = d.error
    }
  }
  Process {
    id: seasonsProc
    stdout: StdioCollector { id: seasonsOut; waitForEnd: true }
    onExited: {
      var d = win.parse(seasonsOut.text)
      if (!d.ok || !win.detail) return
      win.seasons = d.items
      var target = d.items.find(function(s) { return win.wantSeasonId !== "" && s.id === win.wantSeasonId })
        || d.items.find(function(s) { return s.number > 0 && s.unplayed !== 0 }) || d.items[0]
      if (target) win.pickSeason(target.id)
    }
  }
  Process {
    id: showProc
    stdout: StdioCollector { id: showOut; waitForEnd: true }
    onExited: {
      var d = win.parse(showOut.text)
      if (d.ok && d.item) win.open(d.item, d.seasonId)
      else win.errorText = d.error || "Show not found"
    }
  }
  function pickSeason(id) { seasonId = id; episodes = []; run(episodesProc, ["episodes", detail.id, id]) }
  Process {
    id: episodesProc
    stdout: StdioCollector { id: episodesOut; waitForEnd: true }
    onExited: { var d = win.parse(episodesOut.text); if (d.ok) win.episodes = d.items }
  }
  Process { id: favoriteProc }
  Process {
    id: tiersProc
    stdout: StdioCollector { id: tiersOut; waitForEnd: true }
    onExited: {
      win.tiersLoading = false
      var d = win.parse(tiersOut.text)
      if (d.ok && win.detail && d.id === win.detail.id) {
        win.tiers = d.tiers
        win.tiersChecked = true
        if (!d.tiers.length) { var m = win.deadIds; m[d.id] = true; win.deadIds = m }
      }
    }
  }
  Process { id: qualityProc }

  // Hover preview, debounced so sweeping across a row doesn't flicker the hero.
  property var hoverCandidate: null
  Timer { id: hoverTimer; interval: 160; onTriggered: win.hovered = win.hoverCandidate }
  function hoverItem(it) { hoverCandidate = it; hoverTimer.restart() }

  // ---------------------------------------------------------------- surface
  Rectangle {
    id: surface
    anchors.fill: parent
    radius: win.u(18)
    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.9)
    border.width: 1
    border.color: win.fg(0.08)
    clip: true

    // Hero backdrop with a cross-fade between previews.
    Item {
      id: heroArt
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: Math.min(parent.height * 0.48, win.u(400))

      property string src: win.preview && win.preview.backdrop ? win.preview.backdrop : ""
      property bool showA: true
      onSrcChanged: {
        if (showA) { backB.source = src; showA = false } else { backA.source = src; showA = true }
      }
      Image {
        id: backA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: true
        sourceSize.width: 1280
        opacity: heroArt.showA && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
      }
      Image {
        id: backB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: true
        sourceSize.width: 1280
        opacity: !heroArt.showA && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
      }
      // Fades: left for text, bottom into the rows.
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.96) }
          GradientStop { position: 0.45; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.55) }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.35) }
          GradientStop { position: 0.55; color: "transparent" }
          GradientStop { position: 1.0; color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.97) }
        }
      }

      Column {
        id: heroText
        anchors { left: parent.left; leftMargin: win.u(36); bottom: parent.bottom; bottomMargin: win.u(26) }
        width: Math.min(parent.width * 0.5, win.u(560))
        spacing: win.u(8)
        visible: !!win.preview
        Text {
          width: parent.width
          text: win.preview ? (win.preview.title || "") : ""
          color: win.foreground
          font.family: win.fontFamily
          font.pixelSize: win.u(34)
          font.bold: true
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.WordWrap
          style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.35)
        }
        Text {
          width: parent.width
          text: win.preview && win.preview.type === "episode" ? win.preview.subtitle + "   " + win.metaLine(win.preview) : win.metaLine(win.preview)
          color: win.fg(0.8)
          font.family: win.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: win.preview ? (win.preview.overview || "") : ""
          color: win.fg(0.72)
          font.family: win.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
          lineHeight: 1.15
        }
        Row {
          spacing: win.u(10)
          topPadding: win.u(6)
          Pill {
            primary: true
            text: win.preview && win.preview.position > 30 && !win.preview.played ? "󰐊  Resume " + win.hhmm(win.preview.position) : "󰐊  Play"
            onClicked: win.preview.type === "series" ? win.open(win.preview) : win.play(win.preview)
          }
          Pill { text: "󰋽  Details"; visible: !!win.preview && win.preview.type !== "episode"; onClicked: win.open(win.preview) }
          Pill {
            objectName: "browse-hero-episodes"
            text: "󰒺  Seasons & episodes"
            visible: !!win.preview && win.preview.type === "episode"
            onClicked: win.openEpisodesOf(win.preview)
          }
        }
      }
    }

    // Top bar: section switch, search, quality, close.
    Row {
      id: topBar
      anchors { left: parent.left; leftMargin: win.u(28); top: parent.top; topMargin: win.u(18) }
      spacing: win.u(10)
      Rectangle {
        height: win.u(34); width: switchRow.width + win.u(6); radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1; border.color: win.fg(0.1)
        Row {
          id: switchRow
          anchors.centerIn: parent
          Repeater {
            model: [{ id: "movie", name: "󰿎  Movies" }, { id: "series", name: "󰟴  Series" }]
            Rectangle {
              required property var modelData
              width: label.implicitWidth + win.u(26); height: win.u(28); radius: height / 2
              color: win.kind === modelData.id ? win.accent : (sm.containsMouse ? win.fg(0.08) : "transparent")
              Behavior on color { ColorAnimation { duration: 160 } }
              Text {
                id: label
                anchors.centerIn: parent
                text: modelData.name
                color: win.kind === modelData.id ? Color.background : win.foreground
                font.family: win.fontFamily; font.pixelSize: Style.font.body; font.bold: win.kind === modelData.id
              }
              MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.setKind(modelData.id) }
            }
          }
        }
      }
    }
    Row {
      anchors { right: parent.right; rightMargin: win.u(22); top: parent.top; topMargin: win.u(18) }
      spacing: win.u(10)
      Rectangle {
        width: win.u(280); height: win.u(34); radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.35)
        border.width: 1; border.color: searchBox.activeFocus ? win.accent : win.fg(0.1)
        Text {
          id: searchIcon
          anchors { left: parent.left; leftMargin: win.u(12); verticalCenter: parent.verticalCenter }
          text: "󰍉"; color: win.fg(0.6); font.family: win.fontFamily; font.pixelSize: Style.font.body
        }
        TextInput {
          id: searchBox
          objectName: "browse-search"
          anchors { left: searchIcon.right; leftMargin: win.u(8); right: parent.right; rightMargin: win.u(12); verticalCenter: parent.verticalCenter }
          color: win.foreground
          font.family: win.fontFamily; font.pixelSize: Style.font.body
          clip: true
          selectByMouse: true
          onAccepted: win.search(text)
          Keys.onEscapePressed: { text = ""; win.grid = null; focus = false }
          Text {
            visible: !parent.text && !parent.activeFocus
            text: win.kind === "series" ? "Search series" : "Search movies"
            color: win.fg(0.45); font: parent.font
          }
        }
      }
      Pill {
        objectName: "browse-quality"
        text: "󰕧  " + (win.quality === 2160 ? "4K" : win.quality === 1440 ? "2K" : win.quality + "p")
        tip: "Maximum stream quality"
        onClicked: win.cycleQuality()
      }
      Pill { text: "󰑓"; tip: "Reload"; onClicked: win.reload() }
      Pill { text: "󰅖"; tip: "Close"; onClicked: win.visible = false }
    }

    // Rows
    ListView {
      id: rowList
      objectName: "browse-rows"
      anchors { left: parent.left; right: parent.right; top: heroArt.bottom; bottom: parent.bottom; topMargin: -win.u(10) }
      visible: !win.grid
      clip: true
      spacing: win.u(14)
      model: win.rows
      bottomMargin: win.u(24)
      boundsBehavior: Flickable.StopAtBounds
      cacheBuffer: 900
      delegate: Item {
        id: rowItem
        required property var modelData
        required property int index
        readonly property string key: modelData.id + "|" + (modelData.sort || "")
        width: rowList.width
        height: header.height + strip.height + win.u(6)
        property int next: modelData.items.length
        property int total: modelData.total || modelData.items.length
        property bool requested: false
        ListModel { id: cards }
        Component.onCompleted: {
          for (var i = 0; i < modelData.items.length; i++) cards.append({ it: modelData.items[i] })
          var map = win.rowViews; map[key] = rowItem; win.rowViews = map
        }
        function appendPage(d) {
          for (var i = 0; i < d.items.length; i++) cards.append({ it: d.items[i] })
          next = d.next || (next + d.items.length)
          total = d.total
          requested = false
        }
        function maybeMore() {
          if (requested || modelData.id === "continue" || next >= total) return
          if (strip.contentX + strip.width > strip.contentWidth - win.u(600)) { requested = true; win.requestPage(key, modelData, next) }
        }

        Row {
          id: header
          x: win.u(36)
          height: win.u(28)
          spacing: win.u(10)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.modelData.title
            color: win.foreground
            font.family: win.fontFamily; font.pixelSize: Style.font.title + 2; font.bold: true
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.total > 0 ? String(rowItem.total) : ""
            color: win.fg(0.4)
            font.family: win.fontFamily; font.pixelSize: Style.font.caption
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "See all  ›"
            color: seeAllMouse.containsMouse ? win.accent : win.fg(0.55)
            font.family: win.fontFamily; font.pixelSize: Style.font.caption
            MouseArea { id: seeAllMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: { var r = Object.assign({}, rowItem.modelData); r.items = []; for (var i = 0; i < cards.count; i++) r.items.push(cards.get(i).it); r.total = rowItem.total; win.seeAll(r) } }
          }
        }
        ListView {
          id: strip
          anchors { top: header.bottom; topMargin: win.u(4) }
          width: parent.width
          height: win.u(rowItem.modelData.id === "continue" ? 150 : 236)
          orientation: ListView.Horizontal
          spacing: win.u(12)
          leftMargin: win.u(36); rightMargin: win.u(36)
          clip: false
          model: cards
          boundsBehavior: Flickable.StopAtBounds
          cacheBuffer: 1200
          onContentXChanged: rowItem.maybeMore()
          delegate: PosterCard {
            required property var it
            item: it
            visible: !win.isDead(it)
            width: visible ? implicitCardWidth : -strip.spacing
            wide: rowItem.modelData.id === "continue"
            height: strip.height - win.u(14)
          }
          // Wheel over a row scrolls it sideways with Shift, vertical otherwise (falls through).
          WheelHandler {
            acceptedModifiers: Qt.ShiftModifier
            onWheel: function(e) { strip.flick(-(e.angleDelta.y || e.angleDelta.x) * 12, 0) }
          }
        }
        // Arrows that appear on hover for mouse users.
        StripArrow { anchors.left: parent.left; y: strip.y; height: strip.height - win.u(14); dir: -1; target: strip; shown: rowHover.hovered && !strip.atXBeginning }
        StripArrow { anchors.right: parent.right; y: strip.y; height: strip.height - win.u(14); dir: 1; target: strip; shown: rowHover.hovered && !strip.atXEnd }
        HoverHandler { id: rowHover }
      }
    }

    Text {
      anchors.centerIn: rowList
      visible: !win.grid && (win.loading || win.errorText !== "") && !win.rows.length
      text: win.loading ? "Loading your library…" : win.errorText
      color: win.fg(0.55)
      font.family: win.fontFamily; font.pixelSize: Style.font.title
    }

    // See-all / search grid
    Item {
      id: gridPane
      anchors { left: parent.left; right: parent.right; top: heroArt.bottom; bottom: parent.bottom; topMargin: -win.u(10) }
      visible: !!win.grid
      Row {
        id: gridHeader
        x: win.u(36)
        height: win.u(34)
        spacing: win.u(12)
        Pill { text: "󰁍  Back"; anchors.verticalCenter: parent.verticalCenter; onClicked: win.grid = null }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: win.grid ? win.grid.title : ""
          color: win.foreground
          font.family: win.fontFamily; font.pixelSize: Style.font.title + 4; font.bold: true
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: win.grid && win.grid.total ? win.grid.total + " titles" : (win.grid && win.grid.search && searchProc.running ? "Searching…" : "")
          color: win.fg(0.45)
          font.family: win.fontFamily; font.pixelSize: Style.font.caption
        }
      }
      Row {
        anchors { right: parent.right; rightMargin: win.u(28); verticalCenter: gridHeader.verticalCenter }
        spacing: win.u(6)
        visible: !!win.grid && win.grid.sortable
        Repeater {
          model: [{ id: "featured", name: "Featured" }, { id: "rating", name: "Top rated" }, { id: "newest", name: "Newest" }, { id: "az", name: "A–Z" }]
          Pill {
            required property var modelData
            text: modelData.name
            primary: !!win.grid && win.grid.sort === modelData.id
            onClicked: win.setGridSort(modelData.id)
          }
        }
      }
      GridView {
        id: gridView
        objectName: "browse-grid"
        anchors { left: parent.left; right: parent.right; top: gridHeader.bottom; bottom: parent.bottom; topMargin: win.u(10); leftMargin: win.u(36) }
        clip: true
        readonly property real cardW: win.u(150)
        cellWidth: Math.floor((width - win.u(24)) / Math.max(1, Math.floor((width - win.u(24)) / (cardW + win.u(14)))))
        cellHeight: cardW * 1.5 + win.u(18)
        model: win.grid ? win.grid.items : []
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 1200
        onContentYChanged: if (contentY + height > contentHeight - win.u(500)) win.loadGridPage()
        delegate: PosterCard {
          required property var modelData
          item: modelData
          width: gridView.cardW
          height: gridView.cardW * 1.5
        }
      }
    }

    // Detail sheet
    Rectangle {
      id: sheetScrim
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)
      opacity: win.detail ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      MouseArea { anchors.fill: parent; onClicked: win.detail = null; onWheel: function(e) { e.accepted = true } }

      Rectangle {
        id: sheet
        objectName: "browse-detail"
        anchors.centerIn: parent
        width: Math.min(parent.width - win.u(80), win.u(980))
        height: Math.min(parent.height - win.u(70), win.u(640))
        radius: win.u(18)
        clip: true
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.97)
        border.width: 1; border.color: win.fg(0.1)
        scale: win.detail ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }   // swallow clicks

        Image {
          id: sheetBack
          anchors { left: parent.left; right: parent.right; top: parent.top }
          height: win.u(300)
          source: win.detail ? win.detail.backdrop : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true; sourceSize.width: 1280
          opacity: status === Image.Ready ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 300 } }
        }
        Rectangle {
          anchors.fill: sheetBack
          gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: sheet.color }
          }
        }
        Pill { anchors { right: parent.right; top: parent.top; margins: win.u(14) } text: "󰅖"; onClicked: win.detail = null }

        Rectangle {
          id: sheetPoster
          x: win.u(30); y: win.u(150)
          width: win.u(170); height: width * 1.5
          radius: win.u(12)
          clip: true
          color: win.fg(0.08)
          border.width: 1; border.color: win.fg(0.14)
          Image {
            anchors.fill: parent
            source: win.detail ? (win.detail.poster || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true; sourceSize.height: 480
          }
        }
        Column {
          id: sheetInfo
          anchors { left: sheetPoster.right; leftMargin: win.u(24); right: parent.right; rightMargin: win.u(30) }
          y: win.u(190)
          spacing: win.u(8)
          Text {
            width: parent.width
            text: win.detail ? win.detail.title : ""
            color: win.foreground
            font.family: win.fontFamily; font.pixelSize: win.u(30); font.bold: true
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: win.metaLine(win.detail)
            color: win.fg(0.75)
            font.family: win.fontFamily; font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Row {
            spacing: win.u(10)
            topPadding: win.u(4)
            Pill {
              objectName: "browse-detail-play"
              primary: !win.noStreams
              opacity: win.noStreams ? 0.45 : 1
              enabled: !win.noStreams
              text: {
                var d = win.detail
                if (!d) return ""
                if (d.type === "series") {
                  var e = win.episodes.find(function(x) { return !x.played })
                  return e ? "󰐊  Play S" + e.season + "·E" + e.episode : "󰐊  Play"
                }
                return d.position > 30 && !d.played ? "󰐊  Resume " + win.hhmm(d.position) : "󰐊  Play"
              }
              onClicked: win.playDetail()
            }
            Pill {
              text: win.detail && win.detail.favorite ? "󰋑  In favorites" : "󰋕  Favorite"
              onClicked: win.toggleFavorite(win.detail)
            }
          }
          // Quality: what this title really has (movies), or the cap choice (series).
          Row {
            objectName: "browse-tiers"
            spacing: win.u(6)
            visible: !!win.detail
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: win.tiersLoading ? "Checking streams…" : win.noStreams ? "No streams available for this title yet" : "Quality"
              color: win.fg(0.55)
              font.family: win.fontFamily; font.pixelSize: Style.font.caption
              rightPadding: win.u(4)
            }
            Repeater {
              model: win.detail && win.detail.type === "series"
                ? [720, 1080, 1440, 2160].map(function(t) { return { tier: t, cached: true, label: "" } })
                : win.tiers
              Pill {
                required property var modelData
                height: win.u(28)
                text: (modelData.tier === 2160 ? "4K" : modelData.tier === 1440 ? "2K" : modelData.tier + "p")
                  + (modelData.cached ? "" : "  ·  slow")
                tip: modelData.label
                primary: win.quality === modelData.tier
                onClicked: win.playAt(modelData.tier)
              }
            }
          }
          Text {
            width: parent.width
            text: win.detail ? (win.detail.overview || "") : ""
            color: win.fg(0.75)
            font.family: win.fontFamily; font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            maximumLineCount: win.detail && win.detail.type === "series" ? 3 : 8
            elide: Text.ElideRight
            lineHeight: 1.2
          }
        }

        // Series: seasons + episodes
        Item {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: sheetPoster.bottom; topMargin: win.u(16); margins: win.u(30) }
          visible: !!win.detail && win.detail.type === "series"
          ListView {
            id: seasonPills
            width: parent.width; height: win.u(36)
            orientation: ListView.Horizontal
            spacing: win.u(6)
            model: win.seasons
            clip: true
            delegate: Pill {
              required property var modelData
              text: modelData.number > 0 ? "Season " + modelData.number : modelData.name
              primary: win.seasonId === modelData.id
              onClicked: win.pickSeason(modelData.id)
            }
          }
          ListView {
            anchors { top: seasonPills.bottom; topMargin: win.u(10); left: parent.left; right: parent.right; bottom: parent.bottom }
            orientation: ListView.Horizontal
            spacing: win.u(12)
            clip: true
            model: win.episodes
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
              id: ep
              required property var modelData
              height: ListView.view ? ListView.view.height : win.u(170)
              width: Math.max(win.u(150), (height - win.u(26)) * 16 / 9)
              Rectangle {
                id: epThumb
                width: parent.width; height: parent.height - win.u(26)
                radius: win.u(10); clip: true
                color: win.fg(0.06)
                border.width: epMouse.containsMouse ? 2 : 0; border.color: win.accent
                Image {
                  anchors.fill: parent
                  source: ep.modelData.thumb || ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true; sourceSize.width: 400
                }
                Rectangle {
                  anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                  height: 3; color: win.fg(0.15)
                  visible: ep.modelData.position > 0 && ep.modelData.runtime > 0
                  Rectangle { height: parent.height; color: win.accent; width: parent.width * Math.min(1, ep.modelData.position / Math.max(1, ep.modelData.runtime)) }
                }
                Text {
                  anchors.centerIn: parent
                  text: "󰐊"; font.pixelSize: win.u(30); color: "white"
                  opacity: epMouse.containsMouse ? 0.95 : 0
                  Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Text {
                  anchors { right: parent.right; top: parent.top; margins: win.u(6) }
                  visible: ep.modelData.played
                  text: "󰄬"; color: win.accent; font.pixelSize: Style.font.title
                }
              }
              Text {
                anchors { top: epThumb.bottom; topMargin: win.u(6) }
                width: parent.width
                text: ep.modelData.subtitle
                color: win.foreground
                font.family: win.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                elide: Text.ElideRight
              }
              MouseArea { id: epMouse; anchors.fill: epThumb; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.play(ep.modelData) }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- components
  component Pill: Rectangle {
    id: pill
    property string text: ""
    property string tip: ""
    property bool primary: false
    signal clicked()
    height: win.u(34)
    width: pillLabel.implicitWidth + win.u(text.length <= 2 ? 20 : 30)
    radius: height / 2
    color: primary ? (pillMouse.containsMouse ? Qt.lighter(win.accent, 1.12) : win.accent)
                   : (pillMouse.containsMouse ? win.fg(0.16) : Qt.rgba(0, 0, 0, 0.35))
    border.width: primary ? 0 : 1
    border.color: win.fg(0.12)
    scale: pillMouse.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 90 } }
    Text {
      id: pillLabel
      anchors.centerIn: parent
      text: pill.text
      color: pill.primary ? Color.background : win.foreground
      font.family: win.fontFamily; font.pixelSize: Style.font.body; font.bold: pill.primary
    }
    MouseArea { id: pillMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
  }

  component StripArrow: Rectangle {
    id: arrow
    property int dir: 1
    property var target: null
    property bool shown: false
    width: win.u(44)
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 150 } }
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: arrow.dir < 0 ? Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.9) : "transparent" }
      GradientStop { position: 1.0; color: arrow.dir > 0 ? Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.9) : "transparent" }
    }
    Text { anchors.centerIn: parent; text: arrow.dir > 0 ? "󰅂" : "󰅁"; color: win.foreground; font.pixelSize: win.u(26) }
    MouseArea {
      anchors.fill: parent; cursorShape: Qt.PointingHandCursor
      onClicked: {
        var t = arrow.target
        var dest = Math.max(t.originX - t.leftMargin, Math.min(t.contentX + arrow.dir * t.width * 0.8, t.contentWidth + t.originX - t.width + t.rightMargin))
        scrollAnim.target = t; scrollAnim.to = dest; scrollAnim.restart()
      }
    }
    NumberAnimation { id: scrollAnim; property: "contentX"; duration: 420; easing.type: Easing.OutCubic }
  }

  component PosterCard: Item {
    id: card
    property var item: ({})
    property bool wide: false
    readonly property real implicitCardWidth: wide ? height * 16 / 9 * 0.92 : height / 1.5
    width: implicitCardWidth
    readonly property bool hot: cardMouse.containsMouse || playMouse.containsMouse || epsMouse.containsMouse
    z: hot ? 2 : 0

    Rectangle {
      id: frame
      anchors.fill: parent
      radius: win.u(12)
      color: win.fg(0.06)
      clip: true
      scale: card.hot ? 1.05 : 1
      Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      border.width: card.hot ? 2 : 1
      border.color: card.hot ? win.accent : win.fg(0.07)

      Image {
        id: art
        anchors.fill: parent
        source: card.wide ? (card.item.backdrop || card.item.thumb || card.item.poster || "") : (card.item.poster || "")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: true
        sourceSize.height: card.wide ? 300 : 360
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260 } }
      }
      Text {
        anchors.centerIn: parent
        width: parent.width - win.u(16)
        visible: art.status !== Image.Ready
        text: card.item.title || ""
        color: win.fg(0.55)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.family: win.fontFamily; font.pixelSize: Style.font.caption
      }
      // Bottom info on hover (and always on wide continue cards)
      Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.5
        opacity: card.hot || card.wide ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
        }
        Column {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: win.u(10); bottomMargin: win.u(12) }
          spacing: 2
          Text {
            width: parent.width
            text: card.item.title || ""
            color: "white"
            font.family: win.fontFamily; font.pixelSize: Style.font.body; font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: card.item.type === "episode" ? card.item.subtitle
                : [card.item.year || "", card.item.rating ? "★ " + card.item.rating : ""].filter(function(p) { return p }).join("  ")
            color: Qt.rgba(1, 1, 1, 0.75)
            font.family: win.fontFamily; font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
      // Rating badge
      Rectangle {
        anchors { right: parent.right; top: parent.top; margins: win.u(7) }
        visible: !card.wide && !!card.item.rating && !card.hot
        height: win.u(20); width: badge.implicitWidth + win.u(12); radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.6)
        Text { id: badge; anchors.centerIn: parent; text: "★ " + card.item.rating; color: "white"; font.family: win.fontFamily; font.pixelSize: Style.font.caption }
      }
      // Favorite marker
      Text {
        anchors { left: parent.left; top: parent.top; margins: win.u(8) }
        visible: !!card.item.favorite
        text: "󰋑"; color: win.accent; font.pixelSize: Style.font.title
      }
      // Progress
      Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 4
        visible: (card.item.position || 0) > 0 && (card.item.runtime || 0) > 0 && !card.item.played
        color: Qt.rgba(1, 1, 1, 0.2)
        Rectangle { height: parent.height; color: win.accent; width: parent.width * Math.min(1, card.item.position / Math.max(1, card.item.runtime)) }
      }
      // Episodes of this show (episode cards, e.g. Continue after autoplay)
      Rectangle {
        objectName: "browse-card-episodes"
        anchors { right: parent.right; top: parent.top; margins: win.u(7) }
        visible: card.item.type === "episode"
        opacity: card.hot ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        height: win.u(26); width: epsLabel.implicitWidth + win.u(16); radius: height / 2
        color: epsMouse.containsMouse ? win.accent : Qt.rgba(0, 0, 0, 0.65)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3)
        Text { id: epsLabel; anchors.centerIn: parent; text: "󰒺  Episodes"; color: "white"; font.family: win.fontFamily; font.pixelSize: Style.font.caption }
        MouseArea { id: epsMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.openEpisodesOf(card.item) }
        z: 4
      }
      // Quick play on hover (movies / episodes)
      Rectangle {
        anchors.centerIn: parent
        width: win.u(46); height: width; radius: width / 2
        visible: card.item.type !== "series"
        opacity: card.hot ? 1 : 0
        scale: playMouse.containsMouse ? 1.12 : 1
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 120 } }
        color: playMouse.containsMouse ? win.accent : Qt.rgba(0, 0, 0, 0.55)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
        Text { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; text: "󰐊"; color: "white"; font.pixelSize: win.u(22) }
        MouseArea { id: playMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.play(card.item) }
        z: 3
      }
    }
    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) win.hoverItem(card.item)
      onClicked: win.open(card.item)
      onDoubleClicked: win.play(card.item)
      z: -1
    }
  }
}
