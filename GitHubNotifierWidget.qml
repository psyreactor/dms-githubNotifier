import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 420
    layerNamespacePlugin: "github-notifier"

    // Load settings with fallback via PluginService
    property string ghBinary: PluginService.loadPluginData("githubNotifier", "ghBinary", "gh")
    property string org: PluginService.loadPluginData("githubNotifier", "org", "")
    property int refreshInterval: PluginService.loadPluginData("githubNotifier", "refreshInterval", 60)
    property bool showPRs: PluginService.loadPluginData("githubNotifier", "showPRs", true)
    property bool showIssues: PluginService.loadPluginData("githubNotifier", "showIssues", true)
    property string timeFormat: PluginService.loadPluginData("githubNotifier", "timeFormat", "system")

    // State
    // isRefreshing doubles as the serialization flag: it is true from the start
    // of refresh() until completeRefresh(), so the spinner tracks the real work
    // instead of a fixed timer, and overlapping refreshes coalesce.
    property bool isRefreshing: false
    property bool refreshPending: false
    // Bumped on every refresh() so callbacks from an abandoned cycle (watchdog
    // timeout, overlapping refresh) can be discarded instead of completing it.
    property int refreshEpoch: 0
    // Set by the manual refresh button so the toast only fires for a refresh
    // the user actually asked for, not for every periodic tick.
    property bool manualRefresh: false
    property string lastError: ""
    property var lastUpdated: null

    property int prCount: 0
    property int issuesCount: 0
    property var prList: []
    property var issueList: []

    property string profileUrl: ""
    property string avatarUrl: ""
    property string username: ""

    readonly property int totalCount: (showPRs ? prCount : 0) + (showIssues ? issuesCount : 0)

    property string toastText: ""

    // Reactivity
    PluginGlobalVar { varName: "ghBinary"; onValueChanged: { root.ghBinary = value; root.refresh() } }
    PluginGlobalVar { varName: "org"; onValueChanged: { root.org = value; root.refresh() } }
    PluginGlobalVar { varName: "refreshInterval"; onValueChanged: { root.refreshInterval = value } }
    PluginGlobalVar { varName: "showPRs"; onValueChanged: { root.showPRs = value } }
    PluginGlobalVar { varName: "showIssues"; onValueChanged: { root.showIssues = value } }
    PluginGlobalVar { varName: "timeFormat"; onValueChanged: { root.timeFormat = value } }

    onPluginDataChanged: {
        if (!pluginData) return;
        root.ghBinary = PluginService.loadPluginData("githubNotifier", "ghBinary", "gh");
        root.org = PluginService.loadPluginData("githubNotifier", "org", "");
        root.refreshInterval = PluginService.loadPluginData("githubNotifier", "refreshInterval", 60);
        root.showPRs = PluginService.loadPluginData("githubNotifier", "showPRs", true);
        root.showIssues = PluginService.loadPluginData("githubNotifier", "showIssues", true);
        root.timeFormat = PluginService.loadPluginData("githubNotifier", "timeFormat", "system");
    }

    function showToast(msg) {
        toastText = msg;
        toastTimer.restart();
    }

    Timer {
        id: toastTimer
        interval: 1800
    }

    Timer {
        interval: Math.max(15, root.refreshInterval) * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // If a Proc callback never fires, isRefreshing would latch true and
    // refresh() would early-return for the rest of the session. 30s is above
    // the worst legitimate case: ghVersion, authStatus and the count queries
    // carry a 10s Proc timeout each and run back to back.
    Timer {
        id: loadingWatchdog
        interval: 30000
        repeat: false
        running: root.isRefreshing
        onTriggered: {
            root.refreshEpoch++;
            root.refreshPending = false;
            root.manualRefresh = false;
            root.isRefreshing = false;
            root.lastError = "Timed out talking to gh. Will retry.";
        }
    }

    function completeRefresh() {
        const shouldRefresh = root.refreshPending;
        const wasManual = root.manualRefresh;
        root.refreshPending = false;
        root.manualRefresh = false;
        root.isRefreshing = false;

        if (wasManual && !root.lastError)
            root.showToast("Refreshed GitHub Data");

        if (shouldRefresh)
            root.refresh();
    }

    function getEffectiveTimeFormat() {
        if (root.timeFormat === "12h") return "12h";
        if (root.timeFormat === "24h") return "24h";
        
        let dmsClock24 = PluginService.loadPluginData("dankbar", "use24HourClock", undefined);
        if (dmsClock24 === undefined) {
            dmsClock24 = PluginService.loadPluginData("settings", "use24Hour", undefined);
        }
        if (dmsClock24 !== undefined) {
            return dmsClock24 ? "24h" : "12h";
        }
        
        let sysFmt = Qt.locale().timeFormat(Locale.ShortFormat);
        let is24 = sysFmt.indexOf("H") !== -1 || sysFmt.indexOf("k") !== -1;
        return is24 ? "24h" : "12h";
    }

    function formatHeaderTime(dateObj) {
        if (!dateObj) return "";
        let effFormat = getEffectiveTimeFormat();
        if (effFormat === "24h") {
            return Qt.formatTime(dateObj, "HH:mm");
        } else {
            return Qt.formatTime(dateObj, "h:mm AP");
        }
    }

    function openUrl(url) {
        if (!url) return;
        Quickshell.execDetached(["xdg-open", url]);
        root.closePopout();
    }

    function prWebUrl() {
        return "https://github.com/pulls/authored";
    }

    function issuesWebUrl() {
        const o = (root.org || "").trim();
        if (o)
            return "https://github.com/issues?q=is:issue+is:open+assignee:@me+org:" + o;
        return "https://github.com/issues";
    }

    function refresh() {
        if (root.isRefreshing) {
            root.refreshPending = true;
            return;
        }

        root.isRefreshing = true;
        const gen = ++root.refreshEpoch;
        root.lastError = "";

        Proc.runCommand(null, [root.ghBinary, "--version"], (stdout, exitCode) => {
            if (gen !== root.refreshEpoch)
                return;

            if (exitCode !== 0) {
                root.prCount = 0;
                root.issuesCount = 0;
                root.lastError = "Could not execute gh CLI. Is it installed and in PATH?";
                root.completeRefresh();
                return;
            }

            Proc.runCommand(null, [root.ghBinary, "auth", "status"], (authOut, authExit) => {
                if (gen !== root.refreshEpoch)
                    return;

                if (authExit !== 0) {
                    root.prCount = 0;
                    root.issuesCount = 0;
                    root.lastError = "gh is not authenticated. Run: gh auth login";
                    root.completeRefresh();
                    return;
                }

                if (!root.profileUrl) {
                    Proc.runCommand(null, [root.ghBinary, "api", "user", "--jq", "{html_url,avatar_url,login}"], (pOut, pExit) => {
                        if (pExit === 0) {
                            try {
                                const u = JSON.parse(pOut.trim());
                                root.profileUrl = u.html_url || "";
                                root.avatarUrl = u.avatar_url || "";
                                root.username = u.login || "";
                            } catch (_) {}
                        }
                    }, 0, 10000);
                }

                root.fetchCounts(gen);
            }, 0, 10000);
        }, 0, 10000);
    }

    function parseGitHubList(stdout) {
        const raw = (stdout || "").trim();
        if (!raw) return [];
        try {
            const data = JSON.parse(raw);
            if (Array.isArray(data)) return data;
            if (data && Array.isArray(data.items)) return data.items;
            return [];
        } catch (e) {
            return [];
        }
    }

    function fetchCounts(gen) {
        const o = (root.org || "").trim();

        function prArgs() {
            const base = [root.ghBinary, "search", "prs", "archived:false", "--author=@me", "--state=open", "--json", "number,title,url,repository", "--limit", "25"];
            if (o) base.push("--owner=" + o);
            return base;
        }

        function issueArgs() {
            const base = [root.ghBinary, "search", "issues", "archived:false", "--assignee=@me", "--state=open", "--json", "number,title,url,repository", "--limit", "25"];
            if (o) base.push("--owner=" + o);
            return base;
        }

        let tasks = [];
        if (root.showPRs) tasks.push("pr");
        if (root.showIssues) tasks.push("issue");

        if (tasks.length === 0) {
            root.lastUpdated = new Date();
            root.completeRefresh();
            return;
        }

        let remaining = tasks.length;
        const done = () => {
            if (--remaining === 0) {
                root.lastUpdated = new Date();
                root.completeRefresh();
            }
        };

        if (root.showPRs) {
            Proc.runCommand(null, prArgs(), (stdout, exitCode) => {
                if (gen !== root.refreshEpoch)
                    return;

                if (exitCode === 0) {
                    root.prList = parseGitHubList(stdout);
                    root.prCount = root.prList.length;
                }
                done();
            }, 0, 10000);
        }

        if (root.showIssues) {
            Proc.runCommand(null, issueArgs(), (stdout, exitCode) => {
                if (gen !== root.refreshEpoch)
                    return;

                if (exitCode === 0) {
                    root.issueList = parseGitHubList(stdout);
                    root.issuesCount = root.issueList.length;
                }
                done();
            }, 0, 10000);
        }
    }

    // Horizontal Bar Pill
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankSVGIcon {
                source: Qt.resolvedUrl("github.svg")
                size: Theme.iconSize - 7
                anchors.verticalCenter: parent.verticalCenter
                colorOverride: root.lastError ? Theme.error : (root.totalCount > 0 ? Theme.primary : (Theme.widgetIconColor || Theme.surfaceText))
            }

            StyledText {
                text: root.totalCount.toString()
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: root.lastError ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Vertical Bar Pill
    // A bare Column reports no implicit size here, which is what broke the
    // vertical pill before #9. Keep the Item wrapper that fixed it.
    verticalBarPill: Component {
        Item {
            implicitWidth: verticalCol.implicitWidth
            implicitHeight: verticalCol.implicitHeight

            Column {
                id: verticalCol
                anchors.centerIn: parent
                spacing: Theme.spacingS

                DankSVGIcon {
                    source: Qt.resolvedUrl("github.svg")
                    size: root.iconSize
                    anchors.horizontalCenter: parent.horizontalCenter
                    colorOverride: root.lastError ? Theme.error : (root.totalCount > 0 ? Theme.primary : (Theme.widgetIconColor || Theme.surfaceText))
                }

                StyledText {
                    text: root.totalCount.toString()
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.lastError ? Theme.error : Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // Popout Content
    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn
            headerText: ""
            showCloseButton: false

            Item {
                id: popoutWrapper
                width: parent.width
                height: mainCol.implicitHeight

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: Theme.spacingM
                    topPadding: 0
                    bottomPadding: 2

                    // Header Card
                    StyledRect {
                        width: parent.width
                        height: 72
                        radius: Theme.cornerRadius * 1.5
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)

                        // Left: Logo / Profile + Title
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingM

                            Item {
                                width: 42
                                height: 42
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    id: profileArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: mouse => profileRipple.trigger(mouse.x, mouse.y)
                                    onClicked: if (root.profileUrl) root.openUrl(root.profileUrl)
                                }

                                DankCircularImage {
                                    anchors.fill: parent
                                    imageSource: root.avatarUrl
                                    fallbackIcon: ""
                                    border.width: profileArea.containsMouse ? 2 : 0
                                    border.color: Theme.primary

                                    DankSVGIcon {
                                        source: Qt.resolvedUrl("github.svg")
                                        size: 22
                                        anchors.centerIn: parent
                                        colorOverride: Theme.primary
                                        visible: parent.imageStatus !== Image.Ready
                                    }
                                }

                                DankRipple {
                                    id: profileRipple
                                    rippleColor: Theme.primary
                                    cornerRadius: 21
                                    anchors.fill: parent
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                StyledText {
                                    text: root.username ? root.username : "GitHub Notifier"
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeLarge
                                    color: Theme.surfaceText
                                }

                                StyledText {
                                    text: root.lastUpdated ? (root.totalCount + " Active Items • Updated " + root.formatHeaderTime(root.lastUpdated)) : (root.totalCount + " Active Items")
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    color: Theme.primary
                                    opacity: 0.85
                                }
                            }
                        }

                        // Right: Single Refresh Action Button
                        Rectangle {
                            id: headerRefreshBtn
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            property bool isHovered: refreshMa.containsMouse

                            width: 38
                            height: 38

                            color: isHovered ? Theme.withAlpha(Theme.primary, 0.15) : Theme.withAlpha(Theme.surfaceContainer, 0.4)
                            border.width: 1
                            border.color: Theme.withAlpha(Theme.primary, isHovered ? 0.3 : 0.15)
                            radius: Theme.cornerRadius

                            scale: refreshMa.pressed ? 0.92 : (isHovered ? 1.05 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                            DankRipple { id: refreshRip; anchors.fill: parent; cornerRadius: Theme.cornerRadius; rippleColor: Theme.primary }

                            DankSpinner {
                                size: 20
                                color: Theme.primary
                                anchors.centerIn: parent
                                visible: root.isRefreshing
                            }

                            DankIcon {
                                id: refreshBtnIcon
                                name: "refresh"
                                size: 20
                                color: Theme.primary
                                anchors.centerIn: parent
                                visible: !root.isRefreshing

                                rotation: refreshMa.containsMouse ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            }

                            MouseArea {
                                id: refreshMa
                                anchors.fill: parent
                                hoverEnabled: !root.isRefreshing
                                cursorShape: Qt.PointingHandCursor
                                onPressed: (m) => refreshRip.trigger(m.x, m.y)
                                onClicked: {
                                    root.manualRefresh = true;
                                    root.refresh();
                                }
                            }
                        }
                    }

                    // Error Message Rect
                    StyledRect {
                        width: parent.width
                        visible: root.lastError.length > 0
                        height: Math.max(0, errText.implicitHeight + Theme.spacingM * 2)
                        radius: Theme.cornerRadius
                        color: Qt.rgba(0.95, 0.26, 0.21, 0.12)
                        border.width: 1
                        border.color: Qt.rgba(0.95, 0.26, 0.21, 0.4)

                        StyledText {
                            id: errText
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: root.lastError
                            color: "#F44336"
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    // --- Separate Container Cards for Pull Requests ---
                    StyledRect {
                        id: prGroupCard
                        width: parent.width
                        height: Math.max(0, prGroupCol.implicitHeight + Theme.spacingM * 2)
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        visible: root.showPRs

                        Column {
                            id: prGroupCol
                            width: parent.width
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            // Container Section Header (Interactive link)
                            Item {
                                width: parent.width
                                height: prGroupHeaderRow.implicitHeight

                                RowLayout {
                                    id: prGroupHeaderRow
                                    anchors.fill: parent
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: "merge_type"
                                        size: 14
                                        color: prHeaderMa.containsMouse ? Theme.primary : Theme.surfaceText
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    StyledText {
                                        text: "Pull Requests"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                        color: prHeaderMa.containsMouse ? Theme.primary : Theme.surfaceText
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    DankIcon {
                                        name: "open_in_new"
                                        size: 14
                                        color: prHeaderMa.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                        opacity: prHeaderMa.containsMouse ? 0.9 : 0.4
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                }

                                MouseArea {
                                    id: prHeaderMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openUrl(root.prWebUrl())
                                }
                            }

                            // Empty Category Container Pill
                            StyledRect {
                                width: parent.width
                                height: 44
                                radius: Theme.cornerRadius
                                color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.12)
                                visible: !root.isRefreshing && root.prList.length === 0

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: "check_circle"
                                        size: 18
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: "No active pull requests"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // Loading Category Container Pill
                            StyledRect {
                                width: parent.width
                                height: 44
                                radius: Theme.cornerRadius
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                visible: root.isRefreshing

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS

                                    DankSpinner {
                                        size: 18
                                        color: Theme.primary
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: "Refreshing PRs..."
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // Friend/PR list container (Scrollable if > 3 items)
                            Item {
                                width: parent.width
                                height: root.prList.length > 3 ? 166 : prItemsColumn.implicitHeight
                                visible: !root.isRefreshing && root.prList.length > 0

                                ScrollView {
                                    id: prScrollView
                                    anchors.fill: parent
                                    contentWidth: availableWidth

                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                    ScrollBar.vertical: ScrollBar {
                                        id: prScrollBar
                                        policy: root.prList.length > 3 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                                        active: true
                                        width: 6

                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: prScrollBar.pressed 
                                                   ? Theme.primary 
                                                   : (prScrollBar.hovered 
                                                      ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.7) 
                                                      : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4))
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        background: Rectangle {
                                            implicitWidth: 6
                                            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.2)
                                            radius: 3
                                        }
                                    }

                                    Column {
                                        id: prItemsColumn
                                        width: prScrollView.availableWidth
                                        spacing: 4

                                        Repeater {
                                            model: root.prList

                                            delegate: Item {
                                                id: prDelegate
                                                width: parent.width
                                                height: Math.max(56, prRowLayout.implicitHeight + Theme.spacingS * 2)

                                                property bool isHovered: prMa.containsMouse

                                                Shape {
                                                    id: prBg
                                                    anchors.fill: parent

                                                    property real innerRadius: 6
                                                    property real outerRadius: Theme.cornerRadius || 12
                                                    property bool isFirst: index === 0
                                                    property bool isLast: index === root.prList.length - 1

                                                    property real tlr: isHovered ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                    property real trr: isHovered ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                    property real blr: isHovered ? (height / 2) : (isLast ? outerRadius : innerRadius)
                                                    property real brr: isHovered ? (height / 2) : (isLast ? outerRadius : innerRadius)

                                                    property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                                                    property color paintColor: isHovered
                                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                                            : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)

                                                    property color paintBorder: isHovered
                                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                                            : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                                                    ShapePath {
                                                        fillColor: prBg.paintColor
                                                        strokeColor: prBg.paintBorder
                                                        strokeWidth: 1

                                                        startX: prBg.tlrAnim + 1; startY: 1
                                                        PathLine { x: prBg.width - prBg.trrAnim - 1; y: 1 }
                                                        PathArc { x: prBg.width - 1; y: prBg.trrAnim + 1; radiusX: prBg.trrAnim; radiusY: prBg.trrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: prBg.width - 1; y: prBg.height - prBg.brrAnim - 1 }
                                                        PathArc { x: prBg.width - prBg.brrAnim - 1; y: prBg.height - 1; radiusX: prBg.brrAnim; radiusY: prBg.brrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: prBg.blrAnim + 1; y: prBg.height - 1 }
                                                        PathArc { x: 1; y: prBg.height - prBg.blrAnim - 1; radiusX: prBg.blrAnim; radiusY: prBg.blrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: 1; y: prBg.tlrAnim + 1 }
                                                        PathArc { x: prBg.tlrAnim + 1; y: 1; radiusX: prBg.tlrAnim; radiusY: prBg.tlrAnim; direction: PathArc.Clockwise }
                                                    }
                                                }

                                                DankRipple {
                                                    id: prRip
                                                    anchors.fill: parent
                                                    cornerRadius: prBg.tlrAnim
                                                    rippleColor: Theme.primary
                                                }

                                                RowLayout {
                                                    id: prRowLayout
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: Theme.spacingM
                                                    anchors.rightMargin: Theme.spacingM
                                                    spacing: Theme.spacingM

                                                    DankIcon {
                                                        name: "merge_type"
                                                        size: 18
                                                        color: Theme.primary
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                        spacing: 2

                                                        StyledText {
                                                            text: modelData.title || ""
                                                            font.pixelSize: Theme.fontSizeMedium
                                                            font.weight: Font.Medium
                                                            color: Theme.surfaceText
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.WordWrap
                                                            maximumLineCount: 2
                                                            elide: Text.ElideRight
                                                        }

                                                        StyledText {
                                                            text: (modelData.repository ? (modelData.repository.nameWithOwner || modelData.repository.name) : "") + " #" + modelData.number
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            color: isHovered ? Theme.primary : Theme.surfaceVariantText
                                                            Layout.fillWidth: true
                                                            elide: Text.ElideRight
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                    }

                                                    DankIcon {
                                                        name: "open_in_new"
                                                        size: 16
                                                        color: Theme.surfaceVariantText
                                                        opacity: isHovered ? 0.9 : 0.0
                                                        Layout.alignment: Qt.AlignVCenter
                                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                                    }
                                                }

                                                MouseArea {
                                                    id: prMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onPressed: (m) => prRip.trigger(m.x, m.y)
                                                    onClicked: root.openUrl(modelData.url)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --- Separate Container Cards for Issues ---
                    StyledRect {
                        id: issueGroupCard
                        width: parent.width
                        height: Math.max(0, issueGroupCol.implicitHeight + Theme.spacingM * 2)
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        visible: root.showIssues

                        Column {
                            id: issueGroupCol
                            width: parent.width
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            // Container Section Header (Interactive link)
                            Item {
                                width: parent.width
                                height: issueGroupHeaderRow.implicitHeight

                                RowLayout {
                                    id: issueGroupHeaderRow
                                    anchors.fill: parent
                                    spacing: Theme.spacingXS

                                    DankIcon {
                                        name: "bug_report"
                                        size: 14
                                        color: issueHeaderMa.containsMouse ? Theme.primary : Theme.surfaceText
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    StyledText {
                                        text: "Issues"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Bold
                                        color: issueHeaderMa.containsMouse ? Theme.primary : Theme.surfaceText
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    DankIcon {
                                        name: "open_in_new"
                                        size: 14
                                        color: issueHeaderMa.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                        opacity: issueHeaderMa.containsMouse ? 0.9 : 0.4
                                        Layout.alignment: Qt.AlignVCenter
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                }

                                MouseArea {
                                    id: issueHeaderMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openUrl(root.issuesWebUrl())
                                }
                            }

                            // Empty Category Container Pill
                            StyledRect {
                                width: parent.width
                                height: 44
                                radius: Theme.cornerRadius
                                color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.12)
                                visible: !root.isRefreshing && root.issueList.length === 0

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: "check_circle"
                                        size: 18
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: "No active issues"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // Loading Category Container Pill
                            StyledRect {
                                width: parent.width
                                height: 44
                                radius: Theme.cornerRadius
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                                border.width: 1
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                visible: root.isRefreshing

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS

                                    DankSpinner {
                                        size: 18
                                        color: Theme.primary
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: "Refreshing Issues..."
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        color: Theme.surfaceVariantText
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }

                            // Issue list container (Scrollable if > 3 items)
                            Item {
                                width: parent.width
                                height: root.issueList.length > 3 ? 166 : issueItemsColumn.implicitHeight
                                visible: !root.isRefreshing && root.issueList.length > 0

                                ScrollView {
                                    id: issueScrollView
                                    anchors.fill: parent
                                    contentWidth: availableWidth

                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                    ScrollBar.vertical: ScrollBar {
                                        id: issueScrollBar
                                        policy: root.issueList.length > 3 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                                        active: true
                                        width: 6

                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: issueScrollBar.pressed 
                                                   ? Theme.primary 
                                                   : (issueScrollBar.hovered 
                                                      ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.7) 
                                                      : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4))
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }

                                        background: Rectangle {
                                            implicitWidth: 6
                                            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.2)
                                            radius: 3
                                        }
                                    }

                                    Column {
                                        id: issueItemsColumn
                                        width: issueScrollView.availableWidth
                                        spacing: 4

                                        Repeater {
                                            model: root.issueList

                                            delegate: Item {
                                                id: issueDelegate
                                                width: parent.width
                                                height: Math.max(56, issueRowLayout.implicitHeight + Theme.spacingS * 2)

                                                property bool isHovered: issueMa.containsMouse

                                                Shape {
                                                    id: issueBg
                                                    anchors.fill: parent

                                                    property real innerRadius: 6
                                                    property real outerRadius: Theme.cornerRadius || 12
                                                    property bool isFirst: index === 0
                                                    property bool isLast: index === root.issueList.length - 1

                                                    property real tlr: isHovered ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                    property real trr: isHovered ? (height / 2) : (isFirst ? outerRadius : innerRadius)
                                                    property real blr: isHovered ? (height / 2) : (isLast ? outerRadius : innerRadius)
                                                    property real brr: isHovered ? (height / 2) : (isLast ? outerRadius : innerRadius)

                                                    property real tlrAnim: tlr; Behavior on tlrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real trrAnim: trr; Behavior on trrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real blrAnim: blr; Behavior on blrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                                                    property real brrAnim: brr; Behavior on brrAnim { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }

                                                    property color paintColor: isHovered
                                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                                            : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.04)

                                                    property color paintBorder: isHovered
                                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                                            : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)

                                                    ShapePath {
                                                        fillColor: issueBg.paintColor
                                                        strokeColor: issueBg.paintBorder
                                                        strokeWidth: 1

                                                        startX: issueBg.tlrAnim + 1; startY: 1
                                                        PathLine { x: issueBg.width - issueBg.trrAnim - 1; y: 1 }
                                                        PathArc { x: issueBg.width - 1; y: issueBg.trrAnim + 1; radiusX: issueBg.trrAnim; radiusY: issueBg.trrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: issueBg.width - 1; y: issueBg.height - issueBg.brrAnim - 1 }
                                                        PathArc { x: issueBg.width - issueBg.brrAnim - 1; y: issueBg.height - 1; radiusX: issueBg.brrAnim; radiusY: issueBg.brrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: issueBg.blrAnim + 1; y: issueBg.height - 1 }
                                                        PathArc { x: 1; y: issueBg.height - issueBg.blrAnim - 1; radiusX: issueBg.blrAnim; radiusY: issueBg.blrAnim; direction: PathArc.Clockwise }
                                                        PathLine { x: 1; y: issueBg.tlrAnim + 1 }
                                                        PathArc { x: issueBg.tlrAnim + 1; y: 1; radiusX: issueBg.tlrAnim; radiusY: issueBg.tlrAnim; direction: PathArc.Clockwise }
                                                    }
                                                }

                                                DankRipple {
                                                    id: issueRip
                                                    anchors.fill: parent
                                                    cornerRadius: issueBg.tlrAnim
                                                    rippleColor: Theme.primary
                                                }

                                                RowLayout {
                                                    id: issueRowLayout
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: Theme.spacingM
                                                    anchors.rightMargin: Theme.spacingM
                                                    spacing: Theme.spacingM

                                                    DankIcon {
                                                        name: "bug_report"
                                                        size: 18
                                                        color: Theme.secondary
                                                        Layout.alignment: Qt.AlignVCenter
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.alignment: Qt.AlignVCenter
                                                        spacing: 2

                                                        StyledText {
                                                            text: modelData.title || ""
                                                            font.pixelSize: Theme.fontSizeMedium
                                                            font.weight: Font.Medium
                                                            color: Theme.surfaceText
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.WordWrap
                                                            maximumLineCount: 2
                                                            elide: Text.ElideRight
                                                        }

                                                        StyledText {
                                                            text: (modelData.repository ? (modelData.repository.nameWithOwner || modelData.repository.name) : "") + " #" + modelData.number
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            color: isHovered ? Theme.primary : Theme.surfaceVariantText
                                                            Layout.fillWidth: true
                                                            elide: Text.ElideRight
                                                            Behavior on color { ColorAnimation { duration: 150 } }
                                                        }
                                                    }

                                                    DankIcon {
                                                        name: "open_in_new"
                                                        size: 16
                                                        color: Theme.surfaceVariantText
                                                        opacity: isHovered ? 0.9 : 0.0
                                                        Layout.alignment: Qt.AlignVCenter
                                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                                    }
                                                }

                                                MouseArea {
                                                    id: issueMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onPressed: (m) => issueRip.trigger(m.x, m.y)
                                                    onClicked: root.openUrl(modelData.url)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Dynamic Toast Notification Overlay
                Rectangle {
                    id: toastPill
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spacingS
                    height: 32
                    width: toastLayout.implicitWidth + Theme.spacingM * 2
                    radius: height / 2
                    color: Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.95)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    border.width: 1
                    z: 999
                    opacity: toastTimer.running ? 1.0 : 0.0
                    scale: toastTimer.running ? 1.0 : 0.75

                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                    RowLayout {
                        id: toastLayout
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "info"
                            size: 16
                            color: Theme.primary
                        }

                        StyledText {
                            text: root.toastText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }
                    }
                }
            }
        }
    }
}
