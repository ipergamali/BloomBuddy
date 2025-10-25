import QtQuick 6.5
import QtQuick.Layouts 6.5
import QtQuick.Controls 6.5 as Controls
import org.kde.plasma.core 6 as PlasmaCore
import org.kde.plasma.components 6 as PlasmaComponents
import org.kde.plasma.plasmoid 2.0

PlasmoidItem {
    id: root
    width: 220
    height: 260

    property string stageName: "seed"
    property int stageIndex: 0
    property int dayCount: 1
    property bool isWilted: false
    property int daysIdle: 0

    property string currentImageSource: plasmoid.file("assets", "plant_seed.png")
    property string pendingImageSource: ""

    PlasmaCore.DataSource {
        id: plantDataSource
        engine: "executable"
        connectedSources: []

        function refresh(shouldWater) {
            var scriptPath = plasmoid.file("scripts", "plant_data.py")
            var command = "python3 " + scriptPath
            if (shouldWater) {
                command += " --water"
            }
            disconnectSource(command)
            connectSource(command)
        }

        onNewData: function (sourceName, data) {
            disconnectSource(sourceName)
            if (!data || data["exit code"] !== 0) {
                console.error("BloomBuddy: plant_data.py failed", data ? data["stderr"] : "no data")
                return
            }

            var stdout = data["stdout"]
            if (!stdout || stdout.trim().length === 0) {
                console.warn("BloomBuddy: no output from plant_data.py")
                return
            }

            var payload
            try {
                payload = JSON.parse(stdout)
            } catch (e) {
                console.error("BloomBuddy: invalid JSON from plant_data.py", stdout)
                return
            }
            applyPlantData(payload)
        }
    }

    function applyPlantData(payload) {
        stageName = payload.stage || stageName
        stageIndex = payload.stage_index !== undefined ? payload.stage_index : stageIndex
        dayCount = payload.day !== undefined ? payload.day : dayCount
        isWilted = payload.is_wilted === true
        daysIdle = payload.days_idle || 0

        var imageName = payload.image || ("assets/plant_" + stageName + ".png")
        var assetPath = plasmoid.file("assets", imageName.replace("assets/", ""))

        updateTooltip()

        if (assetPath !== currentImageSource) {
            pendingImageSource = assetPath
            stageTransition.restart()
        } else {
            plantImage.opacity = isWilted ? 0.55 : 1.0
        }
    }

    function updateTooltip() {
        var healthText = isWilted
                ? "looks a little thirsty after " + daysIdle + " days away."
                : "looks healthy!"
        plasmoid.toolTipMainText = "Day " + dayCount + " – " + capitalize(stageName)
        plasmoid.toolTipSubText = "Your BloomBuddy is on Day " + dayCount + " and " + healthText
    }

    function capitalize(text) {
        if (!text || text.length === 0)
            return ""
        return text.charAt(0).toUpperCase() + text.slice(1)
    }

    Component.onCompleted: plantDataSource.refresh(false)

    background: Rectangle {
        id: backgroundRect
        anchors.fill: parent
        color: "#eaf5e1"
        radius: 16
        border.width: 1
        border.color: "#d1e7c8"
    }

    Timer {
        id: leafTimer
        interval: 7000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: leafAnimation.start()
    }

    Rectangle {
        id: leaf
        width: 14
        height: 8
        radius: 4
        color: "#9bd48d"
        opacity: 0.0
        x: backgroundRect.width * 0.75
        y: -12
    }

    ParallelAnimation {
        id: leafAnimation
        running: false
        onStarted: leaf.y = -12
        SequentialAnimation {
            PropertyAnimation {
                target: leaf
                property: "opacity"
                from: 0.0
                to: 0.7
                duration: 400
            }
            PauseAnimation { duration: 200 }
            PropertyAnimation {
                target: leaf
                property: "opacity"
                to: 0.0
                duration: 400
            }
        }
        PropertyAnimation {
            target: leaf
            property: "y"
            from: -12
            to: backgroundRect.height
            duration: 2600
            easing.type: Easing.InOutQuad
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 140

            Image {
                id: plantImage
                anchors.centerIn: parent
                source: currentImageSource
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 120
                sourceSize.height: 120
                opacity: isWilted ? 0.55 : 1.0
            }

            SequentialAnimation {
                id: stageTransition
                running: false
                PropertyAnimation {
                    target: plantImage
                    property: "opacity"
                    to: 0.0
                    duration: 200
                    easing.type: Easing.InOutQuad
                }
                ScriptAction {
                    script: {
                        currentImageSource = pendingImageSource
                        plantImage.source = currentImageSource
                    }
                }
                PropertyAnimation {
                    target: plantImage
                    property: "opacity"
                    to: isWilted ? 0.55 : 1.0
                    duration: 220
                    easing.type: Easing.InOutQuad
                }
            }
        }

        Controls.Label {
            id: stageLabel
            Layout.alignment: Qt.AlignHCenter
            text: "Day " + dayCount + " – " + capitalize(stageName)
            font.pointSize: 12
            color: "#2e533d"
        }

        Controls.Button {
            id: waterButton
            text: "Water Me"
            Layout.alignment: Qt.AlignHCenter
            onClicked: plantDataSource.refresh(true)
        }
    }
}
