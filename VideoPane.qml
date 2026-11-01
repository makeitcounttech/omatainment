import QtQuick
import QtMultimedia
import qs.Commons
import qs.Ui

// Video view inside the OmaTainment popup. Playback state lives in the persistent
// VideoEngine (BarWidget), so closing the popup keeps audio playing.
Column {
  id: pane

  required property var engine
  property QtObject bar: null
  property color foreground: Color.foreground
  property color dim: foreground
  property color muted: foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool panelOpened: false
  property real listCap: Style.space(190)

  // Browse (search + lists) collapses while something plays.
  property bool browseOpen: !engine.hasVideo || engine.isRemux
  property string subTab: "continue"

  property alias searchField: videoSearch
  readonly property var continueItems: engine.history.filter(function(e) { return !e.finished })

  signal closeRequested()

  spacing: Style.space(8)

  onPanelOpenedChanged: {
    if (panelOpened) { engine.refreshHistory(); engine.panelOutput = screenFrame.output }
    else if (engine.panelOutput === screenFrame.output) engine.panelOutput = null
  }
  Component.onCompleted: engine.panelOutput = panelOpened ? screenFrame.output : null
  Component.onDestruction: if (engine.panelOutput === screenFrame.output) engine.panelOutput = null

  Connections {
    target: pane.engine
    function onHasVideoChanged() { pane.browseOpen = !pane.engine.hasVideo }
  }

  function submit() {
    var text = videoSearch.text.trim()
    if (/^(https?:\/\/)?(www\.|m\.)?(youtube\.com|youtu\.be)\//.test(text)) engine.playVideo({ url: text })
    else if (engine.startSearch(text)) subTab = "search"
  }

  // ---------------------------------------------------------------- player
  VideoScreen {
    id: screenFrame
    width: parent.width
    engine: pane.engine
    foreground: pane.foreground
    accent: pane.accent
    fontFamily: pane.fontFamily
  }

  // Now playing line + browse toggle
  Item {
    visible: pane.engine.hasVideo
    width: parent.width
    height: Math.max(nowColumn.implicitHeight, browseToggle.height)

    Column {
      id: nowColumn
      anchors.left: parent.left
      anchors.right: browseToggle.left
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
        text: pane.engine.notice !== "" ? pane.engine.notice : pane.engine.videoArtist
        color: pane.engine.notice !== "" ? pane.accent : pane.dim
        font.family: pane.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Rectangle {
      id: browseToggle
      objectName: "video-browse-toggle"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: browseLabel.implicitWidth + Style.space(22)
      height: Style.space(28)
      radius: height / 2
      color: pane.browseOpen ? Qt.rgba(pane.accent.r, pane.accent.g, pane.accent.b, 0.16)
        : browseMouse.containsMouse ? Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.08)
        : Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.04)
      Behavior on color { ColorAnimation { duration: 120 } }
      Text {
        id: browseLabel
        anchors.centerIn: parent
        text: pane.browseOpen ? "󰅃  Hide" : "󰍉  Browse"
        color: pane.browseOpen ? pane.accent : pane.dim
        font.family: pane.fontFamily
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        id: browseMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          pane.browseOpen = !pane.browseOpen
          if (pane.browseOpen) videoSearch.forceActiveFocus()
        }
      }
    }
  }

  // ---------------------------------------------------------------- browse
  Column {
    id: browse
    objectName: "video-browse"
    visible: pane.browseOpen
    width: parent.width
    spacing: Style.space(8)

    Row {
      width: parent.width
      spacing: Style.space(8)

      TextField {
        id: videoSearch
        width: parent.width - videoSearchBtn.width - Style.space(8)
        placeholderText: "Search YouTube or paste a link…"
        font.family: pane.fontFamily
        font.pixelSize: Style.font.body
        onAccepted: pane.submit()
        Keys.onEscapePressed: pane.closeRequested()
      }

      PanelActionButton {
        id: videoSearchBtn
        iconText: pane.engine.searching ? "󰑮" : "󰍉"
        tooltipText: "Search"
        anchors.verticalCenter: parent.verticalCenter
        onClicked: pane.submit()
      }
    }

    // Segmented pill, same language as DÆMON's Local | Cloud.
    Rectangle {
      width: parent.width
      height: Style.space(30)
      radius: height / 2
      color: Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.05)

      Row {
        anchors.fill: parent
        anchors.margins: Style.space(2)

        Repeater {
          model: [
            { id: "continue", name: "󰋚  Continue watching" + (pane.continueItems.length ? "  " + pane.continueItems.length : "") },
            { id: "search", name: "󰍉  Results" + (pane.engine.results.length ? "  " + pane.engine.results.length : "") }
          ]

          Rectangle {
            width: parent.width / 2
            height: parent.height
            radius: height / 2
            color: pane.subTab === modelData.id ? pane.accent
              : (subMouse.containsMouse ? Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.06) : "transparent")
            Behavior on color { ColorAnimation { duration: 140 } }

            Text {
              anchors.centerIn: parent
              text: modelData.name
              color: pane.subTab === modelData.id ? Color.background : (subMouse.containsMouse ? pane.foreground : pane.dim)
              font.family: pane.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: pane.subTab === modelData.id
            }

            MouseArea {
              id: subMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                pane.subTab = modelData.id
                if (modelData.id === "continue") pane.engine.refreshHistory()
              }
            }
          }
        }
      }
    }

    ListView {
      id: videoList
      objectName: "video-list"
      width: parent.width
      height: Math.max(Style.space(48), Math.min(pane.listCap, count * Style.space(60)))
      clip: true
      spacing: Style.space(2)
      model: pane.subTab === "search" ? pane.engine.results : pane.continueItems

      delegate: Rectangle {
        width: videoList.width
        height: Style.space(58)
        radius: Style.space(10)
        readonly property bool current: (modelData.url || "") === pane.engine.videoUrl && pane.engine.hasVideo
        readonly property real progress: modelData.length > 0 ? Math.min(1, (modelData.position || 0) / modelData.length) : 0
        color: current ? Qt.rgba(pane.accent.r, pane.accent.g, pane.accent.b, 0.14)
          : (rowMouse.containsMouse ? Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.06) : "transparent")
        Behavior on color { ColorAnimation { duration: 110 } }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: pane.engine.playVideo(modelData)
        }

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(6)
          spacing: Style.space(6)

          Column {
            width: parent.width - rowButtons.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: modelData.title || ""
              color: pane.foreground
              font.family: pane.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: pane.subTab === "search"
                ? (modelData.artist || "") + (modelData.duration ? "  ·  " + modelData.duration : "")
                : (modelData.artist || "") + "  ·  " + pane.engine.formatTime(modelData.position) + " / " + pane.engine.formatTime(modelData.length)
              color: pane.dim
              font.family: pane.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Rectangle {
              visible: pane.subTab === "continue"
              width: parent.width
              height: 2
              radius: 1
              color: Qt.rgba(pane.foreground.r, pane.foreground.g, pane.foreground.b, 0.12)
              Rectangle {
                width: parent.width * progress
                height: parent.height
                radius: parent.radius
                color: pane.accent
              }
            }
          }

          Row {
            id: rowButtons
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            opacity: rowMouse.containsMouse || rowHover.hovered ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: 120 } }
            HoverHandler { id: rowHover }

            PanelActionButton {
              iconText: "󰊓"
              tooltipText: "Play in floating window"
              size: Style.space(26)
              onClicked: { pane.engine.playVideo(modelData); pane.engine.popOut() }
            }
            PanelActionButton {
              iconText: "󰗃"
              tooltipText: "Continue on YouTube"
              size: Style.space(26)
              onClicked: pane.engine.openYouTube(modelData)
            }
            PanelActionButton {
              visible: pane.subTab === "continue"
              iconText: "󰅖"
              tooltipText: "Remove from continue watching"
              size: Style.space(26)
              onClicked: pane.engine.removeHistory(modelData.id)
            }
          }
        }
      }
    }

    Text {
      visible: videoList.count === 0
      width: parent.width
      text: pane.subTab === "search"
        ? (pane.engine.searching ? "Searching…" : "Type a search above and press Enter.")
        : "Videos you watch appear here with their saved position."
      color: pane.muted
      font.family: pane.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
