define "app/map", ['leaflet', 'proj4leaflet', 'backbone', 'backbone.marionette', 'leaflet.markercluster', 'leaflet.activearea', 'i18next', 'app/widgets', 'app/models', 'app/p13n', 'app/jade'], (leaflet, p4j, Backbone, Marionette, markercluster, leaflet_activearea, i18n, widgets, models, p13n, jade) ->
    ICON_SIZE = 40
    if get_ie_version() and get_ie_version() < 9
        ICON_SIZE *= .8
    MARKER_POINT_VARIANT = false
    DEFAULT_CENTER = [60.171944, 24.941389] # todo: depends on city

    class MapView extends Backbone.Marionette.View
        tagName: 'div'
        initialize: (opts) ->
            @markers = {}
            @units = opts.units
            @is_retina = window.devicePixelRatio > 1
            @user_click_coordinate_position = opts.user_click_coordinate_position
            @selected_services = opts.services
            @search_results = opts.search_results
            @selected_units = opts.selected_units
            #@listenTo @units, 'add', @draw_units
            @selected_position = opts.selected_position
            @user_position_markers =
                accuracy: null
                position: null
                clicked: null

            @listenTo @units, 'finished', =>
                # Triggered when all of the
                # pages of units have been fetched.
                @draw_units @units

            @listenTo @user_click_coordinate_position, 'change:value', (model, current) =>
                previous = model.previous?.value?()
                if previous?
                    @stopListening previous
                @map.off 'click'
                $('#map').css 'cursor', 'auto'
                @listenTo current, 'request', =>
                    $('#map').css 'cursor', 'crosshair'
                @map.on 'click', (e) =>
                    $('#map').css 'cursor', 'auto'
                    current.set 'location',
                        coordinates: [e.latlng.lng, e.latlng.lat]
                        accuracy: 0
                        type: 'Point'
                    current.set 'name', null
                    @handle_position current

            @listenTo @units, 'unit:highlight', @highlight_unselected_unit
            @listenTo @units, 'batch-remove', @remove_units
            @listenTo @units, 'remove', @remove_unit
            @listenTo @units, 'reset', @render_units
            @listenTo @selected_units, 'reset', @handle_selected_unit
            @listenTo p13n, 'position', @handle_position
            @listenTo @selected_position, 'change:value', =>
                if @selected_position.isSet()
                    @handle_position @selected_position.value(), center=true
            MapView.set_map_active_area_max_height
                maximize:
                    @selected_position.isEmpty() and @selected_units.isEmpty()
            $(window).resize => _.defer(_.bind(@recenter, @))

        lat_lng_from_geojson: (object) =>
            object?.get('location')?.coordinates?.slice(0).reverse()

        render_units: (coll, opts) =>
            if @units.isEmpty() then @clear_popups(true)
            unless opts?.retain_markers then @all_markers.clearLayers()
            markers = {}
            if @selected_units.isSet()
                marker = @markers[@selected_units.first().get('id')]
                if marker? then @markers = {id: marker}
            @units.each (unit) => @draw_unit(unit)
            if @selected_units.isSet()
                @highlight_selected_unit @selected_units.first()
            if not opts?.no_refit and not @units.isEmpty() and @search_results.isSet()
                @refit_bounds()
            if @units.isEmpty() and opts?.bbox
                @show_all_units_at_high_zoom()

        handle_selected_unit: (units, options) ->
            @clear_popups(true)
            if units.isEmpty()
                MapView.set_map_active_area_max_height maximize: true
                return
            unit = units.first()
            _.defer => @highlight_selected_unit unit
            _.defer _.bind(@recenter, @)

        get_max_auto_zoom: ->
            layer = p13n.get('map_background_layer')
            if layer == 'guidemap'
                7
            else if layer == 'ortographic'
                9
            else
                12
        get_zoomlevel_to_show_all_markers: ->
            layer = p13n.get('map_background_layer')
            if layer == 'guidemap'
                return 8
            else if layer == 'ortographic'
                return 8
            else
                return 14

        create_position_marker: (lat_lng, accuracy, type) ->
                #@map.addLayer accuracy_marker
                Z_INDEX = -1000
                switch type
                    when 'detected'
                        opts =
                            icon: L.divIcon
                                iconSize: L.point 40, 40
                                iconAnchor: L.point 20, 39
                                className: 'servicemap-div-icon'
                                html: '<span class="icon-icon-you-are-here"></span'
                            zIndexOffset: Z_INDEX
                        marker = L.marker lat_lng, opts
                    when 'clicked'
                        marker = L.circleMarker lat_lng,
                            color: '#666'
                            weight: 2
                            opacity: 1
                            fill: false
                            clickable: false
                            zIndexOffset: Z_INDEX
                        marker.setRadius 6
                    when 'address'
                        opts =
                            zIndexOffset: Z_INDEX
                            icon: L.divIcon
                                iconSize: L.point 40, 40
                                iconAnchor: L.point 20, 39
                                className: 'servicemap-div-icon'
                                html: '<span class="icon-icon-address"></span'
                        marker = L.marker lat_lng, opts
                return marker

        handle_position: (position_object, center=false, opts) ->
            # TODO: clean up this method
            unless position_object?
                for key in ['clicked', 'address']
                    layer = @user_position_markers[key]
                    if layer then @map.removeLayer layer

            is_selected = position_object == @selected_position.value()

            key = position_object?.origin()
            if key != 'detected'
                @info_popups.clearLayers()

            prev = @user_position_markers[key]
            if prev then @map.removeLayer prev

            if (key == 'address') and @user_position_markers.clicked?
                @map.removeLayer @user_position_markers.clicked
            if (key == 'clicked') and is_selected and @user_position_markers.address?
                @map.removeLayer @user_position_markers.address

            location = position_object?.get 'location'
            unless location then return

            accuracy = location.accuracy
            lat_lng = @lat_lng_from_geojson(position_object)
            accuracy_marker = L.circle lat_lng, accuracy, weight: 0

            marker = @create_position_marker lat_lng, accuracy, position_object.origin()
            marker.position = position_object
            marker.on 'click', =>
                unless position_object == @selected_position.value()
                    app.commands.execute 'selectPosition', position_object
            marker.addTo @map

            @user_position_markers[key] = marker

            if is_selected
                @info_popups.clearLayers()

            popup = @create_position_popup position_object, marker


            if @selected_units.isEmpty() and (
                @selected_position.isEmpty() or
                @selected_position.value() == position_object or
                not position_object?.is_detected_location())

                @info_popups.addLayer popup


            position_object.popup = popup

            if not opts?.skip_refit and (is_selected or center)
                if @map.getZoom() != @get_zoomlevel_to_show_all_markers()
                    @map.setView lat_lng, @get_zoomlevel_to_show_all_markers(),
                        animate: true
                else
                    @map.panTo lat_lng

        render: ->
            @$el.attr 'id', 'map'
        width: ->
            @$el.width()
        height: ->
            @$el.height()
        to_coordinates: (windowCoordinates) ->
            @map.layerPointToLatLng(@map.containerPointToLayerPoint(windowCoordinates))

        clear_popups: (clear_selected) ->
            @popups.eachLayer (layer) =>
                if clear_selected
                    layer.selected = false
                    @popups.removeLayer layer
                else unless layer.selected
                    @popups.removeLayer layer

        remove_units: (options) ->
            @all_markers.clearLayers()
            @markers = {}
            @draw_units @units
            unless @selected_units.isEmpty()
                @highlight_selected_unit @selected_units.first()
            if @units.isEmpty()
                @show_all_units_at_high_zoom()

        remove_unit: (unit, units, options) ->
            if unit.marker?
                @all_markers.removeLayer unit.marker
                delete unit.marker

        create_icon: (unit, services) ->
            color = app.color_matcher.unit_color(unit) or 'rgb(255, 255, 255)'
            if MARKER_POINT_VARIANT
                ctor = widgets.PointCanvasIcon
            else
                ctor = widgets.PlantCanvasIcon
            new ctor ICON_SIZE, color, unit.id

        create_cluster_icon: (cluster) ->
            count = cluster.getChildCount()
            service_collection = new models.ServiceList()
            markers = cluster.getAllChildMarkers()
            _.each markers, (marker) =>
                unless marker.unit?
                    return
                if @selected_services.isEmpty()
                    service = new models.Service
                        id: marker.unit.get('root_services')[0]
                        root: marker.unit.get('root_services')[0]
                else
                    service = @selected_services.find (s) =>
                        s.get('root') in marker.unit.get('root_services')
                service_collection.add service

            colors = service_collection.map (service) =>
                app.color_matcher.service_color(service)

            if MARKER_POINT_VARIANT
                ctor = widgets.PointCanvasClusterIcon
            else
                ctor = widgets.CanvasClusterIcon
            new ctor count, ICON_SIZE, colors, service_collection.first().id

        create_popup: (offset) ->
            opts =
                closeButton: false
                autoPan: false
                zoomAnimation: false
                minWidth: 500
                className: 'unit'
            if offset? then opts.offset = offset
            new widgets.LeftAlignedPopup opts

        create_position_popup: (position_object, marker) ->
            lat_lng = @lat_lng_from_geojson(position_object)
            name = position_object.get('name') or i18n.t('map.retrieving_address')
            if position_object == @selected_position.value()
                popup_contents =
                    (ctx) =>
                        "<div class=\"unit-name\">#{ctx.name}</div>"
                offset_y = switch position_object.origin()
                    when 'detected' then 10
                    when 'address' then 10
                    else 38
                popup = @create_popup L.point(0, offset_y)
                    .setContent popup_contents
                        name: name
                    .setLatLng lat_lng
            else
                popup_contents =
                    (ctx) =>
                        ctx.detected = position_object?.is_detected_location()
                        $popup_el = $ jade.template 'position-popup', ctx
                        $popup_el.on 'click', (e) =>
                            @info_popups.clearLayers()
                            unless position_object == @selected_position.value()
                                e.stopPropagation()
                                @map.removeLayer position_object.popup
                                app.commands.execute 'selectPosition', position_object
                                marker.closePopup()
                        $popup_el[0]
                offset_y = switch position_object.origin()
                    when 'detected' then -53
                    when 'clicked' then -15
                    when 'address' then -50
                offset = L.point 0, offset_y
                popup_opts =
                    closeButton: false
                    className: 'position'
                    autoPan: false
                    offset: offset
                    autoPanPaddingTopLeft: L.point 30, 80
                    autoPanPaddingBottomRight: L.point 30, 80
                popup = L.popup(popup_opts)
                    .setLatLng lat_lng
                    .setContent popup_contents
                        name: name

            pos_list = models.PositionList.from_position position_object
            @listenTo pos_list, 'sync', =>
                best_match = pos_list.first()
                if best_match.get('distance') > 500
                    best_match.set 'name', i18n.t 'map.unknown_address'
                position_object.set best_match.toJSON()
                popup.setContent popup_contents
                    name: best_match.get 'name'
                position_object.trigger 'reverse_geocode'

            popup

        create_marker: (unit) ->
            id = unit.get 'id'
            if id of @markers
                return @markers[id]
            html_content = "<div class='unit-name'>#{unit.get_text 'name'}</div>"
            popup = @create_popup().setContent html_content
            icon = @create_icon unit, @selected_services
            marker = L.marker @lat_lng_from_geojson(unit),
                icon: icon
                zIndexOffset: 100
            marker.unit = unit
            unit.marker = marker
            @listenTo marker, 'click', @select_marker

            marker.bindPopup(popup)
            @markers[id] = marker

        highlight_selected_unit: (unit) ->
            # Prominently highlight the marker whose details are being
            # examined by the user.
            marker = unit.marker
            @clear_popups(true)
            popup = marker?.getPopup()
            unless popup
                return
            popup.selected = true
            popup.setLatLng marker.getLatLng()
            @popups.addLayer popup
            $(marker?._popup._wrapper).addClass 'selected'

        highlight_unselected_unit: (unit) ->
            # Transiently highlight the unit which is being moused
            # over in search results or otherwise temporarily in focus.
            marker = unit.marker
            popup = marker?.getPopup()
            if popup?.selected
                return
            @clear_popups()
            parent = @all_markers.getVisibleParent unit.marker
            if popup?
                $(marker._popup._wrapper).removeClass 'selected'
                popup.setLatLng marker?.getLatLng()
                @popups.addLayer popup

        highlight_unselected_cluster: (cluster) ->
            # Maximum number of displayed names per cluster.
            COUNT_LIMIT = 3
            @clear_popups()
            child_count = cluster.getChildCount()
            names = _.map cluster.getAllChildMarkers(), (marker) ->
                    p13n.get_translated_attr marker.unit.get('name')
                .sort()
            data = {}
            overflow_count = child_count - COUNT_LIMIT
            if overflow_count > 1
                names = names[0...COUNT_LIMIT]
                data.overflow_message = i18n.t 'general.more_units',
                    count: overflow_count
            data.names = names
            popuphtml = jade.get_template('popup_cluster') data
            popup = @create_popup()
            popup.setLatLng cluster.getBounds().getCenter()
            popup.setContent popuphtml
            @map.on 'zoomstart', =>
                @popups.removeLayer popup
            @popups.addLayer popup

        select_marker: (event) ->
            marker = event.target
            unit = marker.unit
            app.commands.execute 'selectUnit', unit

        draw_units: (units) ->
            @all_markers.clearLayers()
            @markers = {}
            units_with_location = units.filter (unit) => unit.get('location')?
            markers = units_with_location.map (unit) => @create_marker(unit)
            @all_markers.addLayers markers

        draw_unit: (unit, units, options) ->
            location = unit.get('location')
            if location?
                marker = @create_marker unit
                @all_markers.addLayer marker

        make_tm35_layer: (url) ->
            crs_name = 'EPSG:3067'
            proj_def = '+proj=utm +zone=35 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs'

            bounds = L.bounds L.point(-548576, 6291456), L.point(1548576, 8388608)
            origin_nw = [bounds.min.x, bounds.max.y]
            crs_opts =
                resolutions: [8192, 4096, 2048, 1024, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1, 0.5, 0.25]
                bounds: bounds
                transformation: new L.Transformation 1, -origin_nw[0], -1, origin_nw[1]

            @crs = new L.Proj.CRS crs_name, proj_def, crs_opts

            opts =
                maxZoom: 15
                minZoom: 6
                continuousWorld: true
                tms: false

            map_layer = new L.TileLayer url, opts

            return map_layer

        make_gk25_layer: (layer_name) ->
            crs_name = 'EPSG:3879'
            proj_def = '+proj=tmerc +lat_0=0 +lon_0=25 +k=1 +x_0=25500000 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs'

            bounds = [25440000, 6630000, 25571072, 6761072]
            @crs = new L.Proj.CRS.TMS crs_name, proj_def, bounds,
                resolutions: [256, 128, 64, 32, 16, 8, 4, 2, 1, 0.5, 0.25, 0.125, 0.0625]

            geoserver_url = (layer_name, layer_fmt) ->
                "http://geoserver.hel.fi/geoserver/gwc/service/tms/1.0.0/#{layer_name}@ETRS-GK25@#{layer_fmt}/{z}/{x}/{y}.#{layer_fmt}"

            if layer_name == 'ortographic'
                map_layer = new L.Proj.TileLayer.TMS geoserver_url("hel:orto2014", "jpg"), @crs,
                    maxZoom: 12
                    minZoom: 2
                    continuousWorld: true
                    tms: false

            else
                guide_map_url = geoserver_url("hel:Karttasarja", "gif")
                guide_map_options =
                    maxZoom: 12
                    minZoom: 2
                    continuousWorld: true
                    tms: false

                map_layer = new L.Proj.TileLayer.TMS guide_map_url, @crs, guide_map_options
                map_layer.setOpacity 0.8

            return map_layer

        make_background_layer: ->
            if p13n.get('map_background_layer') in ['guidemap', 'ortographic']
                return @make_gk25_layer p13n.get('map_background_layer')
            if p13n.get_accessibility_mode 'colour_blind'
                url = "http://144.76.78.72/mapproxy/wmts/osm-toner/etrs_tm35fin/{z}/{x}/{y}.png"
            else
                if @is_retina
                    if p13n.get_language() == 'sv'
                        url = "http://144.76.78.72/mapproxy/wmts/osm-sm-sv-hq/etrs_tm35fin_hq/{z}/{x}/{y}.png"
                    else
                        url = "http://144.76.78.72/mapproxy/wmts/osm-sm-hq/etrs_tm35fin_hq/{z}/{x}/{y}.png"
                else
                    if p13n.get_language() == 'sv'
                        url = "http://144.76.78.72/mapproxy/wmts/osm-sm-sv/etrs_tm35fin/{z}/{x}/{y}.png"
                    else
                        url = "http://144.76.78.72/mapproxy/wmts/osm-sm/etrs_tm35fin/{z}/{x}/{y}.png"

            return @make_tm35_layer url

        calculate_initial_options: ->
            if @selected_position.isSet()
                zoom: @get_zoomlevel_to_show_all_markers()
                center: @lat_lng_from_geojson @selected_position.value()
            else if @selected_units.isSet()
                zoom: @get_max_auto_zoom()
                center: @lat_lng_from_geojson @selected_units.first()
            else
                # Default state without selections
                zoom: if (p13n.get('map_background_layer') == 'servicemap') then 10 else 5
                center: DEFAULT_CENTER

        get_centered_view: ->
            if @selected_position.isSet()
                center: @lat_lng_from_geojson @selected_position.value()
                zoom: @get_zoomlevel_to_show_all_markers()
            else if @selected_units.isSet()
                center: @lat_lng_from_geojson @selected_units.first()
                zoom: Math.max @get_max_auto_zoom(), @map.getZoom()
            else
                null

        draw_initial_state: =>
            if @selected_position.isSet()
                @show_all_units_at_high_zoom()
                @handle_position @selected_position.value(), center=false, skip_refit: true
            else if @selected_units.isSet()
                @render_units @units, no_refit: true
            else if @units.isSet()
                @render_units @units
        get_max_bounds: (layer) ->
            if layer == 'ortographic'
                L.latLngBounds L.latLng(60.11322159453442, 24.839029712845157),
                    L.latLng(60.30146342058585, 25.23664312801843)
            else
                L.latLngBounds L.latLng(60, 24.2), L.latLng(60.5, 25.5)

        create_map: ->
            @background_layer = @make_background_layer()
            options =
                crs: @crs
                continuusWorld: true
                worldCopyJump: false
                zoomControl: false
                closePopupOnClick: false
                maxBounds: @get_max_bounds p13n.get('map_background_layer')
                layers: [@background_layer]

            map = L.map(@$el.get(0), options).setActiveArea 'active-area'
            MapView.set_map_active_area_max_height
                maximize: @selected_units.isEmpty() and @selected_position.isEmpty()
            opts = @calculate_initial_options()
            map.setView opts.center, opts.zoom

            window.debug_map = map
            @listenTo p13n, 'change', @handle_p13n_change
            map

        reset_map: ->
            # With different projections the base layers cannot
            # be changed on a live map.
            window.location.reload true

        handle_p13n_change: (path, new_val) ->
            if path[0] == 'map_background_layer'
                @reset_map()
            if path[0] != 'accessibility' or path[1] != 'colour_blind'
                return

            map_layer = @make_background_layer()
            @map.addLayer map_layer
            @map.removeLayer @background_layer
            @background_layer = map_layer

        overlapping_bounding_boxes: (latLngBounds) ->
            METER_GRID = 1000
            DEBUG_GRID = false
            ne = @crs.project latLngBounds.getNorthEast()
            sw = @crs.project latLngBounds.getSouthWest()
            min = x: ne.x, y: sw.y
            max = y: ne.y, x: sw.x

            snap_to_grid = (coord) ->
                parseInt(coord / METER_GRID) * METER_GRID
            coordinates = {}
            for dim in ['x', 'y']
                coordinates[dim] = coordinates[dim] or {}
                for value in [min[dim] .. max[dim]]
                    coordinates[dim][parseInt(snap_to_grid(value))] = true

            pairs = _.flatten(
                [parseInt(x), parseInt(y)] for x in _.keys(coordinates.x) for y in _.keys(coordinates.y),
                true)

            bboxes = _.map pairs, ([x, y]) -> [[x, y], [x + METER_GRID, y + METER_GRID]]
            if DEBUG_GRID
                @debug_grid.clearLayers()
                for bbox in bboxes
                    sw = @crs.projection.unproject(L.point(bbox[0]...))
                    ne = @crs.projection.unproject(L.point(bbox[1]...))
                    sws = [sw.lat, sw.lng].join()
                    nes = [ne.lat, ne.lng].join()
                    unless @debug_circles[sws]
                        @debug_grid.addLayer L.circle(sw, 10)
                        @debug_circles[sws] = true
                    unless @debug_circles[nes]
                        @debug_grid.addLayer L.circle(ne, 10)
                        @debug_circles[nes] = true
                    # rect = L.rectangle([sw, ne])
                    # @debug_grid.addLayer rect
            bboxes

        show_all_units_at_high_zoom: ->
            if $(window).innerWidth() <= app_settings.mobile_ui_breakpoint
                return
            zoom = @map.getZoom()
            if zoom >= @get_zoomlevel_to_show_all_markers()
                if (@selected_units.isSet() and @map.getBounds().contains(@selected_units.first().marker.getLatLng()))
                    # Don't flood a selected unit's surroundings
                    return
                if @selected_services.isSet()
                    return
                if @search_results.isSet()
                    return
                transformed_bounds = @overlapping_bounding_boxes @map._original_getBounds()
                bboxes = []
                for bbox in transformed_bounds
                    bboxes.push "#{bbox[0][0]},#{bbox[0][1]},#{bbox[1][0]},#{bbox[1][1]}"
                app.commands.execute 'addUnitsWithinBoundingBoxes', bboxes
            else
                app.commands.execute 'clearUnits', all: false, bbox: true

        onShow: ->
            # The map is created only after the element is added
            # to the DOM to work around Leaflet init issues.
            @map = @create_map()
            # The line below is for debugging without clusters.
            # @all_markers = L.featureGroup()
            @all_markers = new L.MarkerClusterGroup
                showCoverageOnHover: false
                maxClusterRadius: (zoom) =>
                    return if (zoom >= @get_zoomlevel_to_show_all_markers()) then 4 else 30
                iconCreateFunction: (cluster) =>
                    @create_cluster_icon(cluster)
            @_add_mouseover_listeners @all_markers
            @popups = L.layerGroup()
            @info_popups = L.layerGroup()

            L.control.scale(imperial: false).addTo(@map);

            L.control.zoom(
                position: 'bottomright'
                zoomInText: '<span class="icon-icon-zoom-in"></span>'
                zoomOutText: '<span class="icon-icon-zoom-out"></span>').addTo @map
            @all_markers.addTo @map
            @popups.addTo @map
            @info_popups.addTo @map

            @debug_grid = L.layerGroup().addTo(@map)
            @debug_circles = {}

            @map.on 'moveend', =>
                # TODO: cleaner way to prevent firing from refit
                if @skip_moveend
                    @skip_moveend = false
                    return
                @show_all_units_at_high_zoom()

            # If the user has allowed location requests before,
            # try to get the initial location now.
            if p13n.get_location_requested()
                p13n.request_location()

            @user_click_coordinate_position.wrap new models.CoordinatePosition
                is_detected: false

            @previous_zoomlevel = @map.getZoom()
            @draw_initial_state()

        _add_mouseover_listeners: (markerClusterGroup)->
            markerClusterGroup.on 'clustermouseover', (e) =>
                @highlight_unselected_cluster e.layer
            markerClusterGroup.on 'mouseover', (e) =>
                @highlight_unselected_unit e.layer.unit
            markerClusterGroup.on 'spiderfied', (e) =>
                icon = $(e.target._spiderfied?._icon)
                icon?.fadeTo('fast', 0)

        @map_active_area_max_height: =>
            screenWidth = $(window).innerWidth()
            screenHeight = $(window).innerHeight()
            Math.min(screenWidth * 0.4, screenHeight * 0.3)

        @set_map_active_area_max_height: (options) =>
            # Sets the height of the map shown in views that have a slice of
            # map visible on mobile.
            defaults = maximize: false
            options = options or {}
            _.extend defaults, options
            options = defaults
            if $(window).innerWidth() <= app_settings.mobile_ui_breakpoint
                height = MapView.map_active_area_max_height()
                $active_area = $ '.active-area'
                if options.maximize
                    $active_area.css 'height', 'auto'
                    $active_area.css 'bottom', 0
                else
                    $active_area.css 'height', height
                    $active_area.css 'bottom', 'auto'
            else
                $('.active-area').css 'height', 'auto'
                $('.active-area').css 'bottom', 0

        recenter: ->
            view = @get_centered_view()
            unless view?
                return
            @map.setView view.center, view.zoom, animate: false

        refit_bounds: ->
            @skip_moveend = true
            @map.fitBounds @all_markers.getBounds(),
                maxZoom: @get_max_auto_zoom()
                animate: true

    return MapView
