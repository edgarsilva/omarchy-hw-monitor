import QtQuick
import QtQuick.Effects
import qs.Commons

// A vertical gauge: a rounded body that fills from the bottom in proportion to
// load. No battery terminal on top — at 7px wide that nub read as an
// unexplained line above the gauge rather than as a battery cap.
//
// It replaces the horizontal meter this widget used to draw underneath each
// group. That meter needed a second row, which pushed the glyphs off the bar's
// optical center and left them out of line with every other icon in the bar.
// A gauge sits on the same row as the glyph, so a group stays one line tall.
Item {
  id: root

  property real ratio: 0
  property color fillColor: Color.foreground
  property color trackColor: Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.14)
  property color borderColor: Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.4)
  // Set while the reading is past its critical threshold. A blurred copy of the
  // fill underneath makes a full gauge catch the eye in peripheral vision,
  // which is the whole point of having it there.
  property bool glow: false

  property real bodyWidth: Math.max(6, Style.space(7))
  property real bodyHeight: Math.max(11, Style.space(14))
  readonly property real inset: 1

  readonly property real clampedRatio: Math.max(0, Math.min(1, ratio))

  implicitWidth: bodyWidth
  implicitHeight: bodyHeight

  Item {
    id: gauge
    anchors.centerIn: parent
    width: root.bodyWidth
    height: root.bodyHeight

    Rectangle {
      id: body
      anchors.fill: parent
      radius: Math.max(2, Style.space(2))
      color: root.trackColor
      border.width: 1
      border.color: root.borderColor

      MultiEffect {
        anchors.centerIn: fill
        width: fill.width
        height: fill.height
        source: fill
        visible: root.glow && fill.height > 0
        autoPaddingEnabled: true
        blurEnabled: true
        blurMax: 16
        blur: 1.0
        brightness: 0.25
      }

      Rectangle {
        id: fill
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.inset
        radius: Math.max(1, body.radius - root.inset)
        color: root.fillColor
        layer.enabled: root.glow

        // A live-but-idle reading still deserves a visible mark, so anything
        // above zero draws at least a sliver rather than nothing.
        readonly property real span: body.height - root.inset * 2
        height: root.clampedRatio <= 0 ? 0 : Math.max(2, Math.round(span * root.clampedRatio))

        Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 240 } }
      }
    }
  }
}
