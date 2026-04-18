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
    property var prList: []
    property var issueList: []
    property string profileUrl: ""


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
        return "https://github.com/pulls/authored";
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

                if (!root.profileUrl) {
                    Proc.runCommand("githubNotifier.getProfile", [root.ghBinary, "api", "user", "--jq", ".html_url"], (pOut, pExit) => {
                        if (pExit === 0) root.profileUrl = pOut.trim();
                    }, 1000);
                }

                root.fetchCounts();

            }, 400);
        }, 300);
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

    function parseJsonArrayLen(stdout) {
        const list = parseGitHubList(stdout);
        if (list.length > 0) return list.length;

        const raw = (stdout || "").trim();
        if (!raw) return 0;

        const num = parseInt(raw, 10);
        if (!isNaN(num)) return num;

        return 0;
    }


    function fetchCounts() {
        const o = (root.org || "").trim();

        function prArgs() {
            const base = [root.ghBinary, "search", "prs", "--author=@me", "--state=open", "--json", "number,title,url,repository", "--limit", "15"];
            if (o) base.push("--owner=" + o);
            return base;
        }

        function issueArgs() {
            const base = [root.ghBinary, "search", "issues", "--assignee=@me", "--state=open", "--json", "number,title,url,repository", "--limit", "15"];
            if (o) base.push("--owner=" + o);
            return base;
        }


        const nextAfterPRs = () => {
            if (!root.showIssues) return finish();
            Proc.runCommand("githubNotifier.issueList", issueArgs(), (stdout, exitCode) => {
                if (exitCode === 0) {
                    root.issueList = parseGitHubList(stdout);
                    root.issuesCount = root.issueList.length;
                }
                finish();
            }, 5000);
        };


        const finish = () => {
            root.loading = false;
        };

        if (root.showPRs) {
            Proc.runCommand("githubNotifier.prList", prArgs(), (stdout, exitCode) => {
                if (exitCode === 0) {
                    root.prList = parseGitHubList(stdout);
                    root.prCount = root.prList.length;
                }
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

    component StatRow: Item {
        property string title: ""
        property string iconName: ""
        property int count: 0
        property string openUrl: ""
        property color accentColor: Theme.primary

        width: parent.width
        height: 40


        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            Rectangle {
                width: 4
                height: 22
                radius: 2
                color: accentColor
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: iconName
                size: 20
                color: accentColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: title
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                width: badgeText.width + 14
                height: 20
                radius: 10
                color: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.15)
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    id: badgeText
                    text: count.toString()
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: accentColor
                    anchors.centerIn: parent
                }
            }
        }

        // Action button (View All)
        Item {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: actionBtnRow.width + Theme.spacingM * 2
            height: 30
            visible: openUrl.length > 0 && count > 0
            scale: actionBtnArea.pressed ? 0.95 : (actionBtnArea.containsMouse ? 1.05 : 1.0)
            Behavior on scale { NumberAnimation { duration: 100 } }

            MouseArea {
                id: actionBtnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => actionRipple.trigger(mouse.x, mouse.y)
                onClicked: root.openUrl(openUrl)
            }

            Row {
                id: actionBtnRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    id: actionIcon
                    name: "open_in_new"
                    size: 14
                    color: actionBtnArea.containsMouse ? "white" : accentColor
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation {
                        running: actionBtnArea.containsMouse
                        loops: Animation.Infinite
                        onStopped: actionIcon.rotation = 0
                        NumberAnimation { target: actionIcon; property: "rotation"; from: 0; to: 10; duration: 50; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: actionIcon; property: "rotation"; from: 10; to: -10; duration: 100; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: actionIcon; property: "rotation"; from: -10; to: 0; duration: 50; easing.type: Easing.InOutQuad }
                    }
                }

                StyledText {
                    text: "View All"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: actionBtnArea.containsMouse ? "white" : accentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            DankRipple {
                id: actionRipple
                rippleColor: actionBtnArea.containsMouse ? "white" : accentColor
                cornerRadius: Theme.cornerRadius
                anchors.fill: parent
            }
        }



    }





    component GitHubItem: Item {
        property var itemData: null
        property color accentColor: Theme.primary

        width: ListView.view.width
        height: 40

        scale: itemArea.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: 100 } }

        MouseArea {
            id: itemArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => itemRipple.trigger(mouse.x, mouse.y)
            onClicked: root.openUrl(itemData.url)
        }


        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Theme.cornerRadius
            color: itemArea.containsMouse ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.08) : "transparent"
        }

        DankRipple { id: itemRipple; rippleColor: accentColor; cornerRadius: Theme.cornerRadius }

        Row {

            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingS

            DankIcon {
                name: "subdirectory_arrow_right"
                size: 14
                color: accentColor
                opacity: 0.6
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                width: parent.width - 20
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    width: parent.width
                    text: itemData ? itemData.title : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    text: itemData ? (itemData.repository.nameWithOwner || itemData.repository.name) : ""
                    font.pixelSize: Theme.fontSizeSmall - 2
                    color: Theme.surfaceVariantText
                    opacity: 0.8
                }
            }
        }
    }

    popoutContent: Component {

        Column {
            width: parent.width
            spacing: Theme.spacingM
            topPadding: Theme.spacingM
            bottomPadding: Theme.spacingM

            // Header card
            Item {
                width: parent.width
                height: 68

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius * 1.5
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                        }
                    }
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Item {
                        width: 40
                        height: 40
                        anchors.verticalCenter: parent.verticalCenter
                        scale: profileArea.pressed ? 0.9 : (profileArea.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        MouseArea {
                            id: profileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => profileRipple.trigger(mouse.x, mouse.y)
                            onClicked: if (root.profileUrl) root.openUrl(root.profileUrl)
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: profileArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        }

                        StyledText {
                            text: root.faGithubGlyph
                            font.family: root.faFamily
                            font.pixelSize: 22
                            color: Theme.primary
                            anchors.centerIn: parent
                            scale: profileArea.containsMouse ? 1.2 : 1.0
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                        }

                        DankRipple { 
                            id: profileRipple
                            rippleColor: Theme.surfaceText
                            cornerRadius: 20
                            anchors.fill: parent
                        }
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

                // Translucent Refresh button
                Item {
                    width: 38
                    height: 38
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    scale: refreshArea.pressed ? 0.9 : (refreshArea.containsMouse ? 1.1 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => refreshRipple.trigger(mouse.x, mouse.y)
                        onClicked: root.refresh()
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: refreshArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.4)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, refreshArea.containsMouse ? 0.3 : 0.15)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    DankIcon {
                        id: refreshIcon
                        name: "refresh"
                        size: 20
                        color: Theme.primary
                        anchors.centerIn: parent

                        SequentialAnimation {
                            id: hoverSpinAnim
                            running: refreshArea.containsMouse && !root.loading
                            onStopped: refreshIcon.rotation = 0
                            NumberAnimation { target: refreshIcon; property: "rotation"; from: 0; to: 360; duration: 400; easing.type: Easing.InOutQuart }
                            NumberAnimation { target: refreshIcon; property: "rotation"; from: 360; to: 0; duration: 400; easing.type: Easing.InOutQuart }
                        }

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            running: root.loading
                        }
                    }

                    DankRipple { 
                        id: refreshRipple
                        rippleColor: Theme.surfaceText
                        cornerRadius: Theme.cornerRadius
                        anchors.fill: parent
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

            // PRs Section
            StatRow {
                title: "Pull Requests"
                iconName: "merge_type"
                count: root.prCount
                openUrl: root.prWebUrl()
                accentColor: Theme.primary
                visible: root.showPRs
            }

            StyledRect {
                id: prContainer
                width: parent.width
                height: root.loading ? 54 : (root.prList.length > 0 ? Math.min(root.prList.length * 40 + (root.prList.length - 1) * 6 + 28, 300) : 54)


                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                visible: root.showPRs
                clip: true

                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.loading

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: parent.visible
                        }
                    }
                    StyledText { text: "Checking..."; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                }


                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.loading && root.prList.length === 0

                    DankIcon { name: "check_circle"; size: 16; color: Theme.secondary; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { text: "No active pull requests"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                }

                ListView {
                    anchors.fill: parent
                    anchors.topMargin: 14
                    anchors.bottomMargin: 14
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    spacing: 6
                    model: root.prList


                    clip: true
                    visible: !root.loading && root.prList.length > 0
                    delegate: GitHubItem {
                        itemData: modelData
                        accentColor: Theme.primary
                    }
                }
            }

            // Issues Section
            StatRow {
                title: "Issues"
                iconName: "bug_report"
                count: root.issuesCount
                openUrl: root.issuesWebUrl()
                accentColor: Theme.secondary
                visible: root.showIssues
            }

            StyledRect {
                id: issueContainer
                width: parent.width
                height: root.loading ? 54 : (root.issueList.length > 0 ? Math.min(root.issueList.length * 40 + (root.issueList.length - 1) * 6 + 28, 300) : 54)


                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.1)
                visible: root.showIssues
                clip: true

                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.loading

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: parent.visible
                        }
                    }
                    StyledText { text: "Checking..."; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                }


                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.loading && root.issueList.length === 0

                    DankIcon { name: "check_circle"; size: 16; color: Theme.secondary; anchors.verticalCenter: parent.verticalCenter }
                    StyledText { text: "No active issues"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; anchors.verticalCenter: parent.verticalCenter }
                }

                ListView {
                    anchors.fill: parent
                    anchors.topMargin: 14
                    anchors.bottomMargin: 14
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    spacing: 6
                    model: root.issueList


                    clip: true
                    visible: !root.loading && root.issueList.length > 0
                    delegate: GitHubItem {
                        itemData: modelData
                        accentColor: Theme.secondary
                    }
                }
            }




            Item {
                width: parent.width
                height: Theme.spacingXS
            }
        }
    }


    popoutWidth: 320
    popoutHeight: 0
}
