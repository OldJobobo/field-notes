import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// A black foldback binder clip seen from the front, gripping the top edge of the paper at
// y = 26: the back wire handle, the clip body, the front wire handle running over the body,
// and the rolled jaw lip the wire tucks into.
Item {
    id: root

    property bool hovered: false
    // Picked up: the clip rises a little off the paper while the board is dragged.
    property bool lifted: false
    // The paper's rotation, so the clip sits along its tilted edge.
    property real tilt: 0
    readonly property real cx: width / 2
    readonly property color wire: lifted || hovered ? "#eef0f2" : "#c3c7cc"

    implicitWidth: 120
    implicitHeight: 50

    transform: Rotation {
        origin.x: root.cx
        origin.y: 26
        angle: root.tilt
    }

    Item {
        id: art

        width: parent.width
        height: parent.height
        y: root.lifted ? -1 : 0
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#70000000"
            shadowBlur: root.lifted ? 0.7 : 0.45
            shadowHorizontalOffset: root.lifted ? 2 : 1
            shadowVerticalOffset: root.lifted ? 6 : 3
            autoPaddingEnabled: true
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Back handle: its legs disappear behind the body.
            ShapePath {
                strokeColor: "#2e3135"
                strokeWidth: 3.6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.cx - 28
                startY: 30

                PathLine { x: root.cx - 18.8; y: 9.5 }
                PathQuad { x: root.cx - 14; y: 5; controlX: root.cx - 19.6; controlY: 5 }
                PathLine { x: root.cx + 14; y: 5 }
                PathQuad { x: root.cx + 18.8; y: 9.5; controlX: root.cx + 19.6; controlY: 5 }
                PathLine { x: root.cx + 28; y: 30 }
            }
            ShapePath {
                strokeColor: "#8d9298"
                strokeWidth: 1.8
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.cx - 28
                startY: 30

                PathLine { x: root.cx - 18.8; y: 9.5 }
                PathQuad { x: root.cx - 14; y: 5; controlX: root.cx - 19.6; controlY: 5 }
                PathLine { x: root.cx + 14; y: 5 }
                PathQuad { x: root.cx + 18.8; y: 9.5; controlX: root.cx + 19.6; controlY: 5 }
                PathLine { x: root.cx + 28; y: 30 }
            }

            // Body: narrower at the folded spine, which stands just above the paper edge.
            ShapePath {
                strokeColor: "#171513"
                strokeWidth: 1
                fillGradient: LinearGradient {
                    x1: 0
                    y1: 21
                    x2: 0
                    y2: 46

                    GradientStop { position: 0; color: "#514b45" }
                    GradientStop { position: 0.22; color: "#36322e" }
                    GradientStop { position: 1; color: "#1e1c1a" }
                }
                startX: root.cx - 50
                startY: 44

                PathLine { x: root.cx - 43; y: 24 }
                PathQuad { x: root.cx - 38.5; y: 21; controlX: root.cx - 42; controlY: 21 }
                PathLine { x: root.cx + 38.5; y: 21 }
                PathQuad { x: root.cx + 43; y: 24; controlX: root.cx + 42; controlY: 21 }
                PathLine { x: root.cx + 50; y: 44 }
                PathLine { x: root.cx - 50; y: 44 }
            }

            // Light catching the rounded spine.
            ShapePath {
                strokeColor: "#9a948b"
                strokeWidth: 1
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: root.cx - 37
                startY: 22.5

                PathLine { x: root.cx + 37; y: 22.5 }
            }

            // Front handle, running over the body into the jaw lip.
            ShapePath {
                strokeColor: "#3b3f44"
                strokeWidth: 3.8
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.cx - 34
                startY: 44

                PathLine { x: root.cx - 21.8; y: 6.4 }
                PathQuad { x: root.cx - 16.6; y: 1.6; controlX: root.cx - 22.8; controlY: 1.6 }
                PathLine { x: root.cx + 16.6; y: 1.6 }
                PathQuad { x: root.cx + 21.8; y: 6.4; controlX: root.cx + 22.8; controlY: 1.6 }
                PathLine { x: root.cx + 34; y: 44 }
            }
            ShapePath {
                strokeColor: root.wire
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.cx - 34
                startY: 44

                PathLine { x: root.cx - 21.8; y: 6.4 }
                PathQuad { x: root.cx - 16.6; y: 1.6; controlX: root.cx - 22.8; controlY: 1.6 }
                PathLine { x: root.cx + 16.6; y: 1.6 }
                PathQuad { x: root.cx + 21.8; y: 6.4; controlX: root.cx + 22.8; controlY: 1.6 }
                PathLine { x: root.cx + 34; y: 44 }
            }
        }

        // Rolled jaw lip pressing on the paper.
        Rectangle {
            x: root.cx - 52
            y: 42
            width: 104
            height: 6
            radius: 3
            gradient: Gradient {
                GradientStop { position: 0; color: "#625b54" }
                GradientStop { position: 0.4; color: "#2e2b28" }
                GradientStop { position: 1; color: "#121110" }
            }
        }
    }
}
