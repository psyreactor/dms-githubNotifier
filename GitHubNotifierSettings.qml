import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "githubNotifier"

    Column {
        width: parent.width
        spacing: Theme.spacingL

        Column {
            width: parent.width
            spacing: Theme.spacingXS
            
            StyledText {
                width: parent.width
                text: "GitHub Notifier"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: "Monitor pull requests and issues directly from your bar. Requires the GitHub CLI (gh) correctly authenticated."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }

        // --- Identity & Source ---
        Rectangle {
            width: parent.width
            height: identityGroup.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            function loadValue() {
                for (var i = 0; i < identityGroup.children.length; i++) {
                    var row = identityGroup.children[i];
                    for (var j = 0; j < row.children.length; j++) {
                        if (row.children[j].loadValue) row.children[j].loadValue();
                    }
                }
            }

            Column {
                id: identityGroup
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        DankIcon { name: "corporate_fare"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                        Column {
                            width: parent.width - 22 - Theme.spacingM
                            spacing: Theme.spacingXXS
                            StyledText {
                                text: "Organization (optional)"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: "Filter by GitHub organization. Leave empty for all repos."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    StringSetting {
                        width: parent.width
                        settingKey: "org"
                        label: ""
                        description: ""
                        placeholder: "my-org"
                        defaultValue: ""
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        DankIcon { name: "terminal"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                        Column {
                            width: parent.width - 22 - Theme.spacingM
                            spacing: Theme.spacingXXS
                            StyledText {
                                text: "gh binary path"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: "Path to gh executable (default: gh)."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    StringSetting {
                        width: parent.width
                        settingKey: "ghBinary"
                        label: ""
                        description: ""
                        placeholder: "gh"
                        defaultValue: "gh"
                    }
                }

            }
        }

        // --- Sync & Performance ---
        Rectangle {
            width: parent.width
            height: syncGroup.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            function loadValue() {
                for (var i = 0; i < syncGroup.children.length; i++) {
                    var row = syncGroup.children[i];
                    for (var j = 0; j < row.children.length; j++) {
                        if (row.children[j].loadValue) row.children[j].loadValue();
                    }
                }
            }

            Column {
                id: syncGroup
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        DankIcon { name: "schedule"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                        Column {
                            width: parent.width - 22 - Theme.spacingM
                            spacing: Theme.spacingXXS
                            StyledText {
                                text: "Refresh Interval"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                text: "Frequency of GitHub data updates."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                width: parent.width
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    SliderSetting {
                        width: parent.width
                        settingKey: "refreshInterval"
                        label: ""
                        description: ""
                        defaultValue: 60
                        minimum: 15
                        maximum: 3600
                        unit: "sec"
                        leftIcon: ""
                    }
                }

            }
        }

        // --- Content Visibility ---
        Rectangle {
            width: parent.width
            height: visibilityGroup.implicitHeight + Theme.spacingM * 2
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.color: Theme.outline
            border.width: 1
            opacity: 0.8

            function loadValue() {
                for (var i = 0; i < visibilityGroup.children.length; i++) {
                    var row = visibilityGroup.children[i];
                    for (var j = 0; j < row.children.length; j++) {
                        if (row.children[j].loadValue) row.children[j].loadValue();
                    }
                }
            }

            Column {
                id: visibilityGroup
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingM

                Row {
                    width: parent.width
                    spacing: Theme.spacingM
                    DankIcon { name: "merge_type"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                    SelectionSetting {
                        width: parent.width - 22 - Theme.spacingM
                        settingKey: "showPRs"
                        label: "Pull Requests"
                        description: "Show open PRs authored by you."
                        options: [
                            {label: "Visible", value: "true"},
                            {label: "Hidden", value: "false"}
                        ]
                        defaultValue: "true"
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingM
                    DankIcon { name: "bug_report"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                    SelectionSetting {
                        width: parent.width - 22 - Theme.spacingM
                        settingKey: "showIssues"
                        label: "Issues"
                        description: "Show open issues assigned to you."
                        options: [
                            {label: "Visible", value: "true"},
                            {label: "Hidden", value: "false"}
                        ]
                        defaultValue: "true"
                    }
                }
            }
        }
    }
}
