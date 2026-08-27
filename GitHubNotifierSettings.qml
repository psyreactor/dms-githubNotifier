import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "githubNotifier"

    Column {
        id: mainSettingsCol
        width: parent.width
        spacing: Theme.spacingL

        function loadValue(key, def) {
            return PluginService.loadPluginData(root.pluginId, key, def);
        }

        function saveValue(key, val) {
            PluginService.savePluginData(root.pluginId, key, val);
            PluginService.setGlobalVar(root.pluginId, key, val);
        }

        function loadValueInternal() {
            ghBinaryField.loadValue();
            orgField.loadValue();
            refreshIntervalField.loadValue();
            showPRsToggle.loadValue();
            showIssuesToggle.loadValue();
            timeFormatSelector.loadValue();
        }

        Component.onCompleted: loadValueInternal()

        // --- Configuration & Credentials Group ---
        StyledRect {
            id: configRect
            width: parent.width
            height: Math.max(0, configGroup.implicitHeight + Theme.spacingM * 2)
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            radius: Theme.cornerRadius
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
            border.width: 1

            Column {
                id: configGroup
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingL

                // gh Binary Path Block
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "terminal"
                            size: 22
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "GitHub CLI Executable Path"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: "Path to gh executable (default: gh). Requires gh CLI authenticated."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    DankTextField {
                        id: ghBinaryField
                        width: parent.width
                        placeholderText: "Enter path or binary name (e.g. gh)"

                        function loadValue() {
                            text = mainSettingsCol.loadValue("ghBinary", "gh");
                        }
                        Component.onCompleted: loadValue()
                        onEditingFinished: {
                            mainSettingsCol.saveValue("ghBinary", text);
                        }
                    }
                }

                // Organization Block
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "corporate_fare"
                            size: 22
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Organization (Optional)"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: "Filter pull requests and issues by organization. Leave empty for all repositories."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    DankTextField {
                        id: orgField
                        width: parent.width
                        placeholderText: "e.g. my-org"

                        function loadValue() {
                            text = mainSettingsCol.loadValue("org", "");
                        }
                        Component.onCompleted: loadValue()
                        onEditingFinished: {
                            mainSettingsCol.saveValue("org", text);
                        }
                    }
                }

                // Refresh Interval Block
                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "update"
                            size: 22
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Refresh Interval (Seconds)"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: "Frequency of GitHub data background updates in seconds (minimum: 15s)."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    DankTextField {
                        id: refreshIntervalField
                        width: parent.width
                        placeholderText: "60"

                        function loadValue() {
                            let val = mainSettingsCol.loadValue("refreshInterval", 60);
                            text = val.toString();
                        }
                        Component.onCompleted: loadValue()
                        onEditingFinished: {
                            let parsed = parseInt(text, 10);
                            if (isNaN(parsed) || parsed < 15) parsed = 15;
                            text = parsed.toString();
                            mainSettingsCol.saveValue("refreshInterval", parsed);
                        }
                    }
                }
            }
        }

        // --- Content & Display Settings Group ---
        StyledRect {
            id: displayRect
            width: parent.width
            height: Math.max(0, displayGroup.implicitHeight + Theme.spacingM * 2)
            color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
            radius: Theme.cornerRadius
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
            border.width: 1

            Column {
                id: displayGroup
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingL

                // Show PRs Toggle
                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "merge_type"
                        size: 22
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Show Pull Requests"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: "Display open pull requests authored by you."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    DankToggle {
                        id: showPRsToggle
                        Layout.alignment: Qt.AlignVCenter
                        checked: true

                        function loadValue() {
                            checked = mainSettingsCol.loadValue("showPRs", true);
                        }
                        Component.onCompleted: loadValue()

                        onClicked: {
                            checked = !checked;
                            mainSettingsCol.saveValue("showPRs", checked);
                        }
                    }
                }

                // Show Issues Toggle
                RowLayout {
                    width: parent.width
                    spacing: Theme.spacingM

                    DankIcon {
                        name: "bug_report"
                        size: 22
                        color: Theme.primary
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Show Issues"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }

                        StyledText {
                            text: "Display open issues assigned to you."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    DankToggle {
                        id: showIssuesToggle
                        Layout.alignment: Qt.AlignVCenter
                        checked: true

                        function loadValue() {
                            checked = mainSettingsCol.loadValue("showIssues", true);
                        }
                        Component.onCompleted: loadValue()

                        onClicked: {
                            checked = !checked;
                            mainSettingsCol.saveValue("showIssues", checked);
                        }
                    }
                }

                // Time Format Horizontal Grouped Option Buttons
                Column {
                    id: timeFormatSelector
                    width: parent.width
                    spacing: Theme.spacingS

                    property string currentFormat: "system"

                    function loadValue() {
                        currentFormat = mainSettingsCol.loadValue("timeFormat", "system");
                    }
                    Component.onCompleted: loadValue()

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "schedule"
                            size: 22
                            color: Theme.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                text: "Time Format"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: "Choose time format for timestamps and update indicators."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: [
                                { title: "System Default", key: "system", icon: "settings_suggest" },
                                { title: "12-Hour", key: "12h", icon: "schedule" },
                                { title: "24-Hour", key: "24h", icon: "alarm" }
                            ]

                            delegate: Item {
                                id: tfItem
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                height: 40

                                property bool isSelected: timeFormatSelector.currentFormat === modelData.key
                                property bool isHovered: tfItemMa.containsMouse

                                Shape {
                                    id: tfItemBg
                                    anchors.fill: parent

                                    property real innerRadius: 4
                                    property real outerRadius: Theme.cornerRadius || 12
                                    property bool isFirst: index === 0
                                    property bool isLast: index === 2

                                    property real tlr: (isSelected || isHovered) ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                    property real blr: (isSelected || isHovered) ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                    property real trr: (isSelected || isHovered) ? (height / 2) : (isLast ? outerRadius : innerRadius)
                                    property real brr: (isSelected || isHovered) ? (height / 2) : (isLast ? outerRadius : innerRadius)

                                    property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                    property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                    property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                                    property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }

                                    property color paintColor: isSelected
                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                            : (isHovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04))

                                    property color paintBorder: isSelected
                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                                            : (isHovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3) : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.12))

                                    ShapePath {
                                        fillColor: tfItemBg.paintColor
                                        strokeColor: tfItemBg.paintBorder
                                        strokeWidth: 1

                                        startX: tfItemBg.tlrAnim; startY: 0
                                        PathLine { x: tfItemBg.width - tfItemBg.trrAnim; y: 0 }
                                        PathArc { x: tfItemBg.width; y: tfItemBg.trrAnim; radiusX: tfItemBg.trrAnim; radiusY: tfItemBg.trrAnim; direction: PathArc.Clockwise }
                                        PathLine { x: tfItemBg.width; y: tfItemBg.height - tfItemBg.brrAnim }
                                        PathArc { x: tfItemBg.width - tfItemBg.brrAnim; y: tfItemBg.height; radiusX: tfItemBg.brrAnim; radiusY: tfItemBg.brrAnim; direction: PathArc.Clockwise }
                                        PathLine { x: tfItemBg.blrAnim; y: tfItemBg.height }
                                        PathArc { x: 0; y: tfItemBg.height - tfItemBg.blrAnim; radiusX: tfItemBg.blrAnim; radiusY: tfItemBg.blrAnim; direction: PathArc.Clockwise }
                                        PathLine { x: 0; y: tfItemBg.tlrAnim }
                                        PathArc { x: tfItemBg.tlrAnim; y: 0; radiusX: tfItemBg.tlrAnim; radiusY: tfItemBg.tlrAnim; direction: PathArc.Clockwise }
                                    }
                                }

                                scale: tfItemMa.pressed ? 0.98 : (isHovered ? 1.01 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                DankRipple { id: tfRip; anchors.fill: parent; cornerRadius: tfItemBg.tlrAnim; rippleColor: Theme.primary }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: modelData.icon
                                        size: 16
                                        color: tfItem.isSelected ? Theme.primary : Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: modelData.title
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: tfItem.isSelected ? Font.Bold : Font.Normal
                                        color: tfItem.isSelected ? Theme.primary : Theme.surfaceText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: tfItemMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (m) => tfRip.trigger(m.x, m.y)
                                    onClicked: {
                                        timeFormatSelector.currentFormat = modelData.key;
                                        mainSettingsCol.saveValue("timeFormat", modelData.key);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
