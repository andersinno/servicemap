define (require) ->
    # This module is a temporary solution to fetch pre-generated
    # accessibility sentences before we can access all the data allowing
    # them to be generated on demand.
    _        = require 'underscore'
    Raven    = require 'raven'
    Backbone = require 'backbone'

    models   = require 'cs!app/models'

    LANGUAGES = ['fi', 'sv', 'en']
    TIMEOUT = 10000

    currentId = 0
    ids = {}
    _generateId = (content) ->
        unless content of ids
            ids[content] = currentId
            currentId += 1
        ids[content]

    _buildHelsinkiTranslatedObject = (data, base) ->
        _.object _.map(LANGUAGES, (lang) ->
            [lang, data["#{base}_#{lang}"]])

    _buildCGIarTranslatedObject = (entries) ->
        transObject = {}
        _.each entries, (entry) ->
            transObject[entry.language] = entry.value
        transObject

    _parseHelsinki = (data) ->
        sentences = { }
        groups = { }
        console.log data
        _.each data.accessibility_sentences, (sentence) ->
            group = _buildHelsinkiTranslatedObject sentence, 'sentence_group'
            key = _generateId group.fi
            groups[key] = group
            unless key of sentences
                sentences[key] = []
            sentences[key].push _buildHelsinkiTranslatedObject(sentence, 'sentence')
        groups:
            groups
        sentences:
            sentences

    _parseCGIar = (data) ->
        sentences = { }
        groups = { }
        _.each data, (sentence) ->
            group = _buildCGIarTranslatedObject sentence.sentenceGroups
            key = _generateId group.fi
            groups[key] = group
            unless key of sentences
                sentences[key] = []
            sentences[key].push _buildCGIarTranslatedObject(sentence.sentences)
        groups:
            groups
        sentences:
            sentences

    fetchHelsinkiSentences = (unit, callback) ->
        args =
            dataType: 'json'
            url: appSettings.accessibility_backend + '/unit/' + unit.id
            jsonpCallback: 'jcbAsc'
            cache: true
            success: (data) ->
                unless data
                    data = {'accessibility_sentences': []}
                callback _parseHelsinki(data)
            timeout: TIMEOUT
            error: (jqXHR, errorType, exception) ->
                context = {
                    tags:
                        type: 'helfi_rest_api'
                    extra:
                        error_type: errorType
                        jqXHR: jqXHR
                }

                if errorType == 'timeout'
                    Raven.captureMessage(
                        'Timeout reached for unit accessibility sentences',
                        context)
                else if exception
                    Raven.captureException exception, context
                else
                    Raven.captureMessage(
                        'Unidentified error in unit accessibility sentences',
                        context)
                callback error: true
        @xhr = $.ajax args

    fetchCGIarSentences = (unit, callback) ->
        unitId = ''
        _.each unit.attributes.identifiers, (identifier) ->
            if identifier.namespace == 'ptv'
                unitId = identifier.value
                return false

        systemId = appSettings.CGIar_accessibility_system_id
        backend = appSettings.accessibility_backend

        url = backend + '/accessibility/servicepoints/' + systemId + '/' + unitId + '/sentences'
        args =
            dataType: 'json'
            contentType: 'application/json'
            url: url
            method: 'GET'
            cache: true
            success: (data) ->
                unless data
                    data = {'accessibility_sentences': []}
                callback _parseCGIar(data)
            timeout: TIMEOUT
            error: (data, textStatus, errorThrown) =>
                    context =
                        tags:
                            type: 'asiointi_rest_api'
                        extra:
                            data: data
                            error_type: textStatus
                            error_thrown: errorThrown
                    if errorThrown
                        Raven.captureException errorThrown, context
                    else
                        Raven.captureMessage(
                            'Unidentified error in unit accessibility sentences',
                            context)
        @xhr = $.ajax args

    fetch:
        if appSettings.accessibility_sentence_loader == 'CGIar'
            fetchCGIarSentences
        else
            fetchHelsinkiSentences

