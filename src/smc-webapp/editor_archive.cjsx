{React, ReactDOM, rclass, rtypes, Flux, Actions, Store}  = require('./r')
{Button, Panel, Row, Col} = require('react-bootstrap')
{Icon} = require('./r_misc')
{salvus_client} = require('./salvus_client')
async = require('async')
misc = require('smc-util/misc')

COMMANDS =
    zip :
        list :
            command : 'unzip'
            args    : ['-l']
        extract :
            command : 'unzip'
            args    : ['-B']
    tar :
        list :
            command : 'tar'
            args    : ['-tf']
        extract :
            command : 'tar'
            args    : ['-xvf']
    gz :
        list :
            command : 'gzip'
            args    : ['-l']
        extract :
            command : 'gunzip'
            args    : ['-vf']
    bzip2 :
        list :
            command : 'ls'
            args    : ['-l']
        extract :
            command : 'bunzip2'
            args    : ['-vf']
    lzip :
        list :
            command : 'ls'
            args    : ['-l']
        extract :
            command : 'lzip'
            args    : ['-vfd']
    xz :
        list :
            command : 'xz'
            args    : ['-l']
        extract :
            command : 'xz'
            args    : ['-vfd']

flux_name = (project_id, path) ->
    return "editor-#{project_id}-#{path}"

class ArchiveActions extends Actions
    _set_to: (payload) =>
        payload

    parse_file_type : (file_info) ->
        if file_info.indexOf('Zip archive data') != -1
            return 'zip'
        else if file_info.indexOf('tar archive') != -1
            return 'tar'
        else if file_info.indexOf('gzip compressed data') != -1
            return 'gz'
        else if file_info.indexOf('bzip2 compressed data') != -1
            return 'bzip2'
        else if file_info.indexOf('lzip compressed data') != -1
            return 'lzip'
        else if file_info.indexOf('XZ compressed data') != -1
            return 'xz'
        return undefined

    set_archive_contents : (project_id, path) ->
        async.waterfall([
            # Get the file type data. Error if no file found.
            (waterfall_cb) =>
                salvus_client.exec
                    project_id : project_id
                    command    : "file"
                    args       : ["-z", "-b", path]
                    err_on_exit: true
                    cb         : (err, info) =>
                        if err
                            if err.indexOf('No such file or directory') != -1
                                err = "No such file or directory"
                        waterfall_cb(err, info)
            # Get the file type. Error if file type not supported.
            (info, waterfall_cb) =>
                if not info?.stdout?
                    cb("Unsupported archive type.\n\nYou might try using a terminal.")
                type = @parse_file_type(info.stdout)
                if not type?
                    cb("Unsupported archive type -- #{info.stdout} \n\nYou might try using a terminal.", info)
                waterfall_cb(undefined, info, type)
            # Get archive contents. Error if unable to read archive.
            (info, type, waterfall_cb) =>
                {command, args} = COMMANDS[type].list

                salvus_client.exec
                    project_id : project_id
                    command    : command
                    args       : args.concat([path])
                    err_on_exit: false
                    cb         : (client_err, client_output) =>
                        waterfall_cb(client_err, info, type, client_output)

        ], (err, info, type, contents) =>
            if not err
                @_set_to(error : err, info : info.stdout, contents : contents.stdout, type : type)
        )

    extract_archive_files : (project_id, path, type, contents) ->
        {command, args} = COMMANDS[type].extract
        path_parts = misc.path_split(path)
        async.waterfall([
            (cb) =>
                if not contents?
                    cb("Archive not loaded yet")
                if type == 'zip'
                    # special case for zip files: if heuristically it looks like not everything is contained
                    # in a subdirectory with name the zip file, then create that subdirectory.
                    base = path_parts.tail.slice(0, path_parts.tail.length - 4)
                    if contents.indexOf(base+'/') == -1
                        extra_args = ['-d', base]
                    cb(undefined, extra_args, [])
                else if type == 'tar'
                    # special case for tar files: if heuristically it looks like not everything is contained
                    # in a subdirectory with name the tar file, then create that subdirectory.
                    i = path_parts.tail.lastIndexOf('.t')  # hopefully that's good enough.
                    base = path_parts.tail.slice(0, i)
                    if contents.indexOf(base+'/') == -1
                        post_args = ['-C', base]
                        salvus_client.exec
                            project_id : project_id
                            path       : path_parts.head
                            command    : "mkdir"
                            args       : ['-p', base]
                            cb         : =>
                                cb(undefined, [], post_args)
                else
                    cb(undefined, [], [])
            (extra_args, post_args, cb) =>
                args = args.concat(extra_args).concat([path_parts.tail]).concat(post_args)
                args_str = ((if x.indexOf(' ')!=-1 then "'#{x}'" else x) for x in args).join(' ')
                cmd = "cd #{path_parts.head} ; #{command} #{args_str}"
                @_set_to(loading : true, command : cmd)
                salvus_client.exec
                    project_id : project_id
                    path       : path_parts.head
                    command    : command
                    args       : args
                    err_on_exit: false
                    timeout    : 120
                    cb         : (err, out) =>
                        @_set_to(loading : false)
                        cb(err, out)
        ], (err, output) =>
            @_set_to(error : err, extract_output : output.stdout)
        )

class ArchiveStore extends Store
    _init: (flux) =>
        ActionIds = flux.getActionIds(@name)
        @register(ActionIds._set_to, @setState)
        @state = {}

exports.init_flux = init_flux = (flux, project_id, filename) ->
    name = flux_name(project_id, filename)
    if flux.getActions(name)?
        return  # already initialized
    actions = flux.createActions(name, ArchiveActions)
    store   = flux.createStore(name, ArchiveStore)
    store._init(flux)

ArchiveContents = ({actions, contents, project_id, path}) ->
    if not contents?
        actions.set_archive_contents(project_id, path)
    <pre>{contents}</pre>


Archive = ({actions, path, project_id, type, contents, info, command, extract_output, error, loading}) ->
    title = () ->
        <tt><Icon name="file-zip-o" /> {path}</tt>

    extract_archive_files = () ->
        actions.extract_archive_files(project_id, path, type, contents)

    <Panel header={title()}>
        <Button bsSize='large' bsStyle='success' onClick={@extract_archive_files}><Icon name='folder' spin={loading} /> Extract Files...</Button>
        {<pre>{command}</pre> if command}
        {<pre>{extract_output}</pre> if extract_output}
        {<pre>{error}</pre> if error}

        <h2>Contents</h2>

        {info}
        <ArchiveContents path={path} contents={contents} actions={actions} project_id={project_id} />
    </Panel>

render = (flux, project_id, path) ->
    name = flux_name(project_id, path)
    actions = flux.getActions(name)
    connect_to =
        contents   : name
        info       : name
        type       : name
        loading    : name
        command    : name
        error      : name
        extract_output : name

    <Flux flux={flux} connect_to=connect_to>
        <Archive path={path} actions={actions} project_id={project_id} />
    </Flux>

exports.free = (project_id, path, dom_node, flux) ->
    ReactDOM.unmountComponentAtNode(dom_node)

exports.render = (project_id, path, dom_node, flux) ->
    init_flux(flux, project_id, path)
    ReactDOM.render(render(flux, project_id, path), dom_node)

exports.hide = (project_id, path, dom_node, flux) ->
    ReactDOM.unmountComponentAtNode(dom_node)

exports.show = (project_id, path, dom_node, flux) ->
    ReactDOM.render(render(flux, project_id, path), dom_node)