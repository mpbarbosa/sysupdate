import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool compositorChecked: false
    property bool wlroots: false
    property int systemUpdates: 0
    property string packageManager: "unknown"
    property string statusAccessibleName: {
        if (statusProcess.running) {
            return "Checking for updates";
        }

        if (root.systemUpdates > 0) {
            return "System updates: " + root.systemUpdates + " pending";
        }

        return "System: up to date";
    }
    property string statusScriptPath: {
        var url = Qt.resolvedUrl("scripts/sysupdate_status.sh").toString();
        if (url.startsWith("file://")) {
            return decodeURIComponent(url.slice(7));
        }

        return url;
    }
    property string updateScriptPath: {
        var url = Qt.resolvedUrl("scripts/run_update.sh").toString();
        if (url.startsWith("file://")) {
            return decodeURIComponent(url.slice(7));
        }

        return url;
    }

    function updateStatus() {
        if (statusProcess.running) {
            return;
        }

        statusProcess.running = true;
    }

    function runUpdates() {
        if (runUpdatesProcess.running) {
            return;
        }

        runUpdatesProcess.running = true;
        statusRefreshTimer.restart();
    }

    onCompositorCheckedChanged: {
        if (!compositorChecked) {
            return;
        }

        var comp = wlroots ? panelWindowComponent : floatingWindowComponent;
        comp.createObject(root);
        updateStatus();
    }

    // Detects wlroots compositor by checking SWAYSOCK and HYPRLAND_INSTANCE_SIGNATURE.
    Process {
        id: compositorCheck
        command: ["sh", "-c", "printf '%s:%s' \"${SWAYSOCK:-}\" \"${HYPRLAND_INSTANCE_SIGNATURE:-}\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split(":");
                root.wlroots = parts[0] !== "" || parts[1] !== "";
                root.compositorChecked = true;
            }
        }
    }

    Process {
        id: statusProcess
        command: ["bash", root.statusScriptPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var payload = JSON.parse(text.trim());
                    root.systemUpdates = Math.max(0, Math.round(Number(payload.system)));
                    root.packageManager = String(payload.package_manager || "unknown");
                } catch (error) {
                    console.error("Failed to parse sysupdate status:", error);
                    root.systemUpdates = 0;
                    root.packageManager = "unknown";
                }
            }
        }
    }

    Process {
        id: runUpdatesProcess
        command: ["gnome-terminal", "--", "bash", root.updateScriptPath]
        running: false
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.updateStatus()
    }

    Timer {
        id: statusRefreshTimer
        interval: 15000
        repeat: false
        onTriggered: root.updateStatus()
    }

    component SysupdateContent: Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#cc1e1e2e"
        border.color: "#665f7a"

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "sysupdate"
                color: "#cdd6f4"
                font.pixelSize: 16
                font.bold: true
            }

            Text {
                width: parent.width
                text: statusProcess.running
                    ? "Checking for updates..."
                    : (root.systemUpdates > 0
                        ? "System updates: " + root.systemUpdates + " pending"
                        : "System: up to date")
                color: "#cdd6f4"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                Accessible.name: root.statusAccessibleName
            }

            Rectangle {
                width: parent.width
                height: 28
                radius: 6
                color: runBtn.pressed ? "#6689b4fa" : (runBtn.containsMouse ? "#4489b4fa" : "#2289b4fa")
                border.color: "#4489b4fa"

                Text {
                    anchors.centerIn: parent
                    text: "Run Updates"
                    color: "#cdd6f4"
                    font.pixelSize: 12
                }

                MouseArea {
                    id: runBtn
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.runUpdates()
                    Accessible.role: Accessible.Button
                    Accessible.name: "Run sysupdate"
                }
            }
        }
    }

    // wlroots compositors (Sway, Hyprland): anchored panel via layershell.
    Component {
        id: panelWindowComponent
        PanelWindow {
            anchors {
                top: true
                right: true
            }
            margins {
                top: 12
                right: 12
            }
            implicitWidth: 260
            implicitHeight: 120
            color: "transparent"

            SysupdateContent {}
        }
    }

    // GNOME and other compositors: floating window without layershell.
    Component {
        id: floatingWindowComponent
        FloatingWindow {
            implicitWidth: 260
            implicitHeight: 120
            color: "transparent"

            SysupdateContent {}
        }
    }
}
