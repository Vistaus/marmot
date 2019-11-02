import QtQuick 2.7
import QtQuick.Window 2.2
import QtQuick.Controls 2.3
import QtPositioning 5.5
import QtLocation 5.13
import QtQuick.Layouts 1.3
import QtQml 2.13
import org.kde.kirigami 2.9 as Kirigami

import HikeManager 1.0

ApplicationWindow {
    id: application

    property var currentLocation: QtPositioning.coordinate(45.187778, 5.726945) //G-Town
    property var activeTrack: null
    property var activeFile: null

    visible: true
    visibility: Window.Maximized
    width: 900
    height: 600

    Component.onCompleted: { if (Qt.application.arguments.length > 1) delayedLoading.start() }

    Timer {
        id: delayedLoading
        interval: 1
        onTriggered: { var files = Qt.application.arguments.slice(); files.shift(); open(files) }
    }

    SystemPalette {
        id: systemPalette
    }

    QtObject {
        id: colorSet
        property color window: "#31363b"
        property color text: "#eff0f1"
        property color highlight: "#3daee9"
//        property color window: systemPalette.window
//        property color text: systemPalette.windowText
//        property color highlight: systemPalette.highlight
//        property color window: "blue"
//        property color text: "red"
//        property color highlight: "green"
    }

    PositionSource {
        id: positionSource
        onSourceErrorChanged: {
            if (sourceError == PositionSource.NoError)
                return
            console.log("Source error: " + sourceError)
            stop()
        }
        onPositionChanged: {
            currentLocation = position.coordinate
            centerMap()
        }
    }

    function centerMap() {
        map.center = currentLocation
        map.zoomLevel = 10
    }

    Plugin {
        id: osmPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.providersrepository.address"; value: "qrc:/providers/" }
    }

//    Plugin {
//        id: graphhopperPlugin
//        name: "graphhopper"
//        PluginParameter { name: "graphhopper.api_key"; value: "6a9427f8-f0c9-49a3-b5d7-9a1a4ffe8cd1" }
//    }

    Plugin {
        id: orsPlugin
        name: "ors"
        PluginParameter { name: "ors.api_key"; value: "5b3ce3597851110001cf624889cac8de7d414405b9394e02dd629d89" }
    }

    RouteQuery {
        id: aQuery
        travelModes: RouteQuery.PedestrianTravel
        routeOptimizations: RouteQuery.ShortestRoute
        maneuverDetail: RouteQuery.NoManeuvers
        onWaypointsChanged: {
            if (waypoints.length < 2) // not enough waypoints to make a query, the model is not updated so we have to do it manually
                routeModel.reset()
        }
    }

    RouteModel {
        id: routeModel
        plugin: orsPlugin
        query: aQuery
        autoUpdate: true
        onModelReset: plotInfo.updateRoute()
        onStatusChanged: {
            if (status == RouteModel.Error) {
                console.log(error+": "+errorString)
            }
        }
    }

    ListModel {
        id: poiModel
        onRowsInserted: {
            for (var i = first; i < last+1; ++i)
                plotInfo.file.addPoi(QtPositioning.coordinate(get(i).latitude, get(i).longitude), get(i).name)
        }
        onRowsRemoved: {
            for (var i = last; i > first-1; --i)
                plotInfo.file.removePoi(i)
        }
    }

    GeocodeModel {
        id: poiGeocodeModel
        plugin: routeModel.plugin
        autoUpdate: true
        onStatusChanged: {
            if (status == GeocodeModel.Error) {
                console.log(error+": "+errorString)
            }
        }
        onLocationsChanged: {
            if (count == 1) {
                poiModel.append({"name": get(0).extendedAttributes.name, "latitude": query.latitude, "longitude": query.longitude})
            }
        }
    }

    ListModel {
        id: searchModel
    }

    GeocodeModel {
        id: searchGeocodeModel
        plugin: osmPlugin
        autoUpdate: true
        onStatusChanged: {
            if (status == GeocodeModel.Error) {
                console.log(error+": "+errorString)
            }
        }
        onLocationsChanged: {
            searchModel.clear()
            for (var i = 0; i<count; ++i) {
                searchModel.append({"address": get(i).address.text})
            }
        }
    }

    Map {
        id: map
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: parent.right
            left: menuButton.left
            leftMargin: -6
        }

        plugin: osmPlugin
        zoomLevel: 10
        onCopyrightLinkActivated: Qt.openUrlExternally(link)
        activeMapType: supportedMapTypes[6]

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: (routeModel.status == RouteModel.Loading)
                      || (poiGeocodeModel.status == GeocodeModel.Loading)
                         ? Qt.BusyCursor : Qt.ArrowCursor
            enabled: (routeModel.status != RouteModel.Loading) && (poiGeocodeModel.status != GeocodeModel.Loading)
            onClicked: {
                map.removeMapItem(markerDescription)
                if (plotRouteButton.checked) {
                    if (mouse.button == Qt.LeftButton) {
                        if (plotInfo.isAddingPoi) {
                            poiGeocodeModel.query = map.toCoordinate(Qt.point(mouse.x, mouse.y))
                        } else {
                            aQuery.addWaypoint(map.toCoordinate(Qt.point(mouse.x, mouse.y)))
                        }
                    } else {
                        if (plotInfo.isAddingPoi) {
                            if (poiModel.count > 0) poiModel.remove(poiModel.count-1)
                        } else {
                            if (aQuery.waypoints.length > 0) aQuery.removeWaypoint(aQuery.waypoints[aQuery.waypoints.length-1])
                        }
                    }
                }
            }
            onPressed: {
                if (editToolBar.deletingZone) {
                    map.gesture.enabled = false
                    zoneSelection.origin = Qt.point(mouse.x, mouse.y)
                    map.addMapItem(zoneSelection)
                }
            }
            onPositionChanged: {
                if (editToolBar.deletingZone) {
                    var xMin = Math.min(zoneSelection.origin.x, mouse.x)
                    var xMax = Math.max(zoneSelection.origin.x, mouse.x)
                    var yMin = Math.min(zoneSelection.origin.y, mouse.y)
                    var yMax = Math.max(zoneSelection.origin.y, mouse.y)
                    zoneSelection.topLeft = map.toCoordinate(Qt.point(xMin, yMin))
                    zoneSelection.bottomRight = map.toCoordinate(Qt.point(xMax, yMax))
                }
            }
            onReleased: {
                if (editToolBar.deletingZone) {
                    map.gesture.enabled = true
                }
            }
        }

        MapItemView {
            model: routeModel
            delegate: MapRoute {
                route: routeData
                line.color: "blue"
                line.width: 5
                smooth: true
                opacity: 0.9
                onRouteChanged: plotInfo.updateRoute()
            }
        }

        MapItemView {
            model:aQuery.waypoints
            delegate: WayPointItem {
                coordinate: modelData
                color: "blue"
            }
        }

        MapItemView {
            model: poiModel
            delegate: PoiMapItem {
                coordinate: QtPositioning.coordinate(latitude, longitude)
                text: name
            }
        }

        Instantiator {
            model: activeFile ? activeFile.tracks : null
            delegate: MapItemView {
                model: ListModel {
                    id: wpModel
                }
                Component.onCompleted: {
                    var path = modelData.path
                    for (var i = 0; i < modelData.length; ++i) {
                        model.append({"latitude": path[i].latitude, "longitude": path[i].longitude})
                    }
                }

                delegate: WayPointItem {
                    readonly property var isSelected: zoneSelection.region.contains(coordinate)
                    coordinate: QtPositioning.coordinate(latitude, longitude)
                    color: isSelected ? "black" : "red"
                    MouseArea {
                        anchors.fill: parent
                        drag.target: editToolBar.movingPoint ? parent : null
                        onReleased: if (editToolBar.movingPoint) modelData.movePoint(index, coordinate)
                        onDoubleClicked:  if (editToolBar.deletingPoint) remove()
                    }
                    Connections {
                        target: deleteShortcut
                        onActivated: if (isSelected) remove()
                    }
                    function remove() {
                        modelData.removePoint(index)
                        wpModel.remove(index)
                    }
                }
            }
            onObjectAdded: map.addMapItemView(object)
            onObjectRemoved: map.removeMapItemView(object)
        }
    }

    MapQuickItem {
        id: markerDescription
        sourceItem: DescriptionBox {
            id: markerdbox
        }
    }

    MapRectangle {
        id: zoneSelection
        property variant region: QtPositioning.rectangle(topLeft, bottomRight)
        property var origin: Qt.point(-1, -1)
    }

    EditToolBar {
        id: editToolBar
        anchors {
            bottom: parent.top
            margins: 6
            horizontalCenter: parent.horizontalCenter
        }
        state: activeFile ? "visible" : ""
        Shortcut {
            id: deleteShortcut
            sequence: StandardKey.Delete
            context: Qt.ApplicationShortcut
            onActivated: map.removeMapItem(zoneSelection)
        }
        onDeletingZoneChanged: if (!deletingZone) map.removeMapItem(zoneSelection)
    }

    onActiveFileChanged: {
        if (activeFile) {
            editToolBar.fileName = activeFile.name
        }
    }

    FilesModel {
        id: filesModel

        onFileAppened: {
            map.removeMapItem(markerDescription)
            // PolyLines
            for (var i = 0; i < file.tracks.length; ++i) {
                var polyLine = Qt.createComponent("PolyLine.qml").createObject(map, {track: file.tracks[i]})
                polyLine.objectName = file.tracks[i].objectName+"_polyline"
                map.addMapItem(polyLine)

                profileChart.createSeries(file.tracks[i])
            }
            // Points of interest
            for (var j = 0; j < file.pois.length; ++j) {
                var poi = Qt.createComponent("Marker.qml").createObject(map, {wayPoint: file.pois[j]})
                poi.objectName = file.pois[j].objectName+"_marker"
                map.addMapItem(poi)
            }
        }

        onFileRemoved: {
            map.removeMapItem(markerDescription)
            var itemsToRemove = []
            for (var i = 0; i < file.tracks.length; ++i) {
                itemsToRemove.push(file.tracks[i].objectName+"_polyline")
            }
            for (var j = 0; j < file.pois.length; ++j) {
                itemsToRemove.push(file.pois[j].objectName+"_marker")
            }
            var items = map.mapItems
            for (var k = 0; k < items.length; ++k) {
                if (itemsToRemove.includes(items[k].objectName)) {
                    items[k].destroy()
                }
            }
            file.destroy()
        }
    }

    function open(files) {
        if (files.length === 0)
            return
        for (var i = 0; i < files.length; ++i) {
            var f = Qt.createQmlObject('import HikeManager 1.0; File {}', filesModel)
            if (f.open(files[i].toString())) {
                filesModel.append(f)
            } else {
                f.destroy()
                console.log("Couldn't open "+files[i].toString())
            }
        }
        aggregateStats.update()
        map.fitViewportToVisibleMapItems()
    }

    function removeFile(index) {
        filesModel.remove(index)
        aggregateStats.update()
    }

    function closeAllFiles() {
        while (filesModel.count > 0)
            filesModel.remove(filesModel.count-1)
        aggregateStats.update()
    }

    function fitToTrack(index) {
        map.fitViewportToGeoShape(filesModel.get(index).boundingBox, 200)
    }

    SideBar {
        id: sideBar
        width: 400
        height: application.height
    }

    CustomButton {
        id: menuButton
        anchors.top: parent.top
        x: sideBar.position*sideBar.width+6
        anchors.margins: 6
        icon.name: "open-menu-symbolic"
        tooltipText: qsTr("Menu")

        onClicked: sideBar.opened ? sideBar.close() : sideBar.open()
    }

    CustomButton {
        id: plotRouteButton
        anchors.right: parent.right
        anchors.bottom: mapTypeButton.top
        anchors.margins: 6
        icon.name: "routeplanning"
        tooltipText: qsTr("Plot a route")
        checkable: true

        onClicked: plotInfo.state = plotInfo.state === "" ? "visible" : ""
    }

    RouteInfo {
        id: plotInfo
        anchors.right: plotRouteButton.left
        anchors.top: parent.bottom
        anchors.margins: 6
    }

    CustomButton {
        id: mapTypeButton
        anchors.right: parent.right
        anchors.bottom: fitToViewButton.top
        anchors.margins: 6
        text: map.activeMapType === map.supportedMapTypes[1] ? "\ud83c\udf10" : "\ud83c\udf0d"
        icon.name: "layer-visible-on"
        tooltipText: map.activeMapType === map.supportedMapTypes[1] ? qsTr("Hiking map") : qsTr("Satellite map")

        onClicked: {
            if (map.activeMapType === map.supportedMapTypes[1]) {
                map.activeMapType = map.supportedMapTypes[6]
            }
            else if (map.activeMapType === map.supportedMapTypes[6]) {
                map.activeMapType = map.supportedMapTypes[1]
            }
            else {
                console.log(map.activeMapType)
            }
        }
    }

    CustomButton {
        id: fitToViewButton
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        icon.name: "zoom-fit-selection"
        tooltipText: qsTr("Fit to view")

        onClicked: {
            if (map.mapItems.length > 0) {
                   map.fitViewportToVisibleMapItems()
            } else {
               centerMap()
            }
        }
    }

    ProfileChart {
        id: profileChart
        anchors.top: map.top
        anchors.right: map.right
        anchors.margins: 6
        width: 400
        height: 200
        visible: count > 0

        model: filesModel
    }

    AggregateStats {
        id: aggregateStats
        anchors.top: profileChart.bottom
        anchors.topMargin: 6
        anchors.right: profileChart.right
        visible: profileChart.visible
    }

    DropArea {
        property var supportedExt: ["gpx", "kml"]
        anchors.fill: parent
        onEntered: {
            for (var i = 0; i < drag.urls.length; ++i) {
                var extension = drag.urls[i].split('.').pop();
                if (supportedExt.includes(extension)) {
                    drag.accepted = true
                    return
                }
            }
            drag.accepted = false
        }

        onDropped: {
            var files = []
            for (var i = 0; i < drop.urls.length; ++i) {
                var extension = drop.urls[i].split('.').pop();
                if (supportedExt.includes(extension)) {
                    files.push(drop.urls[i])
                }
            }
            open(files)
        }
    }
}
