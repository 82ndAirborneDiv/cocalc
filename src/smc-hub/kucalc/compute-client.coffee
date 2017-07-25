###
Compute client for use in Kubernetes cluster by the hub.

The hub uses this module to get information about a project.  This is meant
to be used as part of kucalc, and replaces the other variants
of compute-client.coffee.

The name 'compute-client' probably isn't the best.  Really this is a module
that gets information about and controls projects.

What this modules should acomplish:

- Modify database in response to requests to start/stop/etc project.
- Provide the project secret token to the hub

###

LOCAL_HUB_PORT      = 6000
RAW_PORT            = 6001
SAGE_SERVER_PORT    = 6002
CONSOLE_SERVER_PORT = 6003

{EventEmitter} = require('events')
async = require('async')

misc = require('smc-util/misc')
{defaults, required} = misc

exports.compute_client = (db, logger) ->
    return new Client(db, logger)

class Dbg extends EventEmitter

class Client
    constructor: (@database, @logger) ->
        @dbg("constructor")()
        if not @database?
            throw Error("database must be defined")

    dbg: (f) =>
        if not @logger?
            return ->
        else
            return (args...) => @logger.debug("kucalc.Client.#{f}", args...)

    project: (opts) =>
        opts = defaults opts,
            project_id : required
            cb         : required
        @dbg("project")("project_id=#{opts.project_id}")
        @database.synctable
            table    : 'projects'
            columns  : ['state', 'status', 'action_request']
            where    :
                project_id : opts.project_id
            cb       : (err, synctable) =>
                if err
                    opts.cb(err)
                else
                    opts.cb(undefined, new Project(@, opts.project_id, synctable, @logger))

class Project extends EventEmitter
    constructor: (@client, @project_id, @synctable, @logger) ->
        @host = "project-#{@project_id}"
        @dbg('constructor')
        @synctable.on 'change', => @emit('change')

    # Get the current data about the project from the database.
    get: (field) =>
        t = @synctable.get(@project_id)
        if field?
            return t?.get(field)
        else
            return t

    getIn: (v) =>
        return @get().getIn(v)

    _action_request: =>
        x = @get('action_request')?.toJS()
        if x.started?
            x.started = new Date(x.started)
        if x.finished?
            x.finished = new Date(x.finished)
        return x

    dbg: (f) =>
        if not @logger?
            return ->
        else
            return (args...) => @logger.debug("kucalc.Project('#{@project_id}').#{f}", args...)

    close: () =>
        @synctable?.close()
        delete @synctable
        delete @logger
        delete @project_id
        delete @compute_server
        delete @host

    state: (opts) =>
        opts = defaults opts,
            force  : false  # ignored
            update : false  # ignored
            cb     : required     # cb(err, {state:?, time:?, error:?})
        dbg = @dbg("state")
        dbg()
        opts.cb(undefined, @get('state')?.toJS())

    status: (opts) =>
        opts = defaults opts,
            cb     : required
        dbg = @dbg("status")
        dbg()
        status = @get('status')?.toJS() ? {}
        misc.merge status,  # merge in canonical information
            "local_hub.port"      : LOCAL_HUB_PORT
            "raw.port"            : RAW_PORT
            "sage_server.port"    : SAGE_SERVER_PORT
            "console_server.port" : CONSOLE_SERVER_PORT
        opts.cb(undefined, status)

    _action: (opts) =>
        opts = defaults opts,
            action    : required    # action to do
            goal      : required    # wait until goal(project) is true, where project is immutable js obj
            timeout_s : 300         # timeout in seconds (only used for wait)
            cb        : undefined
        dbg = @dbg("_action('#{opts.action}')")
        if opts.goal(@get())
            dbg("condition already holds; nothing to do.")
            opts.cb?()
            return

        if opts.goal?
            dbg("start waiting for goal to be satisfied")
            @synctable.wait
                until   : () =>
                    return opts.goal(@get())
                timeout : opts.timeout_s
                cb      : (err) =>
                    dbg("done waiting for goal #{err}")
                    opts.cb?(err)
                    delete opts.cb

        dbg("request action to happen")
        @_query
            jsonb_set :
                action_request :
                    action   : opts.action
                    time     : new Date()
                    started  : undefined
                    finished : undefined
            cb          : (err) =>
                if err
                    dbg('action request failed')
                    opts.cb?(err)
                    delete opts.cb
                else
                    dbg("action requested")

    _query: (opts) =>
        opts.query = 'UPDATE projects'
        opts.where = {'project_id  = $::UUID' : @project_id}
        @client.database._query(opts)

    open: (opts) =>
        opts = defaults opts,
            cb   : undefined
        dbg = @dbg("open")
        dbg()
        @_action
            action : 'open'
            goal   : (project) => (project.getIn(['state', 'state']) ? 'closed') != 'closed'
            cb     : opts.cb

    start: (opts) =>
        opts = defaults opts,
            set_quotas : true    # ignored
            cb         : undefined
        dbg = @dbg("start")
        dbg()
        @_action
            action : 'start'
            goal   : (project) -> project.getIn(['state', 'state']) == 'running'
            cb     : opts.cb

    stop: (opts) =>
        opts = defaults opts,
            cb     : undefined
        dbg = @dbg("stop")
        dbg()
        @_action
            action : 'stop'
            goal   : (project) -> project.getIn(['state', 'state']) in ['opened', 'closed']
            cb     : opts.cb

    restart: (opts) =>
        opts = defaults opts,
            set_quotas : true    # ignored
            cb         : undefined
        dbg = @dbg("restart")
        dbg()
        async.series([
            (cb) =>
                @stop(cb:cb)
            (cb) =>
                @start(cb:cb)
        ], (err) => opts.cb?(err))

    ensure_running: (opts) =>
        @start(opts)  # it's just the same

    ensure_closed: (opts) =>
        opts = defaults opts,
            cb     : undefined
        dbg = @dbg("ensure_closed")
        dbg()
        @_action
            action : 'close'
            goal   : (project) -> project.getIn(['state', 'state']) == 'closed'
            cb     : opts.cb

    move: (opts) =>
        opts = defaults opts,
            target : undefined # ignored
            force  : false     # ignored for now
            cb     : required
        opts.cb("move makes no sense for Kubernetes")

    address: (opts) =>
        opts = defaults opts,
            cb : required
        dbg = @dbg("address")
        dbg('first ensure is running')
        @ensure_running
            cb : (err) =>
                if err
                    dbg('error starting it up')
                    opts.cb(err)
                    return
                dbg('it is running')
                address =
                    host         : @host
                    port         : LOCAL_HUB_PORT
                    secret_token : @getIn(['status', 'secret_token'])
                if not address.secret_token
                    err = 'BUG -- running, but no secret_token!'
                    dbg(err)
                    opts.cb(err)
                else
                    opts.cb(undefined, address)

    ###
    LATER
    ###


    # this is a no-op for Kubernetes; this was only used for serving
    # some static websites, e.g., wstein.org, so may evolve into that...
    save: (opts) =>
        opts = defaults opts,
            min_interval  : undefined # ignored
            cb            : undefined # ignored
        dbg = @dbg("save(min_interval:#{opts.min_interval})")
        dbg()
        opts.cb?()

    copy_path: (opts) =>
        opts = defaults opts,
            path              : ""
            target_project_id : ""
            target_path       : ""        # path into project; if "", defaults to path above.
            overwrite_newer   : false     # if true, newer files in target are copied over (otherwise, uses rsync's --update)
            delete_missing    : false     # if true, delete files in dest path not in source, **including** newer files
            backup            : false     # make backup files
            exclude_history   : false
            timeout           : 5*60
            bwlimit           : undefined
            cb                : undefined
        dbg = @dbg("copy_path(#{opts.path} to #{opts.target_project_id})")
        dbg("copy a path using rsync from one project to another")
        if not opts.target_project_id
            opts.target_project_id = @project_id
        if not opts.target_path
            opts.target_path = opts.path
        opts.cb?("copy_path -- not implemented")

    directory_listing: (opts) =>
        opts = defaults opts,
            path      : ''
            hidden    : false
            time      : false        # sort by timestamp, with newest first?
            start     : 0
            limit     : -1
            cb        : undefined
        dbg = @dbg("directory_listing")
        dbg()
        opts.cb?("directory_listing -- not implemented")

    read_file: (opts) =>
        opts = defaults opts,
            path    : required
            maxsize : 3000000    # maximum file size in bytes to read
            cb      : undefined   # cb(err, Buffer)
        dbg = @dbg("read_file(path:'#{opts.path}')")
        dbg("read a file or directory from disk")  # directories get zip'd
        opts.cb?("read_file -- not implemented")

    get_quotas: (opts) =>
        opts = defaults opts,
            cb           : required
        dbg = @dbg("get_quotas")
        dbg("lookup project quotas in the database")
        @compute_server.database.get_project_quotas
            project_id : @project_id
            cb         : opts.cb

    set_member_host: (opts) =>
        opts = defaults opts,
            member_host : required
            cb          : required
        # Ensure that member_host is a boolean for below; it is an integer -- 0 or >= 1 -- elsewhere.  But below
        # we very explicitly assume it is boolean (due to coffeescript not doing coercion).
        opts.member_host =  opts.member_host > 0
        dbg = @dbg("set_member_host(member_host=#{opts.member_host})")
        dbg()
        opts.cb() # TODO

    set_quotas: (opts) =>
        opts = misc.copy_with(opts, ['disk_quota', 'cores', 'memory', 'cpu_shares', 'network',
                                     'mintime', 'member_host', 'cb'])
        dbg = @dbg("set_quotas")
        dbg()
        opts.cb() # TODO

    set_all_quotas: (opts) =>
        opts = defaults opts,
            cb : required
        dbg = @dbg("set_all_quotas")
        dbg()
        opts.cb() # TODO




