import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "github-notifier"

    // Settings
    property string ghBinary: pluginData.ghBinary || "gh"
    property string org: pluginData.org || ""
    property int refreshInterval: pluginData.refreshInterval || 60

    property string faGithubGlyph: "\uf09b" // Font Awesome GitHub (brands)
    property string faFamily: "Font Awesome 6 Brands, Font Awesome 5 Brands, Font Awesome 6 Free, Font Awesome 5 Free"

    function asBool(v, defaultValue) {
        if (v === undefined || v === null)
            return defaultValue;
        if (typeof v === "boolean")
            return v;
        if (typeof v === "string")
            return v.toLowerCase() === "true";
        return !!v;
    }

    property bool showPRs: asBool(pluginData.showPRs, true)
    property bool showIssues: asBool(pluginData.showIssues, true)

    // State
    property bool loading: false
    property string lastError: ""
    property bool ghOk: true
    property bool authOk: true

    property int prCount: 0
    property int issuesCount: 0

    readonly property int totalCount: (showPRs ? prCount : 0) + (showIssues ? issuesCount : 0)

    Timer {
        interval: root.refreshInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onGhBinaryChanged: refresh()
    onOrgChanged: refresh()
    onShowPRsChanged: refresh()
    onShowIssuesChanged: refresh()

    function openUrl(url) {
        if (!url) return;
        Quickshell.execDetached(["xdg-open", url]);
        root.closePopout();
    }

    function setError(msg) {
        root.lastError = msg || "";
    }

    function prWebUrl() {
        const o = (root.org || "").trim();
        if (o)
            return "https://github.com/pulls?q=is:pr+is:open+author:@me+org:" + o;
        return "https://github.com/pulls";
    }

    function issuesWebUrl() {
        const o = (root.org || "").trim();
        if (o)
            return "https://github.com/issues?q=is:issue+is:open+assignee:@me+org:" + o;
        return "https://github.com/issues";
    }

    function refresh() {
        root.loading = true;
        root.setError("");
        root.ghOk = true;
        root.authOk = true;

        // 1) Check gh is installed
        Proc.runCommand("githubNotifier.ghVersion", [root.ghBinary, "--version"], (stdout, exitCode) => {
            if (exitCode !== 0) {
                root.ghOk = false;
                root.authOk = false;
                root.loading = false;
                root.prCount = 0;
                root.issuesCount = 0;
                root.setError("Could not execute gh. Is it installed and in PATH?");
                return;
            }

            // 2) Check auth
            Proc.runCommand("githubNotifier.authStatus", [root.ghBinary, "auth", "status"], (authOut, authExit) => {
                if (authExit !== 0) {
                    root.authOk = false;
                    root.loading = false;
                    root.prCount = 0;
                    root.issuesCount = 0;
                    root.setError("gh is not authenticated. Run: gh auth login");
                    return;
                }

                root.fetchCounts();
            }, 400);
        }, 300);
    }

    function parseJsonArrayLen(stdout) {
        const raw = (stdout || "").trim();
        if (!raw) return 0;

        try {
            const data = JSON.parse(raw);
            if (Array.isArray(data)) return data.length;
            if (Array.isArray(data.items)) return data.items.length;
            if (Array.isArray(data.data)) return data.data.length;
            if (typeof data === "object" && data !== null) {
                if (typeof data.total_count === "number") return data.total_count;
                if (typeof data.total === "number") return data.total;
            }
        } catch (e) {}

        try {
            const lines = raw.split(/\r?\n/).map(s => s.trim()).filter(s => s.length > 0);
            let count = 0;
            for (let i = 0; i < lines.length; i++) {
                try {
                    const obj = JSON.parse(lines[i]);
                    if (obj !== null && typeof obj === "object") count++;
                } catch (e) {}
            }
            if (count > 0) return count;
        } catch (e) {}

        const num = parseInt(raw, 10);
        if (!isNaN(num)) return num;

        return 0;
    }

    function fetchCounts() {
        const o = (root.org || "").trim();

        function prArgs() {
            const base = [root.ghBinary, "search", "prs", "--author=@me", "--state=open", "--json", "number"];
            if (o) base.push("--owner=" + o);
            return base;
        }

        function issueArgs() {
            const base = [root.ghBinary, "search", "issues", "--assignee=@me", "--state=open", "--json", "number"];
            if (o) base.push("--owner=" + o);
            return base;
        }

        const nextAfterPRs = () => {
            if (!root.showIssues) return finish();
            Proc.runCommand("githubNotifier.issueList", issueArgs(), (stdout, exitCode) => {
                if (exitCode === 0)
                    root.issuesCount = parseJsonArrayLen(stdout);
                finish();
            }, 5000);
        };

        const finish = () => {
            root.loading = false;
        };

        if (root.showPRs) {
            Proc.runCommand("githubNotifier.prList", prArgs(), (stdout, exitCode) => {
                if (exitCode === 0)
                    root.prCount = parseJsonArrayLen(stdout);
                nextAfterPRs();
            }, 5000);
        } else {
            nextAfterPRs();
        }
    }

    component Badge: StyledRect {
        property int value: 0
        property color badgeColor: Theme.primary

        height: 18
        width: Math.max(22, badgeText.implicitWidth + Theme.spacingS)
        radius: 9
        color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.18)
        border.width: 1
        border.color: Qt.rgba(badgeColor.r, badgeColor.g, badgeColor.b, 0.35)

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: value.toString()
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: badgeColor
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            StyledText {
                text: root.faGithubGlyph
                font.family: root.faFamily
                font.pixelSize: Theme.iconSize - 7
                color: root.lastError ? Theme.error : (root.totalCount > 0 ? Theme.primary : (Theme.widgetIconColor || Theme.surfaceText))
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.totalCount.toString()
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: root.lastError ? Theme.error : Theme.primary
                anchors.verticalCenter: parent.verticalCenter
                visible: root.totalCount > 0
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            StyledText {
                text: root.faGithubGlyph
                font.family: root.faFamily
                font.pixelSize: 20
                color: root.lastError ? Theme.error : (root.totalCount > 0 ? Theme.primary : (Theme.widgetIconColor || Theme.surfaceText))
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.totalCount.toString()
                color: root.lastError ? Theme.error : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    component StatRow: Row {
        property string title: ""
        property int count: 0
        property string openUrl: ""

        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: title
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            width: 120
        }

        Badge {
            value: count
            badgeColor: count > 0 ? Theme.primary : Theme.surfaceVariantText
        }

        Item { width: Theme.spacingS; height: 1 }

        Rectangle {
            width: 90
            height: 30
            radius: Theme.cornerRadius
            color: openMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
            visible: openUrl.length > 0

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                DankIcon { name: "open_in_new"; size: 18; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                StyledText { text: "Open"; color: Theme.primary; font.pixelSize: Theme.fontSizeMedium; anchors.verticalCenter: parent.verticalCenter }
            }

            MouseArea {
                id: openMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(parent.parent.openUrl)
            }
        }
    }

    popoutContent: Component {
        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingXS
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM

                StyledText {
                    text: root.faGithubGlyph
                    font.family: root.faFamily
                    font.pixelSize: 26
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        text: "GitHub Notifier"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: root.org ? ("Org: " + root.org) : "All repositories"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: root.lastError ? 60 : 0
                radius: Theme.cornerRadius
                color: Theme.errorContainer
                visible: root.lastError.length > 0

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingL * 2
                    text: root.lastError
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.onErrorContainer
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            StatRow {
                title: "Pull Requests"
                count: root.prCount
                openUrl: root.prWebUrl()
                visible: root.showPRs
            }

            StatRow {
                title: "Issues"
                count: root.issuesCount
                openUrl: root.issuesWebUrl()
                visible: root.showIssues
            }

            Item {
                width: parent.width
                height: Theme.spacingM
            }
        }
    }

    popoutWidth: 320
    popoutHeight: 0
}
