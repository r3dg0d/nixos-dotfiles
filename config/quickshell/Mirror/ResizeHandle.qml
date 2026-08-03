import QtQuick

MouseArea {
    id: handle

    required property var window
    property int edge: Qt.RightEdge
    property int thickness: 12

    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: (edge === Qt.LeftEdge || edge === Qt.RightEdge) ? Qt.SizeHorCursor : Qt.SizeVerCursor
    width: (edge === Qt.LeftEdge || edge === Qt.RightEdge) ? thickness : parent.width
    height: (edge === Qt.TopEdge || edge === Qt.BottomEdge) ? thickness : parent.height
    z: 20

    onPressed: function(mouse) {
        window.startSystemResize(edge);
        mouse.accepted = true;
    }
}
