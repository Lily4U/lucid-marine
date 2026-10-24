import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.lucidui

// CURRENTLY THERE ARE ONLY E-Z Services; Feel free to add other hosts like Imgur or catbox ;)
Column {
    id: page

    // the helper sits in ImageServices/, next to the rest of the shell
    readonly property string tool: Quickshell.shellDir + "/ImageServices/ezhost.py"

    property bool probed: false
    property bool hasKey: false
    property bool keyPrivate: true
    property string keyFile: ""
    property string newKey: ""
    property bool busy: false
    property string problem: ""

    function refresh() {
        statusProc.running = true;
    }

    function saveKey() {
        const k = page.newKey.trim();
        if (k === "" || page.busy)
            return ;

        page.busy = true;
        page.problem = "";
        // in the environment, not the command line, so ps never shows it
        setProc.environment = ({
            "EZ_HOST_NEW_KEY": k
        });
        setProc.running = true;
    }

    function forgetKey() {
        if (page.busy)
            return ;

        page.busy = true;
        page.problem = "";
        clearProc.running = true;
    }

    spacing: Theme.dp(18)
    Component.onCompleted: page.refresh()

    Process {
        id: statusProc

        command: ["python3", page.tool, "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(this.text);
                    page.hasKey = s.hasKey === true;
                    page.keyPrivate = s.private !== false;
                    page.keyFile = s.keyFile || "";
                    page.problem = "";
                } catch (e) {
                    page.problem = "Could not read the key's state.";
                }
                page.probed = true;
            }
        }

    }

    Process {
        id: setProc

        command: ["python3", page.tool, "set-key"]
        onExited: (code) => {
            // do not leave the key sitting in the object
            setProc.environment = ({});
            page.busy = false;
            if (code === 0) {
                keyField.clear();
                page.newKey = "";
                page.refresh();
            } else {
                page.problem = "Could not save the key.";
            }
        }
    }

    Process {
        id: clearProc

        command: ["python3", page.tool, "clear-key"]
        onExited: (code) => {
            page.busy = false;
            if (code !== 0)
                page.problem = "Could not remove the key.";

            page.refresh();
        }
    }

    SettingCard {
        title: "E-Z HOST"
        subtitle: "Where the upload button on a screenshot's preview card sends the image."

        SettingRow {
            title: "API key"
            description: !page.probed ? "Reading…" : (page.hasKey ? "A key is saved. It is never shown again; type a new one to replace it." : "No key yet. Paste your e-z.host API key below and press Save.")
            warning: page.problem !== "" ? page.problem : (page.hasKey && !page.keyPrivate ? "The key file can be read by other accounts on this machine. Saving the key again fixes that." : "")
            stacked: true

            Row {
                width: parent.width
                spacing: Theme.dp(10)

                M3TextField {
                    id: keyField

                    width: Math.min(parent.width - Theme.dp(190), Theme.dp(420))
                    placeholder: "API key"
                    commitOnBlur: false
                    enabled: !page.busy
                    onEdited: (value) => {
                        return page.newKey = value;
                    }
                    onAccepted: (value) => {
                        page.newKey = value;
                        page.saveKey();
                    }
                }

                M3Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Save"
                    variant: "filled"
                    enabled: page.newKey.trim() !== "" && !page.busy
                    onClicked: page.saveKey()
                }

                M3IconButton {
                    visible: page.hasKey
                    anchors.verticalCenter: parent.verticalCenter
                    iconPath: "delete"
                    destructive: true
                    onClicked: page.forgetKey()
                }

            }

        }

        SettingRow {
            title: "How to use it"
            description: "Take a screenshot, then press the upload button on its preview card. The link is copied to your clipboard and a notification shows it."
        }

        SettingRow {
            visible: page.keyFile !== ""
            title: "Where the key is kept"
            description: page.keyFile
            monoTitle: false
            showDivider: false
        }

    }

}
