processName = (name) ->
    return name.replace('.jade', '').replace('views/template_overrides', 'views/templates');

module.exports = (grunt, options) ->
  return {
    options:
      client: true
    dev:
      files: [{
          dest: '<%= build %>/js/templates.js'
          src: ['views/templates/**/*.jade', 'views/template_overrides/**/*.jade']
      }]
      options:
        data:
          debug: true
        processName: processName
    dist:
      files: [{
          dest: '<%= build %>/js/templates.js'
          src: ['views/templates/**/*.jade', 'views/template_overrides/**/*.jade']
      }]
      options:
        data:
          debug: false
      processName: processName
  }
