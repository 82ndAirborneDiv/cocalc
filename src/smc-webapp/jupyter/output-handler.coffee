###
Class that handles output messages generated for evaluation of code
for a particular cell.

WARNING: For efficiency reasons (involving syncdb patch sizes),
outputs is a map from the (string representations of) the numbers
from 0 to n-1, where there are n messages.  So watch out.

OutputHandler emits two events:

   - 'change' -- (save),  called when we change cell; if save=true, recommend
                 broadcasting this change to other users ASAP.

   - 'done'  -- emited once when finished; after this, everything is cleaned up

   - 'more_output'  -- If we exceed the message limit, emit more_output  (mesg, mesg_length)
                          with extra messages.

   - 'process'  -- Gets called on any incoming message; it may
                   **mutate** the message, e.g., removing images uses this.

###

{EventEmitter} = require('events')

misc = require('smc-util/misc')
{defaults, required} = misc

now = ->
    misc.server_time() - 0

class exports.OutputHandler extends EventEmitter
    constructor: (opts) ->
        @_opts = defaults opts,
            cell              : required    # object; the cell whose output (etc.) will get mutated
            max_output_length : undefined   # If given, used to truncate, discard output messages; extra
                                            # messages are saved and made available.
            report_started_ms : undefined   # If no messages for this many ms, then we update via set to indicate
                                            # that cell is being run.

        cell = @_opts.cell
        cell.output     = null
        cell.exec_count = null
        cell.state      = 'run'
        cell.start      = null
        cell.end        = null

        # Internal state
        @_n                        = 0
        @_clear_before_next_output = false
        @_output_length            = 0
        @_in_more_output_mode      = false

        # Report that computation started if there is no output soon.
        if @_opts.report_started_ms?
            setTimeout(@_report_started, @_opts.report_started_ms)

    close: =>
        @emit('done')
        delete @_opts
        delete @_n
        delete @_clear_before_next_output
        delete @_output_length
        delete @_in_more_output_mode
        @removeAllListeners()

    _clear_output: (save) =>
        @_clear_before_next_output = false
        # clear output message -- we delete all the outputs
        # reset the counter n, save, and are done.
        # IMPORTANT: In Jupyter the clear_output message and everything
        # before it is NOT saved in the notebook output itself
        # (like in Sage worksheets).
        @_opts.cell.output = null
        @_n = 0
        @_output_length = 0
        @emit('change', save)

    _report_started: =>
        if @_n > 0
            # do nothing -- already getting output
            return
        @emit('change', true)

    # Call when computation starts
    start: =>
        @_opts.cell.start = new Date() - 0
        @_opts.cell.state = 'busy'

    # Call error if an error occurs.  An appropriate error message is generated.
    # Computation is considered done.
    error: (err) =>
        @message
            text : "#{err}"
            name : "stderr"
        @done()

    # Call done when done
    done: =>
        @_opts.cell.state = 'done'
        @_opts.cell.start ?= now()
        @_opts.cell.end   = now()
        @emit('change', true)
        @close()

    # Handle clear
    clear: (wait) =>
        if wait
            # wait until next output before clearing.
            @_clear_before_next_output = true
        else
            @_clear_output()

    _clean_mesg: (mesg) =>
        delete mesg.execution_state
        delete mesg.code
        for k, v of mesg
            if misc.is_object(v) and misc.len(v) == 0
                delete mesg[k]

    _push_mesg: (mesg, save=true) =>
        @_opts.cell.output["#{@_n}"] = mesg
        @_n += 1
        @emit('change', save)

    # Process incoming messages.  This may mutate mesg.
    message: (mesg) =>
        if @_opts.cell.end
            # ignore any messages once we're done.
            return

        # record execution_count, if there.
        if mesg.execution_count?
            @_opts.cell.exec_count = mesg.execution_count
            delete mesg.execution_count

        # delete useless fields
        @_clean_mesg(mesg)

        if misc.len(mesg) == 0
            # don't even both saving this message; nothing useful here.
            return

        # hook to process message (e.g., this may mutate mesg, e.g., to remove big images)
        @emit('process', mesg)

        if @_clear_before_next_output
            @_clear_output(false)

        if @_opts.cell.output == null
            @_opts.cell.output = {}

        if not @_opts.max_output_length
            @_push_mesg(mesg)
            return

        # worry about length
        mesg_length = JSON.stringify(mesg)?.length ? 0
        @_output_length += mesg_length

        if @_output_length <= @_opts.max_output_length
            @_push_mesg(mesg)
            return

        # Check if we have entered the mode were output gets put in
        # the set_more_output buffer.
        if not @_in_more_output_mode
            @_push_mesg({more_output:true})
            @_in_more_output_mode = true
        @emit('more_output', mesg, mesg_length)

