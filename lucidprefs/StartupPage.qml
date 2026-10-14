import QtQuick
import Quickshell
import qs
import qs.lucidui

Column {
    id: page

    // the XDG entries meant for this desktop, and the rest
    readonly property var forHere: Startup.xdgEntries.filter((e) => {
        return e.applies;
    })
    // two packages can ship the same entry under two names
    readonly property var notHere: {
        const seen = {};
        return Startup.xdgEntries.filter((e) => {
            const k = e.name + "\n" + e.reason;
            if (e.applies || seen[k])
                return false;

            seen[k] = true;
            return true;
        });
    }
    property string newName: ""
    property string newValue: ""
    readonly property string newProblem: page.newName === "" ? "" : Startup.nameProblem(page.newName, -1)

    function addVar() {
        if (Startup.addVar(page.newName, page.newValue)) {
            nameField.clear();
            valueField.clear();
            page.newName = "";
            page.newValue = "";
        }
    }

    function twinText(program) {
        const e = Startup.xdgTwin(program);
        return e ? "\"" + e.name + "\" in system autostart below starts it too, so it opens twice." : "";
    }

    spacing: Theme.dp(18)
    Component.onCompleted: Startup.refreshXdg()

    SettingCard {
        visible: Startup.moduleProbed && !Startup.moduleInstalled

        SettingRow {
            title: "Not set up"
            warning: "This page writes ~/.config/hypr/lucid-startup.lua, and your Hyprland config does not read it. Run the installer with --with-hypr, or copy Lucid's modules/startup.lua into ~/.config/hypr/modules/ and add require(\"modules.startup\") to hyprland.lua, after modules.env."
            showDivider: false
        }

    }

    SettingCard {
        title: "APPS"
        subtitle: "Opened each time you log in, after the shell is up."

        Repeater {
            model: Startup.apps

            SettingRow {
                id: appRow

                required property var modelData
                required property int index

                title: modelData.name || modelData.cmd
                monoTitle: !modelData.entry
                description: modelData.entry ? "" : modelData.cmd
                warning: modelData.on !== false ? page.twinText(Startup.programOf(modelData.cmd)) : ""

                Row {
                    spacing: Theme.dp(4)

                    M3IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconPath: "play_arrow"
                        onClicked: Startup.runApp(appRow.index)
                    }

                    M3IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconPath: "delete"
                        destructive: true
                        onClicked: Startup.removeApp(appRow.index)
                    }

                    M3Switch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: appRow.modelData.on !== false
                        onToggled: (v) => {
                            return Startup.setApp(appRow.index, {
                                "on": v
                            });
                        }
                    }

                }

            }

        }

        SettingRow {
            title: Startup.apps.length > 0 ? "Add another" : "Nothing yet"
            description: "Pick an installed app, or type a command and press Enter."
            stacked: true

            Row {
                width: parent.width
                spacing: Theme.dp(10)

                M3Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add an app"
                    variant: "tonal"
                    iconPath: "add"
                    onClicked: Prefs.appPickerRequested(Startup.pickerKey)
                }

                M3TextField {
                    id: commandField

                    width: Math.min(parent.width - x, Theme.dp(420))
                    placeholder: "A command, such as nextcloud --background"
                    commitOnBlur: false
                    onAccepted: (value) => {
                        Startup.addCommand(value);
                        commandField.clear();
                    }
                    onCancelled: commandField.clear()
                }

            }

        }

        SettingRow {
            visible: Startup.configApps.length > 0
            title: "Also in modules/autostart.lua"
            description: "Edit that file to change these."
            stacked: true

            Column {
                width: parent.width
                spacing: Theme.dp(6)

                Repeater {
                    model: Startup.configApps

                    Column {
                        required property var modelData
                        readonly property string twin: page.twinText(modelData.program)

                        width: parent.width
                        spacing: Theme.dp(2)

                        Text {
                            width: parent.width
                            text: modelData.cmd
                            color: Theme.subtext
                            font.family: "monospace"
                            font.pixelSize: Theme.fontBodySm
                            elide: Text.ElideRight
                        }

                        Text {
                            visible: parent.twin !== ""
                            width: parent.width
                            text: parent.twin
                            color: Theme.error
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontBodySm
                            wrapMode: Text.Wrap
                        }

                    }

                }

            }

        }

    }

    SettingCard {
        title: "SYSTEM AUTOSTART"
        subtitle: "What apps put in ~/.config/autostart when you tick \"start at login\" in them, and what packages install for every desktop."

        SettingRow {
            title: Startup.xdgBySession ? "Started by your session" : "Start them with Hyprland"
            description: Startup.xdgBySession ? "Your session manager already starts these, so the switches below are all there is to it." : "Hyprland on its own does not read these. On, Lucid starts them at your next login the way a desktop session would."
            resetKey: Startup.xdgBySession ? "" : "startupXdg"

            M3Switch {
                visible: !Startup.xdgBySession
                checked: Prefs.startupXdg
                onToggled: (v) => {
                    return Prefs.startupXdg = v;
                }
            }

        }

        SettingRow {
            title: "Entries"
            description: !Startup.xdgProbed ? "Reading…" : (page.forHere.length === 0 ? "None for this desktop." : "Switching one off hides it for you alone, as any desktop does; the system's copy is left as it is.")
            stacked: true
            enabled: Startup.xdgStarts && !Startup.xdgBusy
            disabledReason: Startup.xdgBusy ? "Saving…" : "Not started at the moment: the switch above is off."

            Column {
                width: parent.width
                spacing: Theme.dp(14)

                Repeater {
                    model: page.forHere

                    CheckLine {
                        required property var modelData

                        width: parent.width
                        label: modelData.name + (modelData.installed ? "" : "  (not installed)")
                        icon: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                        checked: modelData.enabled
                        enabled: !Startup.xdgBusy
                        onToggled: Startup.setXdg(modelData.id, !checked)
                    }

                }

            }

        }

        SettingRow {
            visible: page.notHere.length > 0
            title: "Not started here"
            description: page.notHere.map((e) => {
                return e.name + " (" + e.reason + ")";
            }).join(", ")
            stacked: true
            showDivider: false
        }

    }

    SettingCard {
        title: "ENVIRONMENT VARIABLES"
        subtitle: "Set for every app you open. Apps from keybinds see a change at once; the dock and the launcher at your next login."

        Repeater {
            model: Startup.vars

            SettingRow {
                id: varRow

                required property var modelData
                required property int index
                readonly property string problem: Startup.nameProblem(modelData.name, index)
                readonly property string state: Startup.varState(modelData)

                title: modelData.name
                monoTitle: true
                stacked: true
                description: varRow.state === "active" ? "In force." : (varRow.state === "pending" ? "Set. The dock and the launcher pick it up at your next login." : "")
                warning: varRow.problem !== "" ? varRow.problem : (modelData.name === "PATH" && modelData.on !== false ? "Replaces the whole search path: put the current one in it too, or apps stop being found." : "")

                Row {
                    width: parent.width
                    spacing: Theme.dp(4)

                    M3TextField {
                        width: Math.min(parent.width - Theme.dp(110), Theme.dp(520))
                        text: varRow.modelData.value
                        placeholder: "Value"
                        onAccepted: (value) => {
                            return Startup.setVar(varRow.index, {
                                "value": value
                            });
                        }
                    }

                    M3IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconPath: "delete"
                        destructive: true
                        onClicked: Startup.removeVar(varRow.index)
                    }

                    M3Switch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: varRow.modelData.on !== false
                        onToggled: (v) => {
                            return Startup.setVar(varRow.index, {
                                "on": v
                            });
                        }
                    }

                }

            }

        }

        SettingRow {
            visible: Startup.lingering.length > 0
            title: "Still set until you log in again"
            description: Startup.lingering.join(", ") + ": taken off the list, but apps opened from now on still get " + (Startup.lingering.length === 1 ? "it" : "them") + " until the next login."
        }

        SettingRow {
            title: "Add a variable"
            stacked: true
            warning: page.newProblem

            Row {
                width: parent.width
                spacing: Theme.dp(10)

                M3TextField {
                    id: nameField

                    width: Theme.dp(220)
                    placeholder: "NAME"
                    commitOnBlur: false
                    error: page.newProblem !== ""
                    onEdited: (value) => {
                        return page.newName = value.trim();
                    }
                    onAccepted: page.addVar()
                }

                M3TextField {
                    id: valueField

                    width: Math.min(parent.width - x - Theme.dp(110), Theme.dp(300))
                    placeholder: "value"
                    commitOnBlur: false
                    onEdited: (value) => {
                        return page.newValue = value;
                    }
                    onAccepted: page.addVar()
                }

                M3Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add"
                    variant: "filled"
                    enabled: page.newName !== "" && page.newProblem === ""
                    onClicked: page.addVar()
                }

            }

        }

        SettingRow {
            visible: Startup.configVars.length > 0
            title: "Also in modules/env.lua"
            description: Startup.configVars.map((v) => {
                return v.name + "=" + v.value;
            }).join("   ")
            stacked: true
            showDivider: false
        }

    }

}
