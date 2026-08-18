import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// RAM, CPU, and GPU as a row of gauges: a glyph, a battery-style capsule that
// fills and warms toward the theme's urgent color as load climbs, and the
// temperature beside it.
//
// Every group is one line tall and vertically centered, so the glyphs sit on
// the same optical center as every other icon in the bar. The numbers live in
// the gauges rather than in the bar itself — set `showValues` to put
// percentages back on the row, or ask over IPC for the full breakdown.
//
// Left click opens btop through the Omarchy launcher, which already has a
// Hyprland rule making org.omarchy.btop float and center. Right click walks
// the display modes and remembers the choice; middle click resamples.
BarWidget {
  id: root
  moduleName: "io.github.edgarsilva.hw-monitor"

  // Three states, cycled by right click:
  //   compact  glyph + gauge
  //   full     glyph + gauge + temperature
  //   labels   the old Waybar reading — RAM 19.4/63G · CPU 34% 46° — with the
  //            words spelled out and no glyph or gauge, for when you want the
  //            numbers rather than the shapes
  readonly property var modes: ["compact", "full", "labels"]
  readonly property string mode: {
    var want = String(setting("mode", "full")).trim().toLowerCase()
    return modes.indexOf(want) === -1 ? "full" : want
  }

  // A vertical bar is 28px wide — a glyph and a gauge and nothing else — so it
  // drops the text whatever the mode says.
  readonly property string nextMode: modes[(modes.indexOf(mode) + 1) % modes.length]
  readonly property bool labelled: mode === "labels" && !vertical
  readonly property bool showTemps: mode !== "compact" && !vertical
  readonly property bool showValues: (labelled || boolSetting("showValues", false)) && !vertical
  readonly property bool showGauges: boolSetting("showGauges", true)
  // Clock speed: the CPU's average across every thread, and the GPU's core
  // clock. Off by default — three gauges and two temperatures is already a lot
  // of bar, and a clock that idles at 0.8 tells you less than the gauge does.
  readonly property bool showClocks: boolSetting("showClocks", false) && !vertical

  readonly property bool showRam: boolSetting("showRam", true)
  readonly property bool showCpu: boolSetting("showCpu", true)
  readonly property bool showGpu: boolSetting("showGpu", true)
  readonly property bool fahrenheit: boolSetting("fahrenheit", false)
  readonly property string ramFormat: {
    var want = String(setting("ramFormat", "used/total")).trim().toLowerCase()
    return ["used/total", "used", "percent"].indexOf(want) === -1 ? "used/total" : want
  }

  // One knob for the whole group's scale. 0 follows the theme's bar icon size,
  // and at that size the derived label sizes below land exactly on the theme's
  // own body/caption tokens — so overriding this grows the readout coherently
  // instead of leaving 16px glyphs beside 11px numbers.
  readonly property int iconSizeSetting: intSetting("iconSize", 0, 0, 48)
  readonly property int iconSize: iconSizeSetting > 0 ? iconSizeSetting : Style.bar.iconFont
  readonly property int valueSize: Math.max(9, Math.round(iconSize * 0.92))
  readonly property int labelSize: Math.max(8, Math.round(iconSize * 0.85))

  readonly property int warnPercent: intSetting("warnPercent", 70, 1, 100)
  readonly property int criticalPercent: intSetting("criticalPercent", 90, 1, 100)
  readonly property int warnTempC: intSetting("warnTempC", 75, 1, 150)
  readonly property int criticalTempC: intSetting("criticalTempC", 90, 1, 150)

  readonly property string clickCommand: String(setting("clickCommand", "omarchy-launch-or-focus-tui btop"))

  // Three different silhouettes: a DIMM stick, a pinned chip, and an expansion
  // card with its output ports. Legibility at bar size is the constraint — the
  // font's own cpu_64_bit glyph writes "64" on a chip and collapses into mud,
  // and two chip-shaped glyphs cannot be told apart at all. The card needs
  // ~16px to read; on a 13px bar 󰆧 (cube outline) is the clearer stand-in.
  // Frequency has no glyph of its own in the font, so this is a stand-in: a
  // speedometer for "rate". Its tick marks need ~16px to stay distinct, which
  // the default 13px bar does not give it — at that size 󱑻 (square wave) or
  // 󰥛 (sine wave) hold up better, and an empty string draws the number alone.
  readonly property string clockIcon: String(setting("clockIcon", "󰓅"))

  readonly property string ramIcon: String(setting("ramIcon", ""))
  readonly property string cpuIcon: String(setting("cpuIcon", ""))
  readonly property string gpuIcon: String(setting("gpuIcon", "󰾲"))

  // `omarchy bar set <id> <key> <value>` writes the value as a JSON string
  // unless the caller passes --json, so a boolean setting has to accept "true"
  // as readily as true or it silently ignores half the ways it gets set.
  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (typeof value === "boolean") return value
    var text = String(value).trim().toLowerCase()
    if (["true", "1", "yes", "on"].indexOf(text) !== -1) return true
    if (["false", "0", "no", "off"].indexOf(text) !== -1) return false
    return fallback
  }

  // Rotation, in degrees, per glyph. An expansion card is drawn lying flat; on
  // its end it reads as a card seated in a slot, and stands beside the upright
  // gauge better. The glyph box is square, so any angle fits without clipping.
  readonly property int ramIconRotation: intSetting("ramIconRotation", 0, -360, 360)
  readonly property int cpuIconRotation: intSetting("cpuIconRotation", 0, -360, 360)
  readonly property int gpuIconRotation: intSetting("gpuIconRotation", 0, -360, 360)

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  // ------------------------------------------------------------------ color

  readonly property color base: bar ? bar.barForeground : Color.foreground
  readonly property color hot: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(base, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Every reading shares one visual language: nothing to report stays in the
  // theme foreground, and load mixes it toward urgent in proportion. Themes
  // only guarantee foreground/accent/urgent, so a hand-picked green/amber/red
  // ramp would clash with half of them.
  function warm(from, amount) {
    if (!(amount > 0)) return from
    var t = Math.min(1, amount)
    return Qt.rgba(from.r + (hot.r - from.r) * t,
                   from.g + (hot.g - from.g) * t,
                   from.b + (hot.b - from.b) * t,
                   from.a)
  }

  // A percentage is one or two digits, and letting it size naturally means the
  // whole group — and every widget beside it — jumps sideways each time CPU
  // crosses 9%. Padding the string was the first fix, but a leading space
  // lands between the label and its figure and reads as a disconnect. So
  // reserve the width of the widest value instead and left-align inside it:
  // the figure stays welded to its label and the slack sits after it, next to
  // the temperature, where a gap between two different quantities belongs.
  // How a percentage holds its width, so that a group does not change size as
  // the figure gains a digit and shove every widget beside it sideways:
  //   lead   " 3%" — a leading space. Constant width, nothing moves; the space
  //          is a full character cell, so it sits between a label and its figure.
  //   zero   "03%" — same constant width, but ink instead of a hole.
  //   trail  "3%" with the leftover width reserved after the group. Figures stay
  //          tight, at the cost of ~11px more gap after a percentage group.
  //   none   "3%" at its natural width. Tightest, but the widget resizes every
  //          time a reading crosses 9% and nudges its neighbours sideways.
  readonly property string percentPad: {
    var want = String(setting("percentPad", "zero")).trim().toLowerCase()
    if (want === "space") want = "trail"  // the name this option shipped under
    return ["lead", "zero", "trail", "none"].indexOf(want) === -1 ? "zero" : want
  }

  // How faint that placeholder zero is — below the temperature's own dimming, so
  // it reads as a column marker rather than as a digit.
  readonly property real padOpacity: {
    var n = Number(setting("padOpacity", 0.3))
    return isFinite(n) ? Math.max(0, Math.min(1, n)) : 0.3
  }

  readonly property int percentSlot: Math.ceil(percentMetrics.advanceWidth)

  TextMetrics {
    id: percentMetrics
    font.family: root.fontFamily
    font.pixelSize: root.valueSize
    text: "100%"
  }

  // --------------------------------------------------------------- readings

  Service {
    id: hw
    settings: root.settings
  }

  // In a monospace face the degree sign owns a full character cell but only
  // inks a small ring at the top of it, so it reads as a gap between the
  // temperature and whatever follows. A letter fills the cell instead.
  readonly property string tempFormat: {
    var want = String(setting("tempFormat", "degree")).trim().toLowerCase()
    return ["degree", "unit", "unit-lower", "degree-unit", "bare"].indexOf(want) === -1 ? "degree" : want
  }

  // In "zero" mode the leading zero is its own text so it can be dimmed to the
  // point of being furniture: it holds the column width without being read as
  // part of the number.
  function percentPadFor(value) {
    if (percentPad !== "zero") return ""
    if (!isFinite(value) || value < 0) return ""
    return Math.round(value) < 10 ? "0" : ""
  }

  function percentText(value) {
    if (percentPad === "lead") return Model.padLeft(Model.formatPercent(value), 3)
    return Model.formatPercent(value)
  }

  function tempText(celsius) {
    var figure = Model.tempNumber(celsius, fahrenheit)
    if (figure === "–") return Model.padLeft(figure, 3)

    var unit = fahrenheit ? "F" : "C"
    var text = figure
    if (tempFormat === "degree") text += "°"
    else if (tempFormat === "unit") text += unit
    else if (tempFormat === "unit-lower") text += unit.toLowerCase()
    else if (tempFormat === "degree-unit") text += "°" + unit
    return Model.padLeft(text, 3)
  }

  function ramText() {
    if (ramFormat === "percent") return percentText(hw.memPercent)
    if (!hw.memory) return "–"

    // The label mode reads as a sentence, so it gets the decimal and the unit;
    // the icon modes are a glance next to a gauge, so they stay narrow.
    if (labelled) {
      return Model.formatGibPrecise(Model.gibFromKib(hw.memory.usedKib))
             + "/" + Model.formatGib(Model.gibFromKib(hw.memory.totalKib)) + "G"
    }

    var used = Model.formatGib(Model.gibFromKib(hw.memory.usedKib))
    if (ramFormat === "used") return Model.padLeft(used + "G", 4)
    var total = Model.formatGib(Model.gibFromKib(hw.memory.totalKib))
    return Model.padLeft(used, 3) + "/" + total
  }

  // One entry per group the bar draws. `ratio` fills the gauge, `severity`
  // drives the color, and either can be -1/0 when a machine does not report
  // that sensor.
  readonly property var cells: {
    var out = []

    if (showRam) {
      out.push({
        key: "ram",
        label: "RAM",
        icon: ramIcon,
        iconRotation: ramIconRotation,
        value: ramText(),
        pad: "",
        // Memory's figure has its own width already; a slot would only add slack.
        slotted: false,
        // Memory has no temperature, so its gauge is the whole readout.
        temp: "",
        clock: "",
        ratio: hw.memPercent >= 0 ? hw.memPercent / 100 : 0,
        severity: Model.severity(hw.memPercent, warnPercent, criticalPercent)
      })
    }

    if (showCpu) {
      out.push({
        key: "cpu",
        label: "CPU",
        icon: cpuIcon,
        iconRotation: cpuIconRotation,
        value: percentText(hw.cpuPercent),
        pad: percentPadFor(hw.cpuPercent),
        slotted: percentPad === "trail",
        temp: tempText(hw.cpuTempC),
        clock: Model.padLeft(Model.formatGhzShort(hw.cpuMhz), 3),
        ratio: hw.cpuPercent >= 0 ? hw.cpuPercent / 100 : 0,
        severity: Math.max(Model.severity(hw.cpuPercent, warnPercent, criticalPercent),
                           Model.severity(hw.cpuTempC, warnTempC, criticalTempC))
      })
    }

    if (showGpu && hw.hasGpu) {
      // A card with no load counter (most iGPUs) still has a temperature and
      // VRAM, so fall back to filling the gauge with VRAM pressure.
      var busy = hw.gpuPercent
      var meterValue = busy >= 0 ? busy : hw.gpuVramPercent
      out.push({
        key: "gpu",
        label: "GPU",
        icon: gpuIcon,
        iconRotation: gpuIconRotation,
        value: percentText(meterValue),
        pad: percentPadFor(meterValue),
        slotted: percentPad === "trail",
        temp: tempText(hw.gpuTempC),
        clock: Model.padLeft(Model.formatGhzShort(hw.gpuMhz), 3),
        ratio: meterValue >= 0 ? meterValue / 100 : 0,
        severity: Math.max(Model.severity(busy, warnPercent, criticalPercent),
                           Model.severity(hw.gpuTempC, warnTempC, criticalTempC))
      })
    }

    return out
  }

  // ---------------------------------------------------------------- tooltip
  //
  // The bar tooltip is one line: what the clicks do. The full breakdown is
  // still assembled, but only when something asks for it over IPC — a readout
  // you are already looking at does not need a paragraph explaining itself.

  readonly property string monitorName: {
    var parts = clickCommand.split(/\s+/)
    var last = String(parts[parts.length - 1] || "")
    return last.substring(last.lastIndexOf("/") + 1)
  }

  readonly property string hint: clickCommand === ""
    ? "Hardware"
    : "Click for " + monitorName + " · right click for " + nextMode

  function detail() {
    var lines = []

    var cpu = "CPU  " + Model.formatPercent(hw.cpuPercent)
    if (hw.cpuTempC > 0) cpu += "  ·  " + Model.formatTemp(hw.cpuTempC, fahrenheit) + (fahrenheit ? "F" : "C")
    if (hw.cpuMhz > 0) cpu += "  ·  " + Model.formatGhz(hw.cpuMhz)
    lines.push(cpu)
    if (hw.cpuInfo && hw.cpuInfo.model) {
      lines.push(hw.cpuInfo.model + " · " + hw.cpuInfo.cores + "C/" + hw.cpuInfo.threads + "T")
    }
    if (hw.load) {
      lines.push("Load " + hw.load.one.toFixed(2) + "  " + hw.load.five.toFixed(2) + "  " + hw.load.fifteen.toFixed(2))
    }

    if (hw.memory) {
      lines.push("")
      lines.push("RAM  " + Model.formatGib(Model.gibFromKib(hw.memory.usedKib)) + " / "
                 + Model.formatGib(Model.gibFromKib(hw.memory.totalKib)) + " GiB  ·  "
                 + Model.formatPercent(hw.memory.percent))
      lines.push("Cache " + Model.formatGib(Model.gibFromKib(hw.memory.cachedKib)) + " GiB"
                 + (hw.memory.swapTotalKib > 0
                    ? "  ·  Swap " + Model.formatGib(Model.gibFromKib(hw.memory.swapUsedKib)) + " / "
                      + Model.formatGib(Model.gibFromKib(hw.memory.swapTotalKib)) + " GiB"
                    : ""))
    }

    if (hw.hasGpu) {
      lines.push("")
      var gpu = "GPU  " + Model.formatPercent(hw.gpuPercent)
      if (hw.gpuTempC > 0) gpu += "  ·  " + Model.formatTemp(hw.gpuTempC, fahrenheit) + (fahrenheit ? "F" : "C")
      if (hw.gpuWatts >= 0) gpu += "  ·  " + Model.formatWatts(hw.gpuWatts)
      lines.push(gpu)
      lines.push(String(hw.gpuInfo.name))
      if (hw.gpuVramTotalBytes > 0) {
        lines.push("VRAM " + Model.formatGib(Model.gibFromBytes(hw.gpuVramUsedBytes)) + " / "
                   + Model.formatGib(Model.gibFromBytes(hw.gpuVramTotalBytes)) + " GiB  ·  "
                   + Model.formatPercent(hw.gpuVramPercent))
      }
      var extras = []
      if (hw.gpuRpm >= 0) extras.push("Fan " + Model.formatRpm(hw.gpuRpm))
      if (hw.gpuMhz > 0) extras.push(Model.formatGhz(hw.gpuMhz))
      if (extras.length > 0) lines.push(extras.join("  ·  "))
    }

    return lines.join("\n")
  }

  // ----------------------------------------------------------------- actions

  function refresh() {
    hw.sample()
  }

  // The shell's updateEntryInline replaces the whole entry with whatever it is
  // handed, so the new one has to be built from the config as it stands on disk
  // rather than from this widget's injected copy. Building it from `settings`
  // means a right-click writes back whatever snapshot the widget happens to
  // hold, silently reverting anything changed since — an `omarchy bar set`, or
  // a hand edit of shell.json.
  function currentEntry() {
    var config = root.bar && root.bar.shell ? root.bar.shell.shellConfig : null
    var layout = config && config.bar ? config.bar.layout : null
    var sections = ["left", "center", "right"]
    for (var s = 0; layout && s < sections.length; s++) {
      var entries = layout[sections[s]] || []
      for (var i = 0; i < entries.length; i++) {
        if (entries[i] && String(entries[i].id) === root.moduleName) return entries[i]
      }
    }
    return root.settings || {}
  }

  function cycleMode() {
    var live = currentEntry()

    var from = String(live.mode === undefined || live.mode === null ? mode : live.mode).trim().toLowerCase()
    if (modes.indexOf(from) === -1) from = mode
    var next = modes[(modes.indexOf(from) + 1) % modes.length]

    var entry = { id: root.moduleName }
    for (var key in live) if (key !== "id") entry[key] = live[key]
    entry.mode = next

    // Applied locally first so the readout changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function launchMonitor() {
    if (clickCommand === "") return
    if (root.bar) root.bar.run(clickCommand)
    else Quickshell.execDetached(["bash", "-lc", clickCommand])
  }

  IpcHandler {
    target: "io.github.edgarsilva.hw-monitor"

    function refresh(): void { root.broadcast("refresh") }
    // Not broadcast: the mode is persisted through shell.json, which the bar
    // hands back to every instance. Cycling all of them would toggle the
    // setting once per monitor and land wherever the count left it.
    function cycleMode(): void { root.cycleMode() }
    function status(): string { return root.detail() }
  }

  // ------------------------------------------------------------------ layout
  //
  // One row height for every part of a group — glyph box, gauge, and labels all
  // get the same height and center their own content inside it, so nothing
  // needs vertical anchoring and the row cannot drift off the bar's center.

  readonly property int glyphBox: Math.max(Style.bar.iconCanvas, iconSize + Style.space(2))
  readonly property int contentHeight: Math.max(glyphBox, Style.space(15))
  // The gauge is sized off the glyph beside it, so one knob keeps the whole
  // group in proportion.
  readonly property int gaugeWidth: Math.max(6, Math.round(iconSize * 0.45))
  readonly property int gaugeHeight: Math.max(11, Math.round(iconSize * 0.9))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.cells.length > 0
    tooltipText: root.hint
    horizontalMargin: 5
    fixedWidth: root.vertical ? -1 : Math.ceil(horizontalCells.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Math.ceil(verticalCells.implicitHeight + Style.space(8)) : -1

    onPressed: function(pressedButton) {
      if (pressedButton === Qt.RightButton) root.cycleMode()
      else if (pressedButton === Qt.MiddleButton) root.refresh()
      else root.launchMonitor()
    }

    Row {
      id: horizontalCells
      visible: !root.vertical
      anchors.centerIn: parent
      // One rhythm for every mode: 8px between groups against 3–4px inside one,
      // which is the 2:1 that makes a group read as a unit. With the widget's
      // own 5px edge padding this hands off to the next widget at ~14px, the
      // same gap the bar's own icons sit at.
      spacing: Style.space(8)

      Repeater {
        model: root.cells
        delegate: cell
      }
    }

    Column {
      id: verticalCells
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(5)

      Repeater {
        model: root.cells
        delegate: cell
      }
    }
  }

  // A group: glyph, gauge, and — when there is room and the mode asks for it —
  // the percentage and the temperature.
  Component {
    id: cell

    Row {
      id: group
      required property var modelData
      // A label and its figure are one phrase, so they sit tighter than a glyph
      // sits from its gauge. The gap between groups (set on the row above) does
      // the separating instead.
      spacing: Style.space(root.labelled ? 3 : 4)

      // What a one-digit percentage is short of a three-digit one. Held at the
      // end of the group rather than beside the figure: the group keeps a
      // constant width either way, so nothing in the bar shifts as the number
      // gains a digit, and the leftover reads as part of the gap between groups
      // instead of prising a label away from its number.
      readonly property real slack: root.showValues && modelData.slotted
        ? Math.max(0, root.percentSlot - valueText.implicitWidth - spacing)
        : 0

      // Sized to the glyph's painted bounds rather than to a fixed box. Nerd
      // Font glyphs carry wildly different amounts of their own whitespace — a
      // narrow one like 3D floats in the middle of a 16px cell and reads as an
      // extra 3px of gap on each side, which is why one group looked further
      // from its neighbour than another despite identical spacing.
      TextMetrics {
        id: glyphMetrics
        font.family: root.fontFamily
        font.pixelSize: root.iconSize
        text: modelData.icon
      }

      Item {
        readonly property bool turned: Math.abs(modelData.iconRotation % 180) === 90
        readonly property real inkWidth: turned
          ? glyphMetrics.tightBoundingRect.height
          : glyphMetrics.tightBoundingRect.width

        visible: !root.labelled
        width: visible ? Math.max(1, Math.ceil(inkWidth)) : 0
        height: root.contentHeight

        // OpticalGlyph nudges a glyph to center its painted bounds rather than
        // its character cell, and that nudge is horizontal by construction.
        // Rotating the item rotates the nudge with it, so on a rotated glyph it
        // lands as a vertical shift and drops the icon off the row's
        // centerline. Rotated glyphs get a plain centered Text instead.
        OpticalGlyph {
          anchors.fill: parent
          visible: modelData.iconRotation === 0
          text: modelData.icon
          fontFamily: root.fontFamily
          fontSize: root.iconSize
          color: root.warm(root.base, modelData.severity)
          Behavior on color { ColorAnimation { duration: 240 } }
        }

        Text {
          anchors.centerIn: parent
          visible: modelData.iconRotation !== 0
          rotation: modelData.iconRotation
          text: modelData.icon
          color: root.warm(root.base, modelData.severity)
          font.family: root.fontFamily
          font.pixelSize: root.iconSize
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 240 } }
        }
      }

      Gauge {
        visible: root.showGauges && !root.labelled
        height: root.contentHeight
        bodyWidth: root.gaugeWidth
        bodyHeight: root.gaugeHeight
        ratio: modelData.ratio
        fillColor: root.warm(root.base, modelData.severity)
        trackColor: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.14)
        borderColor: Qt.rgba(root.base.r, root.base.g, root.base.b, 0.4)
        glow: modelData.severity >= 1
      }

      Text {
        visible: root.labelled
        height: root.contentHeight
        text: modelData.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: root.labelSize
        font.bold: true
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
      }

      Row {
        visible: root.showValues
        height: root.contentHeight
        spacing: 0

        Text {
          visible: modelData.pad !== ""
          height: root.contentHeight
          text: modelData.pad
          color: root.warm(root.base, modelData.severity)
          opacity: root.padOpacity
          font.family: root.fontFamily
          font.pixelSize: root.valueSize
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
        }

        Text {
          id: valueText
          height: root.contentHeight
          text: modelData.value
          color: root.warm(root.base, modelData.severity)
          font.family: root.fontFamily
          font.pixelSize: root.valueSize
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 240 } }
        }
      }

      Row {
        visible: root.showClocks && modelData.clock !== ""
        height: root.contentHeight
        spacing: Style.space(2)

        Text {
          visible: root.clockIcon !== ""
          height: root.contentHeight
          leftPadding: Style.space(2)
          text: root.clockIcon
          color: root.warm(root.dim, modelData.severity)
          font.family: root.fontFamily
          font.pixelSize: root.labelSize + 1
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 240 } }
        }

        Text {
          height: root.contentHeight
          text: modelData.clock
          color: root.warm(root.dim, modelData.severity)
          font.family: root.fontFamily
          font.pixelSize: root.labelSize
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 240 } }
        }
      }

      // Same ink-hugging as the glyphs, for the same reason: the degree sign
      // paints a small ring high in its cell and leaves the rest of that cell
      // empty, so a temperature ending a group pushed the next group visibly
      // further away than a gauge ending one did. The box is the painted
      // bounds, and the text is offset by its own left bearing to sit in it.
      TextMetrics {
        id: tempMetrics
        font.family: root.fontFamily
        font.pixelSize: root.labelSize
        text: modelData.temp
      }

      Item {
        visible: root.showTemps && modelData.temp !== ""
        width: visible ? Math.max(1, Math.ceil(tempMetrics.tightBoundingRect.width)) : 0
        height: root.contentHeight

        Text {
          x: -tempMetrics.tightBoundingRect.x
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.temp
          color: root.warm(root.dim, modelData.severity)
          font.family: root.fontFamily
          font.pixelSize: root.labelSize
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: 240 } }
        }
      }

      Item {
        visible: group.slack > 0
        width: visible ? group.slack : 0
        height: 1
      }
    }
  }
}
