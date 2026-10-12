import QtMultimedia
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The live wallpaper, as a quickshell instance of its own: LiveWall.qml starts it
// with `quickshell -p` and the decoder it is to use in its environment, because
// Qt Multimedia reads QT_FFMPEG_DECODING_HW_DEVICE_TYPES once per process. It
// draws a video on the background layer of every screen and nothing else; what
// plays, and where it is paused, comes from the state file the shell writes.
// The first frame of the same video sits under it on awww, so a video that is
// not up yet, fails, or fades away shows the picture it starts from.
ShellRoot {
    id: root

    property string video: ""
    // output name -> false where the video holds still
    property var playing: ({})

    function urlFor(path) {
        return path === "" ? "" : "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    FileView {
        path: Quickshell.env("LUCID_LIVE_STATE") || ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.video = typeof s.video === "string" ? s.video : "";
                root.playing = s.playing || {};
            } catch (e) {
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            readonly property bool play: root.playing[win.modelData.name] !== false
            // what the player holds; it trails root.video by a fade
            property string loaded: ""
            property bool ready: false
            readonly property bool hasFrame: player.mediaStatus === MediaPlayer.BufferedMedia || player.mediaStatus === MediaPlayer.BufferingMedia

            function settle() {
                // back on the video still loaded, as a quick browse can be
                if (win.loaded === root.video) {
                    win.ready = win.loaded !== "" && win.hasFrame;
                    return;
                }

                if (out.opacity > 0) {
                    win.ready = false;
                    return;
                }
                win.loaded = root.video;
                player.source = root.urlFor(win.loaded);
                if (win.loaded !== "")
                    win.play ? player.play() : player.pause();

            }

            screen: win.modelData
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "lucid-live"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            Component.onCompleted: win.settle()
            onPlayChanged: {
                if (win.loaded !== "")
                    win.play ? player.play() : player.pause();

            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Connections {
                function onVideoChanged() {
                    win.settle();
                }

                target: root
            }

            // nothing here takes the pointer: the desktop above it does
            mask: Region {
            }

            MediaPlayer {
                id: player

                loops: MediaPlayer.Infinite
                videoOutput: out
                // shown once a frame is up; the first one is the picture under it
                onMediaStatusChanged: {
                    if (win.hasFrame)
                        win.ready = win.loaded !== "" && win.loaded === root.video;
                    else if (player.mediaStatus === MediaPlayer.InvalidMedia || player.mediaStatus === MediaPlayer.NoMedia)
                        win.ready = false;
                }
                onErrorOccurred: (error, errorString) => {
                    console.warn("lucid-live:", errorString);
                    win.ready = false;
                }
            }

            VideoOutput {
                id: out

                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                opacity: win.ready ? 1 : 0
                // a new video waits for the old one to fade, then loads
                onOpacityChanged: {
                    if (out.opacity === 0)
                        win.settle();

                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

    }

}
