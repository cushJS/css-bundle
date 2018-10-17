{ErrorTracer, uhoh} = require 'cush/utils'
snipSyntaxError = require 'cush/utils/snipSyntaxError'
MagicString = require '@cush/magic-string'
isObject = require 'is-object'
sorcery = require '@cush/sorcery'
Bundle = require 'cush/lib/Bundle'

class CSSBundle extends Bundle
  @id: 'css'
  @exts: ['.css']
  @plugins: ['postcss']

  _wrapSourceMapURL: (url) ->
    "/*# sourceMappingURL=#{url} */"

  _concat: ->
    bundle = new MagicString.Bundle

    files = {}   # asset lookup by filename
    assets = []  # sparse asset map for deduping

    addAsset = (asset) =>
      return if assets[asset.id]
      assets[asset.id] = asset

      if asset.ext isnt '.css'
        uhoh 'Unsupported asset type: ' + asset.path(), 'BAD_ASSET'

      filename = @relative asset.path()
      files[filename] = asset

      code = new MagicString asset.content
      code.prepend "\n/* #{filename} */\n" if @dev
      code.trimEnd()

      # strip any `@import` statements
      asset.deps?.forEach (dep) ->
        code.remove dep.start, dep.end
        addAsset dep.asset

      bundle.addSource {filename, content: code}

    addAsset @main
    chain = [
      content: bundle.toString()
      map: bundle.generateMap
        includeContent: false
    ]

    if event = @_events.bundle
      try for hook in event.hooks
        result = await hook chain[0].content, this
        if isObject result?.map
          chain.unshift result

      catch err
        if err.line? then do ->
          opts = readFile: (filename) -> files[filename].content
          ErrorTracer(chain, opts)(err)
          err.snippet = snipSyntaxError chain[0].content, err
        throw err

    content: chain[0].content
    map: sorcery chain,
      getMap: (filename) -> files[filename].map or false
      includeContent: false

module.exports = CSSBundle
