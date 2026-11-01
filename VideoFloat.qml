import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Floating OmaTainment video: a borderless Quickshell window that reuses the engine's
// MediaPlayer, so popping out is instant (no second stream). Hyprland rule in
// ~/.config/hypr/omatainment.lua pins it across workspaces and keeps 16:9 on resize.
FloatingWindow {
  id: win

  required property var engine
  property color accent: "#7dd3fc"
  property string fontFamily: "monospace"

  property string windowTitle: "OmaTainment Video"
  title: windowTitle
  visible: engine.floating && engine.hasVideo
  implicitWidth: 414
  implicitHeight: 233
  minimumSize: Qt.size(280, 158)
  color: "transparent"

  onClosed: engine.dock()          // Super+W: back into the panel, audio keeps playing

  // Apply engine.fullscreen to this window; keep it in sync if the user uses Super+F.
  function applyFullscreen() {
    var target = 'window = "title:^' + win.windowTitle + '$"'
    if (engine.fullscreen) {
      Hyprland.dispatch('hl.dsp.window.pin({' + target + ', action = "off"})')
      Hyprland.dispatch('hl.dsp.window.fullscreen({' + target + ', mode = "fullscreen", action = "set"})')
    } else {
      Hyprland.dispatch('hl.dsp.window.fullscreen({' + target + ', mode = "fullscreen", action = "unset"})')
      Hyprland.dispatch('hl.dsp.window.pin({' + target + ', action = "on"})')
      restoreAfterFullscreen.restart()
    }
  }
  // A saved box is reused only if it is window-sized (not fullscreen) and mostly on a current screen.
  function usable(g) {
    if (!g || g.w < 200 || g.h < 110) return false
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      var sc = screens[i]
      if (g.w >= sc.width * 0.9) continue
      var cx = g.x + g.w / 2, cy = g.y + g.h / 2
      if (cx >= sc.x && cx <= sc.x + sc.width && cy >= sc.y && cy <= sc.y + sc.height) return true
    }
    return false
  }
  // Ordinary window -> pinned corner overlay again, on the workspace you're on now.
  function backToFloating() {
    var t = 'window = "title:^' + win.windowTitle + '$"'
    Hyprland.dispatch('hl.dsp.window.move({' + t + ', workspace = "' + (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1) + '", follow = false})')
    Hyprland.dispatch('hl.dsp.window.float({' + t + ', action = "on"})')
    Hyprland.dispatch('hl.dsp.window.pin({' + t + ', action = "on"})')
    Hyprland.dispatch('hl.dsp.window.tag({' + t + ', tag = "-omatainment-tiled"})')
    win.engine.tiled = false
    restoreAfterFullscreen.restart()
  }
  Connections {
    target: win.engine
    function onFloatRequested() { win.backToFloating() }
  }
  // Saved corner geometry, or the default corner spot (top-right under the bar).
  function placeNormally() {
    var g = win.engine.floatGeometry
    var t = 'window = "title:^' + win.windowTitle + '$"'
    if (!win.usable(g)) {
      var sx = win.screen ? win.screen.x : 0, sw = win.screen ? win.screen.width : 1600
      g = { w: 414, h: 233, x: sx + sw - 414 - 22, y: (win.screen ? win.screen.y : 0) + 41 }
      win.engine.floatGeometry = g
    }
    Hyprland.dispatch('hl.dsp.window.resize({' + t + ', x = ' + Math.round(g.w) + ', y = ' + Math.round(g.h) + '})')
    Hyprland.dispatch('hl.dsp.window.move({' + t + ', x = ' + Math.round(g.x) + ', y = ' + Math.round(g.y) + '})')
  }
  Timer { id: restoreAfterFullscreen; interval: 160; onTriggered: win.placeNormally() }
  Connections {
    target: win.engine
    function onFullscreenChanged() { fullscreenApply.restart() }
  }
  Timer { id: fullscreenApply; interval: 120; onTriggered: win.applyFullscreen() }
  Shortcut { sequence: "F"; onActivated: win.engine.toggleFullscreen() }
  Shortcut { sequence: "Escape"; enabled: win.engine.fullscreen; onActivated: win.engine.exitFullscreen() }
  Shortcut { sequence: "Space"; onActivated: win.engine.togglePlay() }
  Shortcut { sequence: "Left"; onActivated: win.engine.skip(-10) }
  Shortcut { sequence: "Right"; onActivated: win.engine.skip(10) }
  onVisibleChanged: {
    engine.floatOutput = visible ? out : null
    if (visible) restoreGeometry.restart()
  }
  Component.onCompleted: if (visible) { engine.floatOutput = out; restoreGeometry.restart(); if (engine.fullscreen) fullscreenApply.restart() }

  // Put a restored window back where it was (after a shell restart), then keep
  // tracking moves/resizes so the next restart can do the same.
  Timer {
    id: restoreGeometry
    interval: 180
    onTriggered: {
      var g = win.engine.floatGeometry
      if (win.usable(g)) {
        Hyprland.dispatch('hl.dsp.window.resize({window = "title:^' + win.windowTitle + '$", x = ' + Math.round(g.w) + ', y = ' + Math.round(g.h) + '})')
        Hyprland.dispatch('hl.dsp.window.move({window = "title:^' + win.windowTitle + '$", x = ' + Math.round(g.x) + ', y = ' + Math.round(g.y) + '})')
      }
      geometryPoll.running = true
    }
  }
  Timer {
    id: geometryPoll
    interval: 2000
    repeat: true
    onTriggered: if (!clients.running) clients.running = true
  }
  Process {
    id: clients
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector { id: clientsOut; waitForEnd: true }
    onExited: {
      try {
        var list = JSON.parse(clientsOut.text)
        for (var i = 0; i < list.length; i++) {
          if (list[i].title !== win.windowTitle || list[i].pid !== Quickshell.processId) continue
          var c = list[i], g = win.engine.floatGeometry
          var isTiled = c.floating === false
          if (isTiled !== win.engine.tiled) win.engine.tiled = isTiled
          if (isTiled) break
          var isFull = (c.fullscreen || 0) !== 0
          if (isFull !== win.engine.fullscreen) {
            // Changed outside OmaTainment (Super+F): follow it.
            if (isFull) win.engine.fullscreen = true
            else win.engine.exitFullscreen()
            break
          }
          if (isFull || restoreAfterFullscreen.running) break
          if (!g || g.x !== c.at[0] || g.y !== c.at[1] || g.w !== c.size[0] || g.h !== c.size[1])
            win.engine.floatGeometry = { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1] }
          break
        }
      } catch (e) {}
    }
  }
  Component.onDestruction: if (engine && engine.floatOutput === out) engine.floatOutput = null

  Rectangle {
    id: surface
    anchors.fill: parent
    radius: 12
    color: "black"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
    clip: true

    VideoOutput {
      id: out
      anchors.fill: parent
      anchors.margins: 1
      fillMode: VideoOutput.PreserveAspectFit
    }

    HoverHandler { id: hover }

    Timer {
      id: idle
      interval: 2200
      onTriggered: surface.chromeShown = false
    }
    property bool chromeShown: true
    readonly property bool chrome: chromeShown || !win.engine.playing

    // Moving the pointer reveals chrome; it fades after a short idle period.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      property point pressPos
      onPositionChanged: function(mouse) {
        surface.chromeShown = true
        idle.restart()
        if (pressed && (Math.abs(mouse.x - pressPos.x) > 4 || Math.abs(mouse.y - pressPos.y) > 4)) win.startSystemMove()
      }
      onPressed: function(mouse) { pressPos = Qt.point(mouse.x, mouse.y) }
      onClicked: win.engine.togglePlay()
      onDoubleClicked: win.engine.toggleFullscreen()
      onExited: idle.restart()
    }

    // Title strip
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 36
      opacity: surface.chrome ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 180 } }
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.65) }
        GradientStop { position: 1; color: "transparent" }
      }
      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        anchors.rightMargin: 28
        text: win.engine.videoTitle
        color: Qt.rgba(1, 1, 1, 0.9)
        elide: Text.ElideRight
        font.family: win.fontFamily
        font.pixelSize: 12
      }
    }

    Text {
      anchors.centerIn: parent
      visible: win.engine.buffering
      text: "󰑮"
      color: Qt.rgba(1, 1, 1, 0.8)
      font.family: win.fontFamily
      font.pixelSize: 28
      RotationAnimation on rotation { running: win.engine.buffering; loops: Animation.Infinite; from: 0; to: 360; duration: 1100 }
    }

    VideoControls {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      engine: win.engine
      accent: win.accent
      fontFamily: win.fontFamily
      compact: true
      shown: surface.chrome && (hover.hovered || !win.engine.playing)
      showPopOut: false
      showDock: true
      showClose: true
      onCloseClicked: win.engine.stopVideo()
    }

    // Resize from every corner and edge: invisible grips, the top-right glyph is just a hint
    // (Super+right-drag also resizes). Corners sit above edges so they win the overlap.
    Text {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 5
      visible: surface.chrome
      text: "◥"
      color: Qt.rgba(1, 1, 1, 0.45)
      font.pixelSize: 11
    }
    Repeater {
      model: [
        { edges: Qt.TopEdge, cursor: Qt.SizeVerCursor, x: 0.5, y: 0, w: -1, h: 0 },
        { edges: Qt.BottomEdge, cursor: Qt.SizeVerCursor, x: 0.5, y: 1, w: -1, h: 0 },
        { edges: Qt.LeftEdge, cursor: Qt.SizeHorCursor, x: 0, y: 0.5, w: 0, h: -1 },
        { edges: Qt.RightEdge, cursor: Qt.SizeHorCursor, x: 1, y: 0.5, w: 0, h: -1 },
        { edges: Qt.TopEdge | Qt.LeftEdge, cursor: Qt.SizeFDiagCursor, x: 0, y: 0, w: 1, h: 1 },
        { edges: Qt.TopEdge | Qt.RightEdge, cursor: Qt.SizeBDiagCursor, x: 1, y: 0, w: 1, h: 1 },
        { edges: Qt.BottomEdge | Qt.LeftEdge, cursor: Qt.SizeBDiagCursor, x: 0, y: 1, w: 1, h: 1 },
        { edges: Qt.BottomEdge | Qt.RightEdge, cursor: Qt.SizeFDiagCursor, x: 1, y: 1, w: 1, h: 1 }
      ]
      MouseArea {
        id: grip
        readonly property int edges: modelData.edges
        readonly property int band: 8
        readonly property int corner: 18
        // w/h: -1 = span the side between corners, 0 = thin band, 1 = corner square.
        width: modelData.w < 0 ? surface.width - 2 * corner : (modelData.w ? corner : band)
        height: modelData.h < 0 ? surface.height - 2 * corner : (modelData.h ? corner : band)
        x: modelData.x * (surface.width - width)
        y: modelData.y * (surface.height - height)
        z: modelData.w > 0 ? 3 : 2
        cursorShape: modelData.cursor
        onPressed: win.startSystemResize(grip.edges)
      }
    }
  }
}
