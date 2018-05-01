define (require) ->
    Raven = require 'raven'

    class ColorMatcher
        @serviceNodeColors: appSettings.service_node_colors

        constructor: (@selectedServices, @selectedServiceNodes, @defaultRootColor = 1400) ->

        @rgb: (r, g, b) ->
            return "rgb(#{r}, #{g}, #{b})"

        @rgba: (r, g, b, a) ->
            return "rgba(#{r}, #{g}, #{b}, #{a})"

        serviceNodeRootIdColor: (id) ->
            [r, g, b] = @getColor(id)
            @constructor.rgb(r, g, b)

        unitColor: (unit) ->
            roots = unit.get 'root_service_nodes'

            if roots is null or roots.length is 0
                Raven.captureMessage "No roots found for unit #{unit.id}",
                    tags:
                        type: 'helfi_rest_api_v4'
                roots = [@defaultRootColor]

            findRootInServiceItems = (rootIds, serviceCollection) ->
                _(rootIds).find (rootId) ->
                    serviceCollection.find (serviceItem) ->
                        serviceItem.getRoot() is rootId

            if @selectedServices?
                rootServiceNode = findRootInServiceItems roots, @selectedServices

            if not rootServiceNode and @selectedServiceNodes?
                rootServiceNode = findRootInServiceItems roots, @selectedServiceNodes

            if not rootServiceNode
                rootServiceNode = roots[0]

            [r, g, b] = @getColor(rootServiceNode)
            @constructor.rgb(r, g, b)
        getColor: (serviceNodeId) ->
            @constructor.serviceNodeColors?[serviceNodeId] or [0, 0, 0]
    return ColorMatcher
