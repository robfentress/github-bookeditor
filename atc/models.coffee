# # Backbone Models
# This module contains backbone models used throughout the application
define ['exports', 'jquery', 'backbone', 'i18n!atc/nls/strings'], (exports, jQuery, Backbone, __) ->

  # ## Custom Media Types Plugin
  #
  # Several languages translate to HTML (Markdown, ASCIIDoc, cnxml).
  #
  # Developers can extend the types used by registering to handle different mime-types.
  # Making an extension requires the following:
  #
  # - `parse()` and `serialize()` functions for
  #     reading in the file and writing it to HTML
  # - An Edit View for editing the content
  #
  # Entries in here contain a mapping from mime-type to a `Backbone.Model` constructor
  # Different plugins (Markdown, ASCIIDoc, cnxml) can add themselves to this
  MediaTypes = Backbone.Collection.extend
    # Just a glorified JSON holder
    model: Backbone.Model.extend
      sync: -> throw 'This model cannot be syncd'
    sync: -> throw 'This model cannot be syncd'

  # This is exported at the end of the module
  MEDIA_TYPES = new MediaTypes()


  # Custom Models defined above are mixed in using `BaseContent.initialize`
  BaseContent = Backbone.Model.extend
    initialize: ->
      mediaType = @get 'mediaType'
      throw 'BUG: No mediaType set' if not mediaType
      throw 'BUG: No mediaType not registered' if not MEDIA_TYPES.get mediaType

      # Mixin the subclasses fields
      mediaTypeConfig = MEDIA_TYPES.get mediaType
      proto = mediaTypeConfig.get('constructor').prototype
      for key, value of proto
        @[key] = value

      # Call the mixed-in constructor
      proto.initialize.apply(this, arguments)

  # ## All Content
  #
  # To prevent multiple copies of a model from floating around a single
  # copy of all referenced content (loaded or not) is kept in this Collection
  #
  # This should be read-only by others
  # New content models should be created by calling `ALL_CONTENT.add {}`
  AllContent = Backbone.Collection.extend
    model: BaseContent

  ALL_CONTENT = new AllContent()


  # ## Promises
  # A model representing a piece of content may have been instantiated
  # (ie an entry as a result of a search) but not fetched yet.
  #
  # When dealing with a model (except for `id`, `title`, or `mediaType`)
  # be sure to call `.loaded().then(cb)` first.
  #
  # Once the model is loaded (fetched) call the callbacks.

  loaded = (flag=false) ->
    if flag
      deferred = jQuery.Deferred()
      deferred.resolve @
      @_promise = deferred.promise()

    @_promise = @fetch() if not @_promise or 'rejected' == @_promise.state()
    return @_promise

  Deferrable = Backbone.Model.extend
    loaded: () -> loaded.apply(@, arguments)

  DeferrableCollection = Backbone.Collection.extend
    loaded: () -> loaded.apply(@, arguments)

    # From `Backbone.Collection._prepareModel` version 0.9.10
    #
    # Prepare a model or hash of attributes to be added to this collection.
    _prepareModel: (attrs, options) ->
      if attrs instanceof Backbone.Model
        # Get back the model in ALL_CONTENT
        ALL_CONTENT.add attrs
        attrs = ALL_CONTENT.get attrs

        attrs.collection = this if not attrs.collection
        return attrs

      options || (options = {})
      options.collection = @

      # Here is where we differ. Create the model using `MEDIA_TYPES`
      # and ensure it is added to `ALL_CONTENT`
      ALL_CONTENT.add attrs
      model = ALL_CONTENT.get attrs
      return model



  # When searching for text, perform a local filter on content while we wait
  # for the server to respond.
  #
  # This Collection takes another Collection and maintains an active filter on it.
  exports.FilteredCollection = Backbone.Collection.extend
    defaults:
      collection: null
    setFilter: (str) ->
      return if @filterStr == str
      @filterStr = str

      # Remove anything that no longer matches
      models = (@collection.filter (model) => @isMatch(model))
      @reset models

    isMatch: (model) ->
      return true if not @filterStr
      title = model.get('title') or ''
      title.toLowerCase().search(@filterStr.toLowerCase()) >= 0

    initialize: (models, options) ->
      @filterStr = options.filterStr or ''
      @collection = options.collection
      throw 'BUG: Cannot filter on a non-existent collection' if not @collection

      @add (@collection.filter (model) => @isMatch(model))

      @collection.on 'add', (model) =>
        @add model if @isMatch(model)

      @collection.on 'remove', (model) => @remove model

      @collection.on 'change', (model) =>
        if @isMatch(model)
          @add model
        else
          @remove model



  # The `Content` model contains the following members:
  #
  # * `title` - an HTML title of the content
  # * `language` - the main language (eg `en-us`)
  # * `subjects` - an array of strings (eg `['Mathematics', 'Business']`)
  # * `keywords` - an array of keywords (eg `['constant', 'boltzmann constant']`)
  # * `authors` - an `Collection` of `User`s that are attributed as authors
  Content = Deferrable.extend
    defaults:
      title: __('Untitled')
      subjects: []
      keywords: []
      authors: []
      copyrightHolders: []
      # Default language for new content is the browser's language
      language: (navigator?.userLanguage or navigator?.language or 'en').toLowerCase()

    # Perform some validation before saving
    validate: (attrs) ->
      isEmpty = (str) -> str and not str.trim().length
      return 'ERROR_EMPTY_BODY' if isEmpty(attrs.body)
      return 'ERROR_EMPTY_TITLE' if isEmpty(attrs.title)
      return 'ERROR_UNTITLED_TITLE' if attrs.title == __('Untitled')


  # Represents a "collection" in [Connexions](http://cnx.org) terminology and an `.opf` file in an EPUB
  Book = Deferrable.extend
    defaults:
      manifest: null
      navTree: null
    # Subclasses can provide a better Collection for storing Content items in a book
    # so the book can listen to changes.
    manifestType: Backbone.Collection

    # Takes an element representing a `<nav epub:type="toc"/>` element
    # and returns a JSON tree with the following structure:
    #
    #     [
    #       {id: 'path/to/file1.html', title: 'Appendix', children: [...] },
    #       {title: 'Unit 3', class: 'unit', children: [...] }
    #     ]
    # See [The toc nav Element](http://idpf.org/epub/30/spec/epub30-contentdocs.html#sec-xhtml-nav-def-types-toc) for more information.
    #
    # This method is also used by the DnD edit view.
    #
    # Example from an ePUB3:
    #
    #     <nav epub:type="toc">
    #       <ol>
    #         <li><a href="path/to/file1.html">Appendix</a></li>
    #         <li class="unit"><span>Unit 3</span><ol>[...]</ol></li>
    #       </ol>
    #     </nav>
    #
    # Example from the Drag-and-Drop Book editor (Tree View):
    #
    #     <div>
    #       <ol>
    #         <li><span data-id="path/to/file1.html">Appendix</a></li>
    #         <li class="unit"><span>Unit 3</span><ol>[...]</ol></li>
    #       </ol>
    #     </nav>
    parseNavTree: (li) ->
      $li = jQuery(li)

      $a = $li.children 'a, span'
      $ol = $li.children 'ol'

      obj = {id: $a.attr('href') or $a.data('id'), title: $a.text()}

      # The custom class is either set on the `$span` (if parsing from the editor) or on the `$a` (if parsing from an EPUB)
      obj.class = $a.data('class') or $a.not('span').attr('class')

      obj.children = (@parseNavTree(li) for li in $ol.children()) if $ol[0]
      return obj

    # Creates a Manifest collection of all content it should listen to.
    #
    # For example, changes to `id` or `title` of a piece of content will update the navigation tree.
    #
    # Similarly, an update to the navigation tree will create new models.
    initialize: ->
      @manifest = new @manifestType()
      @manifest.on 'change:title', (model, newValue, oldValue) =>
        navTree = @getNavTree()
        # Find the node that has an `id` to this model
        recFind = (nodes) ->
          for node in nodes
            return node if model.id == node.id
            return recFind node.children if node.children
        node = recFind(navTree)
        throw 'BUG: There is an entry in the tree but no corresponding model in the manifest' if not node
        node.title = newValue
        @set 'navTree', navTree

      @on 'change:navTree', (model, navTree) =>
        # **TODO:** Remove manifest entries if they are not referred to by the navTree or any modules in the book.
        recAdd = (nodes) =>
          for node in nodes
            if node.id
              contentModel = @_addToManifest {id: node.id, title: node.title, mediaType: 'text/x-module'}
            recAdd node.children if node.children
        recAdd(navTree) if navTree

      @trigger 'change:navTree', @, @getNavTree()

    _addToManifest: (config) ->
      ALL_CONTENT.add config
      model = ALL_CONTENT.get config.id
      @manifest.add model
      return model


    # **FIXME:** Somewhat hacky way of creating a new piece of content
    prependNewContent: (config) ->
      uuid = b = (a) ->
        (if a then (a ^ Math.random() * 16 >> a / 4).toString(16) else ([1e7] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, b))
      config.id = uuid() if not config.id

      # Create the model from a config and add it to the manifest
      newContent = @_addToManifest config
      # HACK: Since it is new content there is nothing to load but we already set an `id`
      console.warn 'FIXME: Hack for new content'
      newContent.loaded(true)

      navTree = @getNavTree()
      navTree.unshift {id: config.id, title: config.title}
      @set 'navTree', navTree


    # Since the nav tree is just a plain JSON object and changes to it will not trigger model changes
    # return a deep clone of the tree before making a change to it.
    #
    # **FIXME:** This should be implemented using a Tree-Like Collection that has a `.toJSON()` and methods like `.insertBefore()`
    getNavTree: (tree) ->
      navTree = @get('navTree') or []
      return JSON.parse JSON.stringify(navTree)

  SearchResults = DeferrableCollection.extend
    defaults:
      parameters: []

  # Add the 2 basic Media Types already defined above
  MEDIA_TYPES.add
    id: 'text/x-module'
    constructor: Content

  MEDIA_TYPES.add
    id: 'text/x-collection'
    constructor: Book

  # Finally, export only the pieces needed
  exports.Book = Book
  exports.Deferrable = Deferrable
  exports.DeferrableCollection = DeferrableCollection
  exports.ALL_CONTENT = ALL_CONTENT
  exports.MEDIA_TYPES = MEDIA_TYPES
  exports.SearchResults = SearchResults
  return exports