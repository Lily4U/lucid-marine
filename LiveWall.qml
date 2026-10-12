import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton

// Live wallpapers: a video from the wallpaper folder playing behind the desktop.
// set-wallpaper.sh puts the video's first frame on awww (the colours come from
// it too) and its path in ~/.cache/current_live_wallpaper; this starts
// lucidlive/LiveShell.qml, a quickshell of its own, to play the video over that
// frame, and tells it through a state file where to hold still: under windows,
// in game mode, behind the lock screen. Settings -> Theme -> Live wallpapers.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // one per shell, so a second copy (a test one, say) never drives this player
    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/lucid-live-" + Qt.md5(Quickshell.shellDir).substring(0, 8) + ".json"
    readonly property string childConfig: Quickshell.shellDir + "/lucidlive/LiveShell.qml"
    readonly property var videoExts: ["mp4", "webm", "mkv", "mov", "m4v"]

    property string video: ""
    property bool gameMode: false
    // "still" in game mode leaves the first frame on awww and stops the player
    readonly property bool wanted: Prefs.liveWallpapers && root.video !== "" && !(root.gameMode && Prefs.liveGameMode === "still")
    // Qt's own order puts CUDA first, which wakes a hybrid laptop's dGPU for a
    // wallpaper: auto asks the integrated GPU first
    readonly property string decoders: ({
        "auto": "vaapi,cuda",
        "vaapi": "vaapi",
        "cuda": "cuda",
        "cpu": ""
    })[Prefs.liveDecoder] ?? "vaapi,cuda"
    // output name -> whether the video plays there
    readonly property var playing: {
        const out = {};
        const mons = Hyprland.monitors.values;
        for (let i = 0; i < mons.length; i++) {
            const ws = mons[i].activeWorkspace;
            const windows = ws ? ws.toplevels.values.length : 0;
            let still = Lockscreen.locked || (root.gameMode && Prefs.liveGameMode === "pause");
            if (Prefs.livePauseUnder === "any")
                still = still || windows > 0;
            else if (Prefs.livePauseUnder === "fullscreen")
                still = still || (ws !== null && ws.hasFullscreen);
            out[mons[i].name] = !still;
        }
        return out;
    }
    readonly property string state: JSON.stringify({
        "video": root.video,
        "playing": root.playing
    })
    property int failures: 0

    function isVideo(path) {
        const dot = path.lastIndexOf(".");
        return dot > 0 && root.videoExts.indexOf(path.substring(dot + 1).toLowerCase()) !== -1;
    }

    function sync() {
        if (root.wanted) {
            linger.stop();
            if (!child.running && !sweep.running)
                sweep.running = true;

        } else if (child.running) {
            // back to a picture: the player fades the video out over the
            // transition awww is already running, then goes
            if (root.video === "")
                linger.restart();
            else
                child.running = false;
        }
    }

    onWantedChanged: root.sync()
    onStateChanged: stateView.setText(root.state)
    // a new decoder needs a new process
    onDecodersChanged: {
        if (child.running) {
            child.running = false;
            restart.restart();
        }
    }
    Component.onCompleted: stateView.setText(root.state)

    FileView {
        path: root.home + "/.cache/current_live_wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.video = text().trim()
        onLoadFailed: root.video = ""
    }

    FileView {
        id: stateView

        path: root.stateFile
        atomicWrites: true
        printErrors: false
    }

    FileView {
        path: Prefs.gameModeStateFile
        watchChanges: Prefs.gameModeStateFile !== ""
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.gameMode = true
        onLoadFailed: root.gameMode = false
    }

    // a player left over from a shell that crashed would play under a new one
    Process {
        id: sweep

        command: ["quickshell", "kill", "-p", root.childConfig]
        onExited: layerOrder.running = true
    }

    // The player, awww and the desktop's icons and widgets all sit on the
    // background layer, stacked in the order they appeared, which would put the
    // video over the icons. A higher layer-rule order sits further back, so awww
    // goes to 2, the player to 1 and the rest stays at 0. Set here rather than in
    // modules/layerrules.lua, which an update does not rewrite; once per Lua
    // state, so again after Hyprland reloads its config
    Process {
        id: layerOrder

        command: ["hyprctl", "eval", "if not LucidLiveOrder then LucidLiveOrder = true " + "hl.layer_rule({ match = { namespace = \"awww-daemon\" }, order = 2 }) " + "hl.layer_rule({ match = { namespace = \"swww-daemon\" }, order = 2 }) " + "hl.layer_rule({ match = { namespace = \"lucid-live\" }, order = 1 }) end"]
        onExited: {
            if (root.wanted && !child.running)
                child.running = true;

        }
    }

    Connections {
        function onRawEvent(event) {
            if (event.name === "configreloaded" && child.running && !layerOrder.running)
                layerOrder.running = true;

        }

        target: Hyprland
    }

    Process {
        id: child

        command: ["quickshell", "-p", root.childConfig]
        environment: ({
            "QT_FFMPEG_DECODING_HW_DEVICE_TYPES": root.decoders,
            "LUCID_LIVE_STATE": root.stateFile
        })
        onStarted: alive.restart()
        onExited: (code) => {
            alive.stop();
            if (!root.wanted)
                return;

            // a player that keeps dying leaves the frame on awww
            root.failures++;
            if (root.failures < 4)
                restart.restart();
            else
                console.warn("LiveWall: the player stopped", root.failures, "times; leaving the still frame");
        }
    }

    Timer {
        id: linger

        interval: 800
        onTriggered: {
            if (!root.wanted)
                child.running = false;

        }
    }

    Timer {
        id: restart

        interval: 1000
        onTriggered: root.sync()
    }

    // a player that runs for a minute has settled
    Timer {
        id: alive

        interval: 60000
        onTriggered: root.failures = 0
    }

}
