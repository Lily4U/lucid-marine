import "../luciddocks"
import QtQuick
import QtQuick.Shapes
import qs

// the things on the desk, drawn rather than taken from the icon theme, in the
// hand of the rest of the shell: flat fills with no gloss or shadow, the
// accent for what you act on, the cards' own surface for paper. A folder with
// its tab and a sheet inside, a page with a folded corner and its type on a
// chip, and a bin with a lid. A folder comes in two parts - its back, and the
// front flap - so what it holds can fan out between them
Item {
    id: obj

    // "folder", "home", "document" or "trash"
    property string kind: "folder"
    // "back" or "front"; a page and the bin are all front
    property string part: "front"
    // the side of the square it is drawn in
    property real size: Theme.dp(64)
    // 0 shut, 1 open: the folder's flap, the bin's lid
    property real open: 0
    // the bin with something in it
    property bool full: false
    // a page's type, as a word on its chip, and what is on the page: lines of
    // "text", a zip down an "archive", a note for "audio", a play mark for "video"
    property string tag: ""
    property string variant: "text"

    readonly property real s: obj.size
    // the shell's corner dial, kept within what reads at icon size
    readonly property real k: Math.max(0.15, Math.min(1.5, Theme.cornerScale))
    readonly property real r: Math.max(1.5, obj.s * 0.11 * obj.k)
    readonly property bool isFolder: obj.kind === "folder" || obj.kind === "home"
    readonly property real hairline: Math.max(1, Theme.dp(1))

    // the palette: a folder in the accent the shell fills its buttons with,
    // its back a step deeper; paper is the cards' own surface, its ink the
    // cards' text. Never the tertiary
    readonly property color folderFront: Theme.accent
    readonly property color folderBack: Theme.atTone(Theme.accent, Theme.toneOf(Theme.accent) + (Theme.isLight ? 14 : -16))
    readonly property color folderInk: Theme.fgAccent
    readonly property color paper: Theme.bgOpaque
    readonly property color paperFold: Theme.bgHigh
    readonly property color paperEdge: Theme.alpha(Theme.text, Theme.isLight ? 0.14 : 0.12)
    readonly property color ink: Theme.text
    readonly property color binBody: Theme.bgOpaque
    readonly property color binLid: Theme.bgHigh
    readonly property color binRib: Theme.alpha(Theme.text, 0.2)

    // a gulp: something just went in the bin
    property real gulp: 0
    readonly property real lid: Math.max(obj.open, obj.gulp, obj.full ? 0.28 : 0)

    function swallow() {
        gulpAnim.restart();
    }

    width: obj.s
    height: obj.s

    SequentialAnimation {
        id: gulpAnim

        NumberAnimation {
            target: obj
            property: "gulp"
            to: 1
            duration: 140
            easing.type: Easing.OutQuad
        }

        PauseAnimation {
            duration: 120
        }

        NumberAnimation {
            target: obj
            property: "gulp"
            to: 0
            duration: 420
            easing.type: Easing.OutBounce
        }

    }

    // ---- a folder: the back with its tab, and a sheet standing in it ------

    Shape {
        id: back

        readonly property real x0: obj.s * 0.06
        readonly property real x1: obj.s * 0.94
        readonly property real yTab: obj.s * 0.13
        readonly property real yTop: obj.s * 0.22
        readonly property real yBot: obj.s * 0.88
        readonly property real tabEnd: obj.s * 0.42
        readonly property real slant: obj.s * 0.07
        readonly property real rt: Math.min(obj.r, (back.yTop - back.yTab) * 0.9)

        anchors.fill: parent
        visible: obj.isFolder && obj.part === "back"
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: obj.folderBack
            strokeColor: "transparent"
            pathHints: ShapePath.PathFillOnRight | ShapePath.PathSolid | ShapePath.PathNonIntersecting

            PathSvg {
                path: {
                    var b = back;
                    var r = obj.r;
                    var t = b.rt;
                    return "M " + b.x0 + " " + (b.yTab + t) + " Q " + b.x0 + " " + b.yTab + " " + (b.x0 + t) + " " + b.yTab + " L " + (b.tabEnd - t * 0.6) + " " + b.yTab + " Q " + b.tabEnd + " " + b.yTab + " " + (b.tabEnd + t * 0.5) + " " + (b.yTab + t * 0.6) + " L " + (b.tabEnd + b.slant - t * 0.5) + " " + (b.yTop - t * 0.6) + " Q " + (b.tabEnd + b.slant) + " " + b.yTop + " " + (b.tabEnd + b.slant + t) + " " + b.yTop + " L " + (b.x1 - r) + " " + b.yTop + " Q " + b.x1 + " " + b.yTop + " " + b.x1 + " " + (b.yTop + r) + " L " + b.x1 + " " + (b.yBot - r) + " Q " + b.x1 + " " + b.yBot + " " + (b.x1 - r) + " " + b.yBot + " L " + (b.x0 + r) + " " + b.yBot + " Q " + b.x0 + " " + b.yBot + " " + b.x0 + " " + (b.yBot - r) + " Z";
                }
            }

        }

        // the sheet inside, a card of the shell's surface that rises as the
        // flap opens
        Rectangle {
            x: obj.s * 0.15
            y: obj.s * (0.28 - 0.1 * obj.open)
            width: obj.s * 0.7
            height: obj.s * 0.5
            radius: Math.max(1, obj.r * 0.6)
            color: obj.paperFold
            antialiasing: true

            Rectangle {
                x: parent.width * 0.12
                y: parent.height * 0.14
                width: parent.width * 0.32
                height: Math.max(1.5, obj.s * 0.035)
                radius: height / 2
                color: Theme.accent
            }

        }

    }

    // the front flap, which tips open toward you from its bottom edge
    Rectangle {
        id: flap

        x: obj.s * 0.06
        y: obj.s * 0.35
        width: obj.s * 0.88
        height: obj.s * 0.53
        visible: obj.isFolder && obj.part === "front"
        radius: obj.r
        color: obj.folderFront
        antialiasing: true
        transform: Rotation {
            origin.x: flap.width / 2
            origin.y: flap.height
            axis.x: 1
            axis.y: 0
            axis.z: 0
            distanceToPlane: obj.s * 3
            angle: -obj.open * 26
        }

        DockGlyph {
            visible: obj.kind === "home"
            anchors.centerIn: parent
            width: parent.height * 0.58
            height: width
            pathData: DesktopIcons.glyphs.home
            glyphColor: obj.folderInk
            fill: 1
        }

    }

    // ---- a page ------------------------------------------------------------

    Item {
        id: page

        readonly property real w: obj.s * 0.7
        readonly property real h: obj.s * 0.88
        readonly property real px0: (obj.s - page.w) / 2
        readonly property real py0: obj.s * 0.06
        readonly property real ear: page.w * 0.3
        // where what is on the page starts and how wide it runs
        readonly property real inX: page.px0 + page.w * 0.16
        readonly property real inW: page.w * 0.68

        anchors.fill: parent
        visible: obj.kind === "document"

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // the card's surface with a hairline edge, the way a widget sits
            // on the wallpaper
            ShapePath {
                fillColor: obj.paper
                strokeColor: obj.paperEdge
                strokeWidth: obj.hairline
                pathHints: ShapePath.PathSolid | ShapePath.PathNonIntersecting

                PathSvg {
                    path: {
                        var x = page.px0;
                        var y = page.py0;
                        var w = page.w;
                        var h = page.h;
                        var e = page.ear;
                        var r = Math.min(obj.r, e * 0.6);
                        return "M " + (x + r) + " " + y + " L " + (x + w - e) + " " + y + " L " + (x + w) + " " + (y + e) + " L " + (x + w) + " " + (y + h - r) + " Q " + (x + w) + " " + (y + h) + " " + (x + w - r) + " " + (y + h) + " L " + (x + r) + " " + (y + h) + " Q " + x + " " + (y + h) + " " + x + " " + (y + h - r) + " L " + x + " " + (y + r) + " Q " + x + " " + y + " " + (x + r) + " " + y + " Z";
                    }
                }

            }

            // the folded corner, a tone up from the page
            ShapePath {
                fillColor: obj.paperFold
                strokeColor: "transparent"

                PathSvg {
                    path: {
                        var x = page.px0 + page.w - page.ear;
                        var y = page.py0;
                        var e = page.ear;
                        var r = Math.min(obj.r * 0.7, e * 0.4);
                        return "M " + x + " " + y + " L " + x + " " + (y + e - r) + " Q " + x + " " + (y + e) + " " + (x + r) + " " + (y + e) + " L " + (x + e) + " " + (y + e) + " Z";
                    }
                }

            }

        }

        // text: a short accent rule over the lines, the way a widget heads
        // its figures with a label in the accent
        Repeater {
            model: page.visible && obj.variant === "text" ? 4 : 0

            Rectangle {
                required property int index

                x: page.inX
                y: page.py0 + page.h * (0.3 + index * 0.12)
                width: page.inW * [0.42, 0.9, 0.9, 0.56][index]
                height: Math.max(1.5, obj.s * (index === 0 ? 0.05 : 0.034))
                radius: height / 2
                color: index === 0 ? Theme.accent : Theme.alpha(obj.ink, index === 1 ? 0.42 : 0.22)
            }

        }

        // an archive: a zip down the middle of the page, and its pull
        Item {
            id: zip

            readonly property real tooth: Math.max(1.5, obj.s * 0.035)

            visible: obj.variant === "archive"
            x: page.px0 + page.w / 2
            y: page.py0

            Repeater {
                model: zip.visible ? Math.floor(page.h * 0.42 / zip.tooth) : 0

                Rectangle {
                    required property int index

                    x: index % 2 === 0 ? -zip.tooth * 1.6 : 0
                    y: index * zip.tooth
                    width: zip.tooth * 1.6
                    height: zip.tooth * 0.8
                    radius: height / 2
                    color: Theme.alpha(obj.ink, 0.32)
                }

            }

            Rectangle {
                x: -width / 2
                y: page.h * 0.42
                width: obj.s * 0.13
                height: obj.s * 0.17
                radius: Math.min(width / 2, Math.max(1.5, obj.r * 0.6))
                color: Theme.accent
                antialiasing: true

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.5
                    width: parent.width * 0.4
                    height: parent.height * 0.3
                    radius: width / 2
                    color: obj.paper
                }

            }

        }

        // audio and video: the media widget's own button, an accent disc with
        // the mark on it
        Rectangle {
            visible: obj.variant === "audio" || obj.variant === "video"
            x: page.px0 + (page.w - width) / 2
            y: page.py0 + page.h * 0.24
            width: page.w * 0.56
            height: width
            radius: width / 2
            color: Theme.accent
            antialiasing: true

            DockGlyph {
                anchors.centerIn: parent
                                width: parent.width * 0.62
                height: width
                pathData: obj.variant === "video" ? DesktopIcons.glyphs.play : DesktopIcons.glyphs.note
                glyphColor: Theme.fgAccent
                fill: 1
            }

        }

        // its type, on a chip at the foot of the page
        Rectangle {
            visible: obj.tag !== "" && obj.s >= 40
            x: page.inX - page.w * 0.04
            y: page.py0 + page.h - height - page.h * 0.09
            width: Math.min(page.w * 0.84, Math.max(height * 1.5, tagText.implicitWidth + obj.s * 0.1))
            height: Math.round(obj.s * 0.2)
            radius: Theme.pill(height)
            color: Theme.alpha(Theme.accent, Theme.isLight ? 0.16 : 0.2)
            antialiasing: true

            Text {
                id: tagText

                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - obj.s * 0.06)
                text: obj.tag
                color: Theme.accent
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(7, Math.round(obj.s * 0.13))
                font.weight: Font.Bold
                font.letterSpacing: Math.max(0.4, obj.s * 0.012)
            }

        }

    }

    // ---- the bin -----------------------------------------------------------

    Item {
        id: bin

        anchors.fill: parent
        visible: obj.kind === "trash"

        // what was thrown away, sticking up out of it
        Repeater {
            model: obj.full ? 2 : 0

            Rectangle {
                required property int index

                x: obj.s * (index === 0 ? 0.3 : 0.46)
                y: obj.s * (index === 0 ? 0.2 : 0.23) - obj.lid * obj.s * 0.03
                width: obj.s * 0.24
                height: obj.s * 0.3
                radius: Math.max(1, obj.r * 0.5)
                rotation: index === 0 ? -14 : 10
                color: index === 0 ? Theme.accent : obj.paperFold
                antialiasing: true
            }

        }

        Shape {
            id: can

            readonly property real yTop: obj.s * 0.33
            readonly property real yBot: obj.s * 0.93
            readonly property real top0: obj.s * 0.21
            readonly property real top1: obj.s * 0.79
            readonly property real bot0: obj.s * 0.28
            readonly property real bot1: obj.s * 0.72

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transformOrigin: Item.Bottom
            scale: 1 + obj.gulp * 0.04

            ShapePath {
                fillColor: obj.binBody
                strokeColor: obj.paperEdge
                strokeWidth: obj.hairline
                pathHints: ShapePath.PathSolid | ShapePath.PathNonIntersecting

                PathSvg {
                    path: {
                        var r = obj.r * 0.9;
                        var c = can;
                        return "M " + c.top0 + " " + c.yTop + " L " + c.top1 + " " + c.yTop + " L " + (c.bot1 + r * 0.12) + " " + (c.yBot - r) + " Q " + c.bot1 + " " + c.yBot + " " + (c.bot1 - r) + " " + c.yBot + " L " + (c.bot0 + r) + " " + c.yBot + " Q " + c.bot0 + " " + c.yBot + " " + (c.bot0 - r * 0.12) + " " + (c.yBot - r) + " Z";
                    }
                }

            }

            // three ribs down its side
            ShapePath {
                strokeColor: obj.binRib
                strokeWidth: Math.max(1.5, obj.s * 0.04)
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"

                PathMove {
                    x: obj.s * 0.37
                    y: obj.s * 0.45
                }

                PathLine {
                    x: obj.s * 0.39
                    y: obj.s * 0.81
                }

                PathMove {
                    x: obj.s * 0.5
                    y: obj.s * 0.45
                }

                PathLine {
                    x: obj.s * 0.5
                    y: obj.s * 0.81
                }

                PathMove {
                    x: obj.s * 0.63
                    y: obj.s * 0.45
                }

                PathLine {
                    x: obj.s * 0.61
                    y: obj.s * 0.81
                }

            }

        }

        // the lid and its handle, in the accent, hinged at the left end
        Item {
            id: lidItem

            x: obj.s * 0.15
            y: obj.s * 0.21
            width: obj.s * 0.7
            height: obj.s * 0.1
            transform: [
                Rotation {
                    origin.x: 0
                    origin.y: lidItem.height
                    angle: -obj.lid * 22
                },
                Translate {
                    y: -obj.lid * obj.s * 0.07
                }
            ]

            Rectangle {
                x: parent.width * 0.33
                y: -obj.s * 0.07
                width: parent.width * 0.34
                height: obj.s * 0.11
                radius: Math.min(height / 2, obj.r * 0.8)
                color: "transparent"
                border.width: Math.max(1.5, obj.s * 0.04)
                border.color: Theme.accent
                antialiasing: true
            }

            Rectangle {
                anchors.fill: parent
                radius: Math.min(height / 2, obj.r * 0.8)
                color: Theme.accent
                antialiasing: true
            }

        }

    }

}
