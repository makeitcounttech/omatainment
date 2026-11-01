import QtQuick

// Overlay transport for the OmaTainment video engine, shared by the popup and the
// floating window. Gradient scrim, slim hover-growing scrubber, compact icons.
Item {
  id: controls

  required property var engine
  property color accent: "#7dd3fc"
  property string fontFamily: "monospace"
  property bool compact: false
  property bool shown: true
  property bool showPopOut: true
  property bool showDock: false
  property bool showClose: false

  signal closeClicked()

  // Scales with the player: comfortable in the small corner window, bigger in fullscreen.
  readonly property real iconSize: Math.round(Math.max(compact ? 18 : 20, Math.min(30, width / 34)))
  readonly property bool scrubbing: scrubMouse.pressed

  height: column.implicitHeight + (compact ? 8 : 12)
  readonly property bool menuOpen: qualityChip.open || shareChip.open
  onShownChanged: if (!shown) { qualityChip.open = false; shareChip.open = false }
  opacity: shown || scrubbing || menuOpen ? 1 : 0
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: -parent.height * 0.6
    gradient: Gradient {
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.45) }
      GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.78) }
    }
  }

  component Glyph: Item {
    id: glyph
    property string icon: ""
    property string tip: ""
    property bool active: false
    property real size: controls.iconSize
    property bool chip: false            // glass background, for the window actions
    signal clicked()
    width: size + (chip ? 20 : 16)
    height: size + (chip ? 16 : 14)
    scale: glyphMouse.pressed ? 0.92 : (glyphMouse.containsMouse ? 1.08 : 1)
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Rectangle {
      anchors.fill: parent
      anchors.margins: glyph.chip ? 2 : 0
      radius: height / 2
      color: glyphMouse.pressed ? Qt.rgba(1, 1, 1, 0.28)
        : glyphMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18)
        : glyph.chip ? Qt.rgba(1, 1, 1, 0.09) : "transparent"
      border.width: glyph.chip ? 1 : 0
      border.color: Qt.rgba(1, 1, 1, glyphMouse.containsMouse ? 0.3 : 0.14)
      Behavior on color { ColorAnimation { duration: 110 } }
    }
    // Label above the button on hover, so every icon says what it does.
    Rectangle {
      visible: glyph.tip !== "" && glyphMouse.containsMouse
      anchors.bottom: parent.top
      anchors.bottomMargin: 6
      anchors.horizontalCenter: parent.horizontalCenter
      width: tipText.implicitWidth + 16
      height: tipText.implicitHeight + 8
      radius: height / 2
      color: Qt.rgba(0, 0, 0, 0.82)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.14)
      z: 10
      Text {
        id: tipText
        anchors.centerIn: parent
        text: glyph.tip
        color: "white"
        font.family: controls.fontFamily
        font.pixelSize: 11
      }
    }
    Text {
      anchors.centerIn: parent
      text: glyph.icon
      color: glyph.active ? controls.accent : (glyphMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.86))
      font.family: controls.fontFamily
      font.pixelSize: glyph.size
    }
    MouseArea {
      id: glyphMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: glyph.clicked()
    }
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: controls.compact ? 8 : 12
    anchors.rightMargin: controls.compact ? 8 : 12
    anchors.bottomMargin: controls.compact ? 4 : 6
    spacing: controls.compact ? 0 : 2

    // Scrubber: thin at rest, thicker with a knob on hover; previews while dragging.
    Item {
      id: scrubber
      objectName: "video-scrubber"
      width: parent.width
      height: 18
      property real preview: 0
      readonly property bool hot: scrubMouse.containsMouse || scrubMouse.pressed
      readonly property real duration: controls.engine.durationSec
      readonly property real fraction: duration > 0
        ? Math.max(0, Math.min(1, (scrubMouse.pressed ? preview : controls.engine.positionSec) / duration)) : 0

      Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: scrubber.hot ? 7 : 4
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.22)
        Behavior on height { NumberAnimation { duration: 120 } }
        Rectangle {
          width: parent.width * scrubber.fraction
          height: parent.height
          radius: parent.radius
          color: controls.accent
        }
      }
      Rectangle {
        visible: scrubber.hot && scrubber.duration > 0
        width: 15; height: 15; radius: 7.5
        color: "white"
        x: Math.max(0, Math.min(parent.width - width, parent.width * scrubber.fraction - width / 2))
        anchors.verticalCenter: parent.verticalCenter
      }
      Rectangle {
        visible: scrubMouse.containsMouse && scrubber.duration > 0
        color: Qt.rgba(0, 0, 0, 0.75)
        radius: 4
        width: hoverTime.implicitWidth + 10
        height: hoverTime.implicitHeight + 4
        y: -height - 2
        x: Math.max(0, Math.min(parent.width - width, scrubMouse.mouseX - width / 2))
        Text {
          id: hoverTime
          anchors.centerIn: parent
          text: controls.engine.formatTime(scrubber.duration * Math.max(0, Math.min(1, scrubMouse.mouseX / scrubber.width)))
          color: "white"
          font.family: controls.fontFamily
          font.pixelSize: 11
        }
      }
      MouseArea {
        id: scrubMouse
        anchors.fill: parent
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        hoverEnabled: true
        enabled: controls.engine.player.seekable && scrubber.duration > 0
        cursorShape: Qt.PointingHandCursor
        function at(x) { return scrubber.duration * Math.max(0, Math.min(1, x / width)) }
        onPressed: function(mouse) { scrubber.preview = at(mouse.x) }
        onPositionChanged: function(mouse) { if (pressed) scrubber.preview = at(mouse.x) }
        onReleased: function(mouse) { controls.engine.seek(at(mouse.x)) }
      }
    }

    Item {
      width: parent.width
      height: playGlyph.height

      Row {
        id: leftGroup
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        // Drop the least important pieces first when the right-hand actions need the room.
        readonly property real room: parent.width - rightGroup.width - 12
        readonly property bool showSkip: room > playGlyph.width + volGlyph.width + timeText.implicitWidth + playGlyph.width * 2
        readonly property bool showTotal: room > playGlyph.width + volGlyph.width + 150

        Glyph {
          id: playGlyph
          objectName: "video-play"
          icon: controls.engine.playing ? "󰏤" : "󰐊"
          size: controls.iconSize + 3
          onClicked: controls.engine.togglePlay()
        }
        Glyph { icon: "󰴪"; tip: "Back 10s"; visible: leftGroup.showSkip; onClicked: controls.engine.skip(-10) }
        Glyph { icon: "󰵱"; tip: "Forward 10s"; visible: leftGroup.showSkip; onClicked: controls.engine.skip(10) }

        Glyph {
          id: volGlyph
          icon: controls.engine.audio.muted || controls.engine.audio.volume === 0 ? "󰝟"
            : controls.engine.audio.volume < 0.5 ? "󰖀" : "󰕾"
          onClicked: controls.engine.audio.muted = !controls.engine.audio.muted
        }

        // Inline volume, revealed on hover.
        Item {
          id: volume
          width: volHover.hovered || volMouse.pressed ? 64 : 0
          height: playGlyph.height
          clip: true
          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
          HoverHandler { id: volHover }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 56; height: 3; radius: 1.5
            color: Qt.rgba(1, 1, 1, 0.25)
            Rectangle {
              width: parent.width * (controls.engine.audio.muted ? 0 : controls.engine.audio.volume)
              height: parent.height; radius: parent.radius
              color: "white"
            }
          }
          MouseArea {
            id: volMouse
            anchors.fill: parent
            onPressed: function(mouse) { controls.engine.setVolume(mouse.x / 56) }
            onPositionChanged: function(mouse) { if (pressed) controls.engine.setVolume(mouse.x / 56) }
          }
        }

        Text {
          id: timeText
          visible: leftGroup.room > playGlyph.width + volGlyph.width + implicitWidth + 8
          anchors.verticalCenter: parent.verticalCenter
          leftPadding: 6
          text: controls.engine.formatTime(scrubMouse.pressed ? scrubber.preview : controls.engine.positionSec)
            + (controls.engine.durationSec <= 0 ? "  ·  LIVE"
               : leftGroup.showTotal ? " / " + controls.engine.formatTime(controls.engine.durationSec) : "")
          color: Qt.rgba(1, 1, 1, 0.82)
          font.family: controls.fontFamily
          font.pixelSize: controls.compact ? 12 : 13
        }
      }

      Row {
        id: rightGroup
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // Stream chip: shows the quality cap; opens Quality (720p…4K) + Source (provider) menu.
        Item {
          id: qualityChip
          objectName: "video-quality"
          visible: controls.engine.isRemux
          width: qualityLabel.implicitWidth + 22
          height: controls.iconSize + 16
          property bool open: false
          Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: height / 2
            color: qualityMouse.containsMouse || qualityChip.open ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, qualityMouse.containsMouse ? 0.3 : 0.14)
          }
          Text {
            id: qualityLabel
            anchors.centerIn: parent
            text: controls.engine.qualityName(controls.engine.maxQuality)
            color: "white"
            font.family: controls.fontFamily
            font.pixelSize: Math.round(controls.iconSize * 0.62)
            font.bold: true
          }
          MouseArea {
            id: qualityMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { qualityChip.open = !qualityChip.open; if (qualityChip.open) controls.engine.refreshSources() }
          }
        }
        // Share: continue on the phone, or copy a link for any other device.
        Item {
          id: shareChip
          objectName: "video-share"
          visible: controls.engine.canSendToPhone
          width: controls.iconSize + 20
          height: controls.iconSize + 16
          property bool open: false
          Glyph {
            anchors.fill: parent
            chip: true
            icon: "󰒖"
            tip: shareChip.open ? "" : "Share"
            active: shareChip.open
            onClicked: shareChip.open = !shareChip.open
          }
          Rectangle {
            visible: shareChip.open
            anchors.bottom: parent.top
            anchors.bottomMargin: 8
            anchors.right: parent.right
            width: Math.max(200, shareCol.widest + 44)
            height: shareCol.implicitHeight + 12
            radius: 14
            color: Qt.rgba(0.05, 0.05, 0.06, 0.92)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)
            z: 20
            Column {
              id: shareCol
              anchors.centerIn: parent
              width: parent.width - 12
              property real widest: 0
              Repeater {
                model: [
                  { icon: "󰄜", label: controls.engine.isRemux ? "Continue on Fold (Moonfin)" : "Continue on Fold (NewPipe)", act: "phone" },
                  { icon: "󰆏", label: controls.engine.isRemux ? "Copy IMDb link" : "Copy link at this time", act: "copy" }
                ]
                Rectangle {
                  required property var modelData
                  width: shareCol.width
                  height: 32
                  radius: 9
                  color: shareMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                  Row {
                    anchors.left: parent.left; anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text { text: modelData.icon; color: controls.accent; font.family: controls.fontFamily; font.pixelSize: 15 }
                    Text {
                      text: modelData.label; color: "white"; font.family: controls.fontFamily; font.pixelSize: 13
                      Component.onCompleted: shareCol.widest = Math.max(shareCol.widest, implicitWidth + 25)
                    }
                  }
                  MouseArea {
                    id: shareMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      shareChip.open = false
                      if (parent.modelData.act === "phone") controls.engine.sendToPhone()
                      else controls.engine.copyLink()
                    }
                  }
                }
              }
            }
          }
        }
        Glyph {
          objectName: "video-youtube"
          tip: "Open in YouTube"
          chip: true
          visible: !controls.engine.isRemux
          icon: "󰗃"
          onClicked: controls.engine.openYouTube(null)
        }
        Glyph {
          objectName: "video-prev-episode"
          tip: controls.engine.previousEpisode ? "Back to " + (controls.engine.previousEpisode.artist || "previous episode") : ""
          chip: true
          visible: !!controls.engine.previousEpisode
          icon: "󰒮"
          onClicked: controls.engine.goBackEpisode()
        }
        Glyph {
          objectName: "video-next-episode"
          tip: "Next episode"
          chip: true
          visible: !!controls.engine.nextEpisode
          icon: "󰒭"
          onClicked: controls.engine.playVideo(controls.engine.nextEpisode)
        }
        Glyph {
          objectName: "video-fullscreen"
          tip: controls.engine.fullscreen ? "Exit fullscreen  (F / Esc)" : "Fullscreen  (F)"
          chip: true
          icon: controls.engine.fullscreen ? "󰊔" : "󰊓"
          size: controls.iconSize + 2
          onClicked: controls.engine.toggleFullscreen()
        }
        Glyph {
          objectName: "video-float"
          tip: "Pop out"
          chip: true
          visible: controls.showPopOut
          icon: "󰹑"
          onClicked: controls.engine.popOut()
        }
        Glyph {
          objectName: "video-dock"
          tip: "Back to panel"
          chip: true
          visible: controls.showDock && !controls.engine.fullscreen
          icon: "󰁜"
          onClicked: controls.engine.dock()
        }
        Glyph {
          objectName: "video-close"
          tip: "Close"
          chip: true
          visible: controls.showClose
          icon: "󰅖"
          onClicked: controls.closeClicked()
        }
      }
    }
  }

  // Stream menu (opens upward from the controls, right-aligned): quality cap + every source with its
  // provider, so a bad torrent/debrid link can be swapped without leaving the player.
  Rectangle {
    id: streamMenu
    objectName: "video-stream-menu"
    visible: qualityChip.open && controls.engine.isRemux
    anchors.right: parent.right
    anchors.rightMargin: controls.compact ? 8 : 12
    anchors.bottom: parent.bottom
    anchors.bottomMargin: column.anchors.bottomMargin + playRowHeight + 6
    readonly property real playRowHeight: controls.iconSize + 16
    readonly property real room: (controls.parent ? controls.parent.height : 480) - playRowHeight - 24
    width: Math.min(400, controls.width - 24)
    height: Math.min(menuCol.implicitHeight + 16, Math.max(140, room))
    radius: 14
    color: Qt.rgba(0.05, 0.05, 0.06, 0.94)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.14)
    z: 30
    clip: true
    // Clicks inside the menu must not reach the video below (pause on click).
    MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: function(w) { w.accepted = true } }

    Column {
      id: menuCol
      x: 8; y: 8
      width: parent.width - 16
      spacing: 4

      Text {
        text: "Quality"
        color: Qt.rgba(1, 1, 1, 0.5)
        font.family: controls.fontFamily
        font.pixelSize: 11
        leftPadding: 6
      }
      Row {
        spacing: 4
        leftPadding: 2
        Repeater {
          model: controls.engine.qualityOptions
          Rectangle {
            required property int modelData
            readonly property bool current: controls.engine.maxQuality === modelData
            objectName: "video-quality-" + modelData
            width: qText.implicitWidth + 22
            height: 28
            radius: 14
            color: current ? controls.accent : (qMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06))
            Text {
              id: qText
              anchors.centerIn: parent
              text: controls.engine.qualityName(modelData)
              color: current ? "black" : "white"
              font.family: controls.fontFamily
              font.pixelSize: 12
              font.bold: current
            }
            MouseArea {
              id: qMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { qualityChip.open = false; controls.engine.setQuality(parent.modelData) }
            }
          }
        }
      }

      Item { width: 1; height: 4 }
      Row {
        width: parent.width
        Text {
          text: "Source" + (controls.engine.sourceList.length ? "  ·  " + controls.engine.sourceList.length : "")
          color: Qt.rgba(1, 1, 1, 0.5)
          font.family: controls.fontFamily
          font.pixelSize: 11
          leftPadding: 6
        }
        Text {
          visible: controls.engine.switchingSource
          text: "   checking…"
          color: controls.accent
          font.family: controls.fontFamily
          font.pixelSize: 11
        }
      }
      Text {
        visible: controls.engine.sourceList.length === 0
        width: parent.width
        text: "Loading sources…"
        color: Qt.rgba(1, 1, 1, 0.5)
        font.family: controls.fontFamily
        font.pixelSize: 12
        leftPadding: 6
      }
      ListView {
        id: sourceListView
        objectName: "video-source-list"
        width: parent.width
        height: Math.min(contentHeight, Math.max(44, streamMenu.room - 110))
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: controls.engine.sourceList
        spacing: 2
        delegate: Rectangle {
          id: srcRow
          required property var modelData
          required property int index
          readonly property bool current: modelData.id === controls.engine.mediaSourceId
          readonly property bool bad: !!modelData.bad && !current
          objectName: "video-source-" + index
          width: sourceListView.width
          height: 42
          radius: 9
          color: current ? Qt.rgba(1, 1, 1, 0.10) : (srcMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
          opacity: bad ? 0.55 : 1
          Column {
            anchors.left: parent.left; anchors.leftMargin: 10
            anchors.right: status.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: srcRow.modelData.label || "Unknown stream"
              color: srcRow.current ? controls.accent : "white"
              font.family: controls.fontFamily
              font.pixelSize: 12
              font.bold: srcRow.current
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: srcRow.modelData.provider
              color: Qt.rgba(1, 1, 1, 0.55)
              font.family: controls.fontFamily
              font.pixelSize: 11
            }
          }
          Text {
            id: status
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: srcRow.current ? "󰄬" : srcRow.bad ? srcRow.modelData.bad.replace(" on debrid", "") : ""
            color: srcRow.current ? controls.accent : Qt.rgba(1, 0.75, 0.6, 0.9)
            font.family: controls.fontFamily
            font.pixelSize: srcRow.current ? 14 : 10
          }
          MouseArea {
            id: srcMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: srcRow.current ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (!srcRow.current) { qualityChip.open = false; controls.engine.switchSource(srcRow.modelData.id) }
          }
        }
      }
    }
  }
}
