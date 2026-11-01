import QtQuick

// OmaTainment bar icon — same footprint and weight as the other bar glyphs.
//  idle   : monochrome (bar foreground) rounded play mark, no motion
//  hover  : slightly brighter
//  music  : three slim equalizer bars in the accent colour, gently moving with the audio
//  video  : the play mark in the accent colour with a soft, slow breathe
//  busy   : the play mark dims and pulses
//  lanes  : a tiny accent dot when more than one player runs
Item {
  id: mark

  property color accent: "#7dd3fc"
  property color foreground: "white"
  property bool hovered: false
  property bool busy: false
  property bool musicPlaying: false
  property bool videoPlaying: false
  property bool cinemaPlaying: false
  property real energy: 0
  property real pulse: 0
  property real phase: 0

  readonly property bool active: musicPlaying || videoPlaying || cinemaPlaying
  readonly property int lanes: (musicPlaying ? 1 : 0) + (videoPlaying ? 1 : 0) + (cinemaPlaying ? 1 : 0)
  // Softened accent: blended toward the bar foreground so it never glares.
  readonly property color soft: Qt.rgba(accent.r * 0.8 + foreground.r * 0.2,
                                        accent.g * 0.8 + foreground.g * 0.2,
                                        accent.b * 0.8 + foreground.b * 0.2, 1)
  readonly property color ink: active ? soft : foreground

  opacity: hovered ? 1 : (active ? 0.95 : 0.82)
  Behavior on opacity { NumberAnimation { duration: 160 } }

  // ---- play mark (idle / video / busy): a rounded triangle drawn with Canvas
  Canvas {
    id: play
    anchors.centerIn: parent
    width: Math.round(parent.width * 0.8)
    height: width
    visible: !mark.musicPlaying
    property color ink: mark.ink
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
      var c = getContext("2d"), w = width, h = height, r = w * 0.12
      c.reset()
      var ax = w * 0.18, ay = h * 0.08, bx = w * 0.94, by = h * 0.5, cx = w * 0.18, cy = h * 0.92
      c.beginPath()
      c.moveTo(ax, ay + r)
      c.arcTo(ax, ay, bx, by, r)
      c.arcTo(bx, by, cx, cy, r)
      c.arcTo(cx, cy, ax, ay, r)
      c.closePath()
      c.fillStyle = ink
      c.fill()
    }
    scale: 1
    SequentialAnimation on scale {
      running: play.visible && (mark.videoPlaying || mark.cinemaPlaying || mark.busy)
      loops: Animation.Infinite
      NumberAnimation { to: mark.busy ? 0.82 : 1.06; duration: mark.busy ? 520 : 1400; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: mark.busy ? 520 : 1400; easing.type: Easing.InOutSine }
      onRunningChanged: if (!running) play.scale = 1
    }
    opacity: mark.busy ? 0.6 : 1
    Behavior on opacity { NumberAnimation { duration: 200 } }
  }

  // ---- music: three slim bars
  Item {
    id: bars
    objectName: "opus-bars"
    anchors.centerIn: parent
    width: Math.round(parent.width * 0.72)
    height: Math.round(parent.height * 0.76)
    visible: mark.musicPlaying && !mark.busy
    Repeater {
      model: 3
      Rectangle {
        readonly property real wave: (Math.sin(mark.phase * 1.3 - index * 1.4) + 1) / 2
        width: Math.max(2, Math.round(bars.width / 3.6))
        height: Math.max(width, bars.height * (0.3 + wave * (0.35 + mark.energy * 0.35)))
        radius: width / 2
        x: index * (bars.width - width) / 2
        y: bars.height - height
        color: mark.soft
        Behavior on height { NumberAnimation { duration: 90 } }
      }
    }
  }

  // ---- several players running: tiny dot top-right
  Rectangle {
    visible: mark.lanes > 1
    width: Math.max(3, Math.round(mark.width * 0.18))
    height: width
    radius: width / 2
    color: mark.soft
    anchors.right: parent.right
    anchors.top: parent.top
  }
}
