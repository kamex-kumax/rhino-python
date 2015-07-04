$ = require "jquery"
shelljs = require "shelljs"
ttr = require './talk-to-rhino'
{CompositeDisposable} = require 'atom'
RhinoSettingsView = require './rhino-settings-view'
Vue = require 'vue'
remote = require 'remote'
dialog = remote.require 'dialog'
_ = require 'underscore'

module.exports =
  config:
    httpPort:
      title: 'Port Number'
      description: 'Port number that Rhino listens on for http requests.  NOTE: has to match the port number configured in Rhinoceros.'
      type: 'integer'
      default: 8080

  provider: null
  ready: false

  activate: (state) ->
    @ready = true

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.commands.add 'atom-workspace', 'rhino-python:saveAndRunInRhino': => @saveAndRunInRhino()
    @subscriptions.add atom.commands.add 'atom-workspace', 'rhino-python:saveAndRunInRhinoFromTreeView': => @saveAndRunInRhinoFromTreeView()

    @rhinoSettingsView = new RhinoSettingsView(state.rhinoSettigsViewState)
    @modalPanel = atom.workspace.addBottomPanel(item: @rhinoSettingsView.getElement(), visible: false)
    @subscriptions.add atom.commands.add 'atom-workspace', 'rhino-python:toggleRhinoSettingsView': => @toggleRhinoSettingsView()

    v = new Vue({
      el: '#RhinoSettingsView'
      methods:
        add: ->
          path_to_add = dialog.showOpenDialog({properties:['openDirectory']})
          unless path_to_add?
            return
          #fp = i.content for i in @paths when i.content == p[0]
          dup_path = _.find(@paths, (p) -> p.path == path_to_add[0])
          unless dup_path?
            len = @paths.push({path: path_to_add[0], markdelete: false, selected: false})
            @dirty = true
            @select _.last(@paths)
        delete: ->
          unless @aPathIsSelected()?
            # this should never happen
            alert 'no path is selected'
          sp = @selectedPath()
          newps = _.reject(@paths, (p) -> p.path == sp.path)
          @paths = newps
          #@paths = _.reject(@paths, (p) -> p.path == @selectedPath().path)
          @dirty = true
          @setBtnEnabled()
        save: -> alert 'save!'
        revert: -> alert 'revert!'
        select: (path) ->
          console.log 'select path', path
          _.each(_.filter(@paths, (i) -> i.selected == true), (p) -> p.selected = false)
          path.selected = true
          @setBtnEnabled()
        setBtnEnabled: ->
          @disableAllBtnsExceptAdd()
          if @aPathIsSelected()
            @deleteDisabled = false
            @showDisabled = false
            if @selectedIsNotFirst()
              @upDisabled = false
            if @selectedIsNotLast()
              @downDisabled = false
          if @dirty
            @saveDisabled = false
            @revertDisabled = false

        disableAllBtnsExceptAdd: ->
          @deleteDisabled = true
          @upDisabled = true
          @downDisabled = true
          @showDisabled = true
          @saveDisabled = true
          @revertDisabled = true

        aPathIsSelected: ->
          _.any(@paths, (p) -> p.selected)

        selectedPath: ->
          _.find(@paths, (p) -> p.selected)

        selectedIsNotFirst: ->
          @aPathIsSelected() and @selectedPath().path != _.first(@paths).path

        selectedIsNotLast: ->
          @aPathIsSelected() and @selectedPath().path != _.last(@paths).path
      data:
        dirty: false
        deleteDisabled: true
        upDisabled: true
        downDisabled: true
        showDisabled: true
        saveDisabled: true
        revertDisabled: true
        paths: [
          {
            path: '/mypath',
            markdelete: false,
            selected: false
          },
          {
            path: '/myotherpath',
            markdelete: false,
            selected: false
          }
        ]
    })

  toggleRhinoSettingsView: ->
    if @modalPanel.isVisible()
      @modalPanel.hide()
    else
      @modalPanel.show()

  deactivate: ->
    @provider = null
    @subscriptions.dispose()

  provide: ->
    unless @provider?
      RhinoProvider = require('./rhino-autocomplete-plus-python-provider')
      @provider = new RhinoProvider()
    @provider

  saveAndRunInRhino: ->
    rhinoIsntListeningMsg = "Rhino isn't listening for requests.  Run the \"StartAtomEditorListener\" command from within Rhino."
    editor = atom.workspace.getActiveTextEditor()
    if editor and not /.py$/.test editor.getPath()
      alert("Can't save and run.  Not a python file.")
      return
    editor.save()
    ttr.rhinoIsListening()
      .done (isListening) =>
        [isListening, rhinoPath] = isListening
        if isListening
          @bringRhinoToFront(rhinoPath)
          ttr.runInRhino editor.getPath()
            .done (msg) ->
              console.log msg
            .fail (errorObject) ->
              alert(rhinoIsntListeningMsg)
        else
          alert(rhinoIsntListeningMsg)
      .fail (errorObject) ->
        alert(rhinoIsntListeningMsg)

  bringRhinoToFront: (rhinoPath) ->
    #console.log "bringRhinoToFront: open #{rhinoPath}"
    rhino = shelljs.exec("open #{rhinoPath}", async: true, (code, output) ->
      #console.log "bringRhinoToFront: exit code: #{code}"
      console.log "bringRhinoToFront: output: #{output}" unless not output
    )

  saveAndRunInRhinoFromTreeView: ->
    #s = document.querySelectorAll('[is="tree-view-file"] .selected [data-name$=".py"]')
    selected = document.querySelectorAll('[is="tree-view-file"].selected span')
    if selected.length isnt 1
      alert('This command can only be run when exactly 1 file is selected')
      return
    fileName = selected[0].attributes["data-path"].value
    atom.workspace.open fileName
      .done (o) =>
        @saveAndRunInRhino()
