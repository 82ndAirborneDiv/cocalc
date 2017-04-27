misc = require('smc-util/misc')

{React, ReactDOM, rclass, rtypes}  = require('../smc-react')
{Icon, ImmutablePureRenderMixin, Markdown, HTML} = require('../r_misc')
{sanitize_html} = require('../misc_page')
{Button} = require('react-bootstrap')

Ansi = require('ansi-to-react')

{get_blob_url} = require('./server-urls')

OUT_STYLE =
    whiteSpace    : 'pre-wrap'
    wordWrap      : 'break-word'
    fontFamily    : 'monospace'
    paddingTop    : '5px'
    paddingBottom : '5px'
    paddingLeft   : '5px'

ANSI_STYLE      = OUT_STYLE
STDOUT_STYLE    = OUT_STYLE
STDERR_STYLE    = misc.merge({backgroundColor:'#fdd'}, STDOUT_STYLE)
TRACEBACK_STYLE = misc.merge({backgroundColor: '#f9f2f4'}, OUT_STYLE)

Stdout = rclass
    propTypes :
        message : rtypes.immutable.Map.isRequired

    mixins: [ImmutablePureRenderMixin]

    render: ->
        value = @props.message.get('text')
        if is_ansi(value)
            <div style={STDOUT_STYLE}>
                <Ansi>{value}</Ansi>
            </div>
        else
            <div style={STDOUT_STYLE}>
                {value}
            </div>

Stderr = rclass
    propTypes :
        message : rtypes.immutable.Map.isRequired

    mixins: [ImmutablePureRenderMixin]

    render: ->
        <div style={STDERR_STYLE}>
            {@props.message.get('text')}
        </div>

Image = rclass
    propTypes:
        type       : rtypes.string.isRequired
        sha1       : rtypes.string   # one of sha1 or value should be given
        value      : rtypes.string
        project_id : rtypes.string

    getInitialState: ->
        attempts : 0

    load_error: ->
        if @state.attempts < 5 and @_is_mounted
            f = =>
                if @_is_mounted
                    @setState(attempts : @state.attempts + 1)
            setTimeout(f, 500)

    componentDidMount: ->
        @_is_mounted = true

    componentWillUnmount: ->
        @_is_mounted = false

    extension: ->
        return @props.type.split('/')[1].split('+')[0]

    render_using_server: ->
        src = get_blob_url(@props.project_id, @extension(), @props.sha1) + "&attempts=#{@state.attempts}"
        return <img src={src} onError={@load_error}/>

    encoding: ->
        switch @props.type
            when "image/svg+xml"
                return 'utf8'
            else
                return 'base64'

    render_locally: ->
        src = "data:#{@props.type};#{@encoding()},#{@props.value}"
        return <img src={src}/>

    render: ->
        if @props.value?
            return @render_locally()
        else if @props.sha1? and @props.project_id?
            return @render_using_server()
        else # not enough info to render
            return <span>[unavailable {@extension()} image]</span>

TextPlain = rclass
    propTypes:
        value : rtypes.string.isRequired

    render: ->
        <div style={STDOUT_STYLE}>
            {@props.value}
        </div>

'''
Evaluating JavaScript in a cell.
What features should be supported? [x] means this works.

* [x] local variable "element"
* [x] require.js loading, e.g.

    %%javascript
    require(['//cdnjs.cloudflare.com/ajax/libs/d3/4.8.0/d3.js'], function(d3) {
        console.log(d3); // d3 is sometimes undefined
        d3.select(element[0]).append("h1").text("Successfully loaded D3 version " + d3.version);
    });

* [x] convey data from e.g. python via the global window reference to be used in javascript mode, e.g.

    cell 1:
        from IPython.display import Javascript
        Javascript("window.xy = %s" % 99)
    cell 2:
        %%javascript
        element.append(window.xy)
    and then the output is 99.

* [ ] introspection, e.g.

    %%javascript
    var output_area = this;
    // find my cell element
    var cell_element = output_area.element.parents('.cell');
    // which cell is it?
    var cell_idx = Jupyter.notebook.get_cell_elements().index(cell_element);
    // get the cell object
    var cell = Jupyter.notebook.get_cell(cell_idx);

* [ ] custom style (strategically add classNames, etc.)

* [ ] anything else?
'''
Javascript = rclass
    propTypes:
        value : rtypes.oneOfType([rtypes.object, rtypes.string]).isRequired

    componentDidMount: ->
        element = $(ReactDOM.findDOMNode(@))
        if typeof(@props.value) != 'string'
            value = @props.value.toJS()
        else
            value = @props.value
        if misc.is_array(value)
            value = value.join('\n')

        try
            window.require   = window.__require
            window.define    = window.__define
            window.requirejs = window.__requirejs
            eval(value)
        catch err
            console.log("Error: #{err}")
        finally
            window.__require   = window.require
            window.__define    = window.define
            window.__requirejs = window.requirejs
            window.require     = undefined
            window.define      = false  # the default, I don't know why
            window.requirejs   = undefined

    render: ->
        <div></div>

PDF = rclass
    propTypes:
        project_id : rtypes.string
        value      : rtypes.oneOfType([rtypes.object, rtypes.string]).isRequired

    render: ->
        if misc.is_string(@props.value)
            href  = get_blob_url(@props.project_id, 'pdf', @props.value)
        else
            value = @props.value.get('value')
            href = "data:application/pdf;base64,#{value}"
        <div style={OUT_STYLE}>
            <a href={href} target='_blank' style={cursor:'pointer'}>
                View PDF
            </a>
        </div>

Data = rclass
    propTypes:
        message    : rtypes.immutable.Map.isRequired
        project_id : rtypes.string
        directory  : rtypes.string

    mixins: [ImmutablePureRenderMixin]

    render: ->
        type  = undefined
        value = undefined
        @props.message.get('data').forEach (v, k) ->
            type  = k
            value = v
            return false
        if type
            [a, b] = type.split('/')
            switch a
                when 'text'
                    switch b
                        when 'plain'
                            if is_ansi(value)
                                return <div style={STDOUT_STYLE}><Ansi>{value}</Ansi></div>
                            else
                                return <TextPlain value={value}/>
                        when 'html', 'latex'  # put latex as HTML, since jupyter requires $'s anyways.
                            return <HTML
                                    value      = {value}
                                    project_id = {@props.project_id}
                                    file_path  = {@props.directory}
                                   />
                        when 'markdown'
                            return <Markdown
                                    value      = {value}
                                    project_id = {@props.project_id}
                                    file_path  = {@props.directory}
                                />
                when 'image'
                    return <Image
                        project_id = {@props.project_id}
                        type       = {type}
                        sha1       = {value if typeof(value) == 'string'}
                        value      = {value.get('value') if typeof(value) == 'object'}
                        />
                when 'application'
                    switch b
                        when 'javascript'
                            return <Javascript value={value}/>
                        when 'pdf'
                            return <PDF value={value} project_id = {@props.project_id}/>

        return <pre>Unsupported message: {JSON.stringify(@props.message.toJS())}</pre>

Traceback = rclass
    propTypes :
        message : rtypes.immutable.Map.isRequired

    mixins: [ImmutablePureRenderMixin]

    render: ->
        v = []
        n = 0
        @props.message.get('traceback').forEach (x) ->
            v.push(<Ansi key={n}>{x}</Ansi>)
            n += 1
            return
        <div style={TRACEBACK_STYLE}>
            {v}
        </div>

MoreOutput = rclass
    propTypes :
        message : rtypes.immutable.Map.isRequired
        actions : rtypes.object  # if not set, then can't get more ouput
        id      : rtypes.string.isRequired

    shouldComponentUpdate: (next) ->
        return next.message != @props.message

    show_more_output: ->
        @props.actions?.fetch_more_output(@props.id)

    render: ->
        if not @props.actions? or @props.message.get('expired')
            <Button bsStyle = "info" disabled>
                <Icon name='eye-slash'/> Additional output not available
            </Button>
        else
            <Button onClick={@show_more_output} bsStyle = "info">
                <Icon name='eye'/> Fetch additional output...
            </Button>

INPUT_STYLE =
    padding : '0em 0.25em'
    margin  : '0em 0.25em'

InputDone = rclass
    propTypes :
        message : rtypes.immutable.Map.isRequired

    render: ->
        value = @props.message.get('value') ? ''
        <div style={STDOUT_STYLE}>
            {@props.message.getIn(['opts', 'prompt']) ? ''}
            <input
                style       = {INPUT_STYLE}
                type        = {if @props.message.getIn(['opts', 'password']) then 'password' else 'text'}
                size        = {Math.max(47, value.length + 10)}
                readOnly    = {true}
                value       = {value}
            />
        </div>

Input = rclass
    propTypes :
        message : rtypes.immutable.Map.isRequired
        actions : rtypes.object
        id      : rtypes.string.isRequired

    getInitialState: ->
        value : ''

    key_down: (evt) ->
        if evt.keyCode == 13
            @submit()
        # Official docs: If the user hits EOF (*nix: Ctrl-D, Windows: Ctrl-Z+Return), raise EOFError.
        # The Jupyter notebook does *NOT* properly implement this.  We do something at least similar
        # and send an interrupt on control d or control z.
        if (evt.keyCode == 68 or evt.keyCode == 90) and evt.ctrlKey
            @props.actions?.signal('SIGINT')
            setTimeout(@submit, 10)

    submit: ->
        @props.actions?.submit_input(@props.id, @state.value)
        @props.actions?.focus_unlock()

    render: ->
        <div style={STDOUT_STYLE}>
            {@props.message.getIn(['opts', 'prompt']) ? ''}
            <input
                style       = {INPUT_STYLE}
                autoFocus   = {true}
                readOnly    = {not @props.actions?}
                type        = {if @props.message.getIn(['opts', 'password']) then 'password' else 'text'}
                ref         = 'input'
                size        = {Math.max(47, @state.value.length + 10)}
                value       = {@state.value}
                onChange    = {(e) => @setState(value: e.target.value)}
                onBlur      = {@props.actions?.focus_unlock}
                onFocus     = {@props.actions?.blur_lock}
                onKeyDown   = {@key_down}
            />
        </div>


NotImplemented = rclass
    propTypes :
        message : rtypes.immutable.Map.isRequired

    mixins: [ImmutablePureRenderMixin]

    render: ->
        <pre style={STDERR_STYLE}>
            {JSON.stringify(@props.message.toJS())}
        </pre>


message_component = (message) ->
    if message.get('more_output')?
        return MoreOutput
    if message.get('name') == 'stdout'
        return Stdout
    if message.get('name') == 'stderr'
        return Stderr
    if message.get('name') == 'input'
        if message.get('value')?
            return InputDone
        else
            return Input
    if message.get('data')?
        return Data
    if message.get('traceback')?
        return Traceback
    return NotImplemented

exports.CellOutputMessage = CellOutputMessage = rclass
    propTypes :
        message    : rtypes.immutable.Map.isRequired
        project_id : rtypes.string
        directory  : rtypes.string
        actions    : rtypes.object  # optional  - not needed by most messages
        id         : rtypes.string  # optional, and not usually needed either

    render: ->
        C = message_component(@props.message)
        <C
            message    = {@props.message}
            project_id = {@props.project_id}
            directory  = {@props.directory}
            actions    = {@props.actions}
            id         = {@props.id}
            />

OUTPUT_STYLE =
    flex            : 1
    overflowX       : 'auto'
    lineHeight      : 'normal'
    backgroundColor : '#fff'
    border          : 0
    marginBottom    : 0
    marginLeft      : '1px'

OUTPUT_STYLE_SCROLLED = misc.merge({maxHeight:'40vh'}, OUTPUT_STYLE)

exports.CellOutputMessages = rclass
    propTypes :
        actions    : rtypes.object  # optional actions
        output     : rtypes.immutable.Map.isRequired  # the actual messages
        project_id : rtypes.string
        directory  : rtypes.string
        scrolled   : rtypes.bool
        id         : rtypes.string

    shouldComponentUpdate: (next) ->
        return \
            next.output   != @props.output or \
            next.scrolled != @props.scrolled

    render_output_message: (n, mesg) ->
        if not mesg?
            return
        <CellOutputMessage
            key        = {n}
            message    = {mesg}
            project_id = {@props.project_id}
            directory  = {@props.directory}
            actions    = {@props.actions}
            id         = {@props.id}
        />

    message_list: ->
        v = []
        k = 0
        # TODO: use caching to make this more efficient...
        # combine stdout and stderr messages...
        for n in [0...@props.output.size]
            mesg = @props.output.get("#{n}")
            if not mesg?
                continue
            name = mesg.get('name')
            if k > 0 and (name == 'stdout' or name == 'stderr') and v[k-1].get('name') == name
                v[k-1] = v[k-1].set('text', v[k-1].get('text') + mesg.get('text'))
            else

                v[k] = mesg
                k += 1
        return v

    render: ->
        # (yes, I know n is a string in the next line, but that's fine since it is used only as a key)
        v = (@render_output_message(n, mesg) for n, mesg of @message_list())
        <div
            style = {if @props.scrolled then OUTPUT_STYLE_SCROLLED else OUTPUT_STYLE}
            >
            {v}
        </div>

is_ansi = (s) ->
    return s? and s.indexOf("\u001b") != -1