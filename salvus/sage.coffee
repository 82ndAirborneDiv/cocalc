############################################################################
#
# sage.coffee -- TCP interface between NodeJS and a Sage server instance
#
# The TCP interface to the sage server is necessarily "weird" because
# the Sage process that is actually running the code *is* the server
# one talks to via TCP after starting a session.  Since Sage itself is
# blocking when running code, and running as the user when running
# code can't be trusted, e.g., anything in the server can be
# arbitrarily modified, all *control* messages, e.g., sending signals,
# cleaning up, etc. absolutely require making a separate TCP connection.
#
# So:
#
#    1. Make a connection to the TCP server, which runs as root and
#       forks on connection.
#
#    2. Create a new session, which drops privileges to a random clean
#       user, and continues to listen on the TCP socket when not doing
#       computations.
#
#    3. Send request-to-exec, etc., messages to the socket in (2)
#       and get back output over (2).
#
#    4. To send a signal, get files, save worksheet state, etc.,
#       make a new connection to the TCP server, and send a message
#       in the freshly forked off process, which runs as root.
#
# With this architecture, the sage process that the user is
# interacting with has ultimate control over the messages it sends and
# receives (which is incredibly powerful and customizable), with no
# stupid pexpect or anything else like that to get in the way.  At the
# same time, we still have a root out-of-process control mechanism,
# though with the overhead of establishing a new connection each time.
# Since control messages are much less frequent, this overhead is
# acceptable.
#
############################################################################

net     = require('net')

winston = require('winston')            # https://github.com/flatiron/winston

message = require("message")

misc    = require("misc"); defaults = misc.defaults; required = defaults.required

exports.send_control_message = (opts={}) ->
    opts = defaults(opts, {host: required, port: required, mesg: required})
    sage_control_conn = new exports.Connection
        host : opts.host
        port : opts.port
        cb   : ->
            sage_control_conn.send_json(opts.mesg)
            sage_control_conn.close()

exports.send_signal = (opts={}) ->
    opts = defaults(opts, {host: required, port: required, pid:required, signal:required})
    exports.send_control_message
        host : opts.host
        port : opts.port
        mesg : message.send_signal(pid:opts.pid, signal:opts.signal)


class exports.Connection
    constructor: (options) ->
        options = defaults(options,
            host: required
            port: required
            recv: undefined
            cb:   undefined
        )
        @host = options.host
        @port = options.port
        @conn = net.connect({port:@port, host:@host}, options.cb)
        @recv = options.recv  # send message to client
        @buf = null
        @buf_target_length = -1

        @conn.on('error', (err) =>
            winston.error("sage connection error: #{err}")
            @recv?('json', message.terminate_session(reason:"#{err}"))
        )

        @conn.on('data', (data) =>
            # read any new data into buf
            if @buf == null
                @buf = data   # first time to ever recv data, so initialize buffer
            else
                @buf = Buffer.concat([@buf, data])   # extend buf with new data

            loop
                if @buf_target_length == -1
                    # starting to read a new message
                    if @buf and @buf.length >= 4
                        @buf_target_length = @buf.readUInt32BE(0) + 4
                    else
                        return  # have to wait for more data
                if @buf_target_length <= @buf.length
                    # read a new message from our buffer
                    type = @buf.slice(4, 5).toString()
                    mesg = @buf.slice(5, @buf_target_length)
                    switch type
                        when 'j'   # JSON
                            s = mesg.toString()
                            @recv?('json', JSON.parse(s))
                        when 'b'   # BLOB
                            @recv?('blob', mesg)
                        else
                            throw("unknown message type '#{type}'")
                    @buf = @buf.slice(@buf_target_length)
                    @buf_target_length = -1
                    if @buf.length == 0
                        return
                else  # nothing to do but wait for more data
                    return
        )
        @conn.on('end', -> winston.info("(sage.coffee) disconnected from sage server"))

    # send a message to sage_server
    _send: (s) ->
        #winston.info("(sage.coffee) send message: #{s}")
        buf = new Buffer(4)
        buf.writeInt32BE(s.length, 0)
        @conn.write(buf)
        @conn.write(s)

    send_json: (mesg) ->
        @_send('j' + JSON.stringify(mesg))

    send_blob: (uuid, blob) ->
        # TODO: is concat expensive and wasteful!?  -- easier to code
        # this way, then rewrite by copying code from _send later once
        # this works.
        @_send(Buffer.concat([new Buffer('b'), blob]))

    # Close the connection with the server.  You probably instead want
    # to send_signal(...) using the module-level fucntion to kill the
    # session, in most cases.
    close: () ->
        @conn.end()
        @conn.destroy()

###
test = (n=1) ->
    message = require("message")
    cb = () ->
        conn.send_json(message.start_session())
        for i in [1..n]
            conn.send_json(message.execute_code(id:0,code:"factor(2012)"))
    tm = (new Date()).getTime()
    conn = new exports.Connection(
        {
            host:'localhost'
            port:10000
            recv:(mesg) -> winston.info("received message #{mesg}; #{(new Date()).getTime()-tm}")
            cb:cb
        }
    )

test(5)
###