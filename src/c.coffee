###
Some convenient command-line shortcuts.  If you're working on the command line, do

    require('./c.coffee')

The functiosns below in some cases return things, and in some cases set global variables!  Read docs.

###

start_time = new Date()
global.start = ->
    start_time = new Date()
global.start()
global.done = (args...) ->
    console.log("*** TOTALLY DONE! (#{(new Date() - start_time)/1000}s since start) ", args)
global.time = () ->
    global.start()
    return global.done

db = undefined
get_db = (cb) ->
    if db?
        cb(undefined, db)  # HACK -- might not really be initialized yet!
        return db
    else
        db = require('./smc-hub/rethink').rethinkdb(hosts:['db0'], pool:1, cb:cb)
        return db

# get a connection to the db
global.db = ->
    return global.db = get_db()
console.log("db() -- sets global variable db to a database")

global.gcloud = ->
    global.g = require('./smc-hub/smc_gcloud.coffee').gcloud(db:get_db())
    console.log("setting global variable g to a gcloud interface")

console.log("gcloud() -- sets global variable g to gcloud instance")

# make the global variable s be the compute server
global.compute_server = () ->
    return require('smc-hub/compute-client').compute_server
        db_hosts:['db0']
        cb:(e,s)->
            global.s=s
console.log("compute_server() -- sets global variable s to compute server")

# make the global variable p be the project with given id and the global variable s be the compute server
global.proj = global.project = (id) ->
    require('smc-hub/compute-client').compute_server
        db_hosts:['db0']
        cb:(e,s)->
            global.s=s
            s.project
                project_id:id
                cb:(e,p)->global.p=p

console.log("project('project_id') -- set p = project, s = compute server")

global.activity = (opts={}) ->
    opts.cb = (err, a) ->
        if err
            console.log("failed to initialize activity")
        else
            console.log('initialized activity')
            global.activity = a
    require('smc-hub/storage').activity(opts)

console.log("activity()  -- makes activity the activity monitor object")
