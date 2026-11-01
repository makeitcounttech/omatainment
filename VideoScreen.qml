import QtQuick
import QtMultimedia
import qs.Commons

// 16:9 video surface for the OmaTainment popup: the panel sink of the shared VideoEngine,
// status/placeholder text and the overlay controls. Used by YouTube and Movies/Series.
Rectangle {
  id: screen

  required property var engine
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string placeholder: "Search a video or continue where you left off"
  property alias output: videoOut

  height: Math.round(width * 9 / 16)
  radius: Style.space(12)
  color: "black"
  border.width: 1
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  clip: true

  // Poster backdrop while loading / floating (Remux titles).
  Image {
    anchors.fill: parent
    source: screen.engine.backdrop || ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    visible: source !== "" && (screen.engine.buffering || screen.engine.floating)
    opacity: 0.35
  }

  VideoOutput {
    id: videoOut
    anchors.fill: parent
    anchors.margins: 1
    fillMode: VideoOutput.PreserveAspectFit
    visible: !screen.engine.floating
  }

  HoverHandler { id: screenHover }

  MouseArea {
    anchors.fill: parent
    cursorShape: screen.engine.hasVideo ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: screen.engine.togglePlay()
    onDoubleClicked: screen.engine.toggleFullscreen()
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - Style.space(32)
    spacing: Style.space(6)
    visible: !screen.engine.hasVideo || screen.engine.floating || screen.engine.buffering || screen.engine.errorText !== ""

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: screen.engine.errorText !== "" ? "󰀦"
        : screen.engine.buffering ? "󰑮"
        : screen.engine.tiled ? "󰖯"
        : screen.engine.floating ? "󰊓" : "󰕧"
      color: screen.engine.errorText !== "" ? Color.urgent : Qt.rgba(1, 1, 1, 0.7)
      font.family: screen.fontFamily
      font.pixelSize: Style.font.title * 1.8
      RotationAnimation on rotation {
        running: screen.engine.buffering && screen.engine.errorText === ""
        loops: Animation.Infinite; from: 0; to: 360; duration: 1100
        onRunningChanged: if (!running) parent.rotation = 0
      }
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: screen.engine.errorText !== "" ? screen.engine.errorText
        : screen.engine.resolving ? (screen.engine.isRemux ? "Finding the best cached stream…" : "Loading video…")
        : screen.engine.buffering ? "Buffering…"
        : screen.engine.tiled ? "Playing as a desktop window"
        : screen.engine.floating ? "Playing in the floating window"
        : screen.placeholder
      color: Qt.rgba(1, 1, 1, 0.75)
      font.family: screen.fontFamily
      font.pixelSize: Style.font.caption
    }
    // Desktop-window state: bring it back.
    Row {
      objectName: "video-tiled-actions"
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)
      topPadding: Style.space(6)
      visible: screen.engine.tiled
      Repeater {
        model: [
          { icon: "󰁜", label: "Back to panel", act: "dock" },
          { icon: "󰹑", label: "Back to floating", act: "float" }
        ]
        Rectangle {
          required property var modelData
          height: Style.space(30)
          width: actLabel.implicitWidth + Style.space(26)
          radius: height / 2
          color: actMouse.containsMouse ? Qt.rgba(screen.accent.r, screen.accent.g, screen.accent.b, 0.9) : Qt.rgba(1, 1, 1, 0.12)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.18)
          Behavior on color { ColorAnimation { duration: 120 } }
          Text {
            id: actLabel
            anchors.centerIn: parent
            text: modelData.icon + "  " + modelData.label
            color: actMouse.containsMouse ? Color.background : "white"
            font.family: screen.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          MouseArea {
            id: actMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: modelData.act === "dock" ? screen.engine.dock() : screen.engine.backToFloating()
          }
        }
      }
    }
  }

  VideoControls {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: screen.engine.hasVideo
    engine: screen.engine
    accent: screen.accent
    fontFamily: screen.fontFamily
    shown: screenHover.hovered || !screen.engine.playing || screen.engine.floating
    showPopOut: !screen.engine.floating
    showDock: screen.engine.floating && !screen.engine.tiled
    showClose: true
    onCloseClicked: screen.engine.stopVideo()
  }
}
