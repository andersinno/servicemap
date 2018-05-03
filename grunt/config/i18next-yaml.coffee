module.exports = (grunt, options) ->
  return {
    fi:
      src: ['locales/app.yaml', 'locales/*.yaml']
      dest: '<%= build %>/locales/fi.json'
      options:
        language: 'fi'
    sv:
      src: ['locales/app.yaml', 'locales/*.yaml']
      dest: '<%= build %>/locales/sv.json'
      options:
        language: 'sv'
    en:
      src: ['locales/app.yaml', 'locales/*.yaml']
      dest: '<%= build %>/locales/en.json'
      options:
        language: 'en'
  }
