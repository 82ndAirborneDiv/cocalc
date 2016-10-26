#############################################
# Editor for HTML/Markdown/ReST documents
#############################################

_               = require('underscore')
async           = require('async')

misc            = require('smc-util/misc')
{defaults, required} = misc

misc_page       = require('../misc_page')

editor          = require('../editor')

{alert_message} = require('../alerts')
{salvus_client} = require('../salvus_client')
{IS_MOBILE}     = require('../feature')

{redux}         = require('../smc-react')


templates       = $("#salvus-editor-templates")


class exports.HTML_MD_Editor extends editor.FileEditor
    constructor: (@project_id, @filename, content, @opts) ->
        # The are two components, side by side
        #     * source editor -- a CodeMirror editor
        #     * preview/contenteditable -- rendered view
        @ext = misc.filename_extension_notilde(@filename).toLowerCase()   #'html' or 'md'
        # console.log("HTML_MD_editor", @)

        if @ext == 'html'
            @opts.mode = 'htmlmixed'
        else if @ext == 'md'
            @opts.mode = 'gfm'
        else if @ext == 'rst'
            @opts.mode = 'rst'
        else if @ext == 'wiki' or @ext == "mediawiki"
            # canonicalize .wiki and .mediawiki (as used on github!) to "mediawiki"
            @ext = "mediawiki"
            @opts.mode = 'mediawiki'
        else if @ext == 'tex'  # for testing/experimentation
            @opts.mode = 'stex2'
        else
            throw Error('file must have extension md or html or rst or wiki or tex')

        @disable_preview = @local_storage("disable_preview")
        if not @disable_preview? and @opts.mode == 'htmlmixed'
            # Default the preview to be disabled for html, but enabled for everything else.
            # This is mainly because when editing the SMC source itself, the previews break
            # everything by emding SMC's own code in the DOM.  However, it is probably a
            # reasonable default more generally.
            @disable_preview = true

        @element = templates.find(".salvus-editor-html-md").clone()

        # create the textedit button bar.
        @edit_buttons = templates.find(".salvus-editor-textedit-buttonbar").clone()
        @element.find(".salvus-editor-html-md-textedit-buttonbar").append(@edit_buttons)

        @preview = @element.find(".salvus-editor-html-md-preview")
        @preview_content = @preview.find(".salvus-editor-html-md-preview-content")
        @preview.on 'scroll', =>
            @preview_scroll_position = @preview.scrollTop()

        # initialize the codemirror editor
        @source_editor = editor.codemirror_session_editor(@project_id, @filename, @opts)
        @element.find(".salvus-editor-html-md-source-editor").append(@source_editor.element)
        @source_editor.action_key = @action_key

        @spell_check()

        cm = @cm()
        cm.on('change', _.debounce(@update_preview,500))
        #cm.on 'cursorActivity', @update_preview

        @init_buttons()
        @init_draggable_split()

        @init_preview_select()

        @init_keybindings()

        # this is entirely because of the chat
        # currently being part of @source_editor, and
        # only calling the show for that; once chat
        # is refactored out, delete this.
        @source_editor.on 'show-chat', () =>
            @show()
        @source_editor.on 'hide-chat', () =>
            @show()

    cm: () =>
        return @source_editor.syncdoc.focused_codemirror()

    init_keybindings: () =>
        keybindings =  # inspired by http://www.door2windows.com/list-of-all-keyboard-shortcuts-for-sticky-notes-in-windows-7/
            bold      : 'Cmd-B Ctrl-B'
            italic    : 'Cmd-I Ctrl-I'
            underline : 'Cmd-U Ctrl-U'
            comment   : 'Shift-Ctrl-3'
            strikethrough : 'Shift-Cmd-X Shift-Ctrl-X'
            justifycenter : "Cmd-E Ctrl-E"
            #justifyright  : "Cmd-R Ctrl-R"  # messes up page reload
            subscript     : "Cmd-= Ctrl-="
            superscript   : "Shift-Cmd-= Shift-Ctrl-="

        extra_keys = @cm().getOption("extraKeys") # current keybindings
        if not extra_keys?
            extra_keys = {}
        for cmd, keys of keybindings
            for k in keys.split(' ')
                ( (cmd) => extra_keys[k] = (cm) => @command(cm, cmd) )(cmd)

        for cm in @source_editor.codemirrors()
            cm.setOption("extraKeys", extra_keys)

    init_draggable_split: () =>
        @_split_pos = @local_storage("split_pos")
        @_dragbar = dragbar = @element.find(".salvus-editor-html-md-resize-bar")
        dragbar.css(position:'absolute')
        dragbar.draggable
            axis : 'x'
            containment : @element
            zIndex      : 100
            stop        : (event, ui) =>
                # compute the position of bar as a number from 0 to 1
                left  = @element.offset().left
                chat_pos = @element.find(".salvus-editor-codemirror-chat").offset()
                if chat_pos.left
                    width = chat_pos.left - left
                else
                    width = @element.width()
                p     = dragbar.offset().left
                @_split_pos = (p - left) / width
                @local_storage('split_pos', @_split_pos)
                @show()

    inverse_search: (cb) =>

    forward_search: (cb) =>

    action_key: () =>

    init_buttons: () =>
        @element.find("a").tooltip(delay:{ show: 500, hide: 100 } )
        @element.find("a[href=\"#save\"]").click(@click_save_button)
        @print_button = @element.find("a[href=\"#print\"]").show().click(@print)
        @init_edit_buttons()
        @init_preview_buttons()

    command: (cm, cmd, args) =>
        switch cmd
            when "link"
                cm.insert_link()
            when "image"
                cm.insert_image()
            when "SpecialChar"
                cm.insert_special_char()
            else
                cm.edit_selection
                    cmd  : cmd
                    args : args
                    mode : @opts.mode
                @sync()

    init_preview_buttons: () =>
        disable = @element.find("a[href=\"#disable-preview\"]").click (evt) =>
            evt.preventDefault()
            disable.hide()
            enable.show()
            @disable_preview = true
            @local_storage("disable_preview", true)
            @preview_content.html('')

        enable = @element.find("a[href=\"#enable-preview\"]").click (evt) =>
            evt.preventDefault()
            disable.show()
            enable.hide()
            @disable_preview = false
            @local_storage("disable_preview", false)
            @update_preview()

        if @disable_preview
            enable.show()
            disable.hide()

    init_edit_buttons: () =>
        that = @
        @edit_buttons.find("a").click () ->
            args = $(this).data('args')
            cmd  = $(this).attr('href').slice(1)
            if args? and typeof(args) != 'object'
                args = "#{args}"
                if args.indexOf(',') != -1
                    args = args.split(',')
            that.command(that.cm(), cmd, args)
            return false

        if true #  @ext != 'html'
            # hide some buttons, since these are not markdown friendly operations:
            for t in ['clean'] # I don't like this!
                @edit_buttons.find("a[href=\"##{t}\"]").hide()

        # initialize the color controls
        button_bar = @edit_buttons
        init_color_control = () =>
            elt   = button_bar.find(".sagews-output-editor-foreground-color-selector")
            if IS_MOBILE
                elt.hide()
                return
            button_bar_input = elt.find("input").colorpicker()
            sample = elt.find("i")
            set = (hex, init) =>
                sample.css("color", hex)
                button_bar_input.css("background-color", hex)
                if not init
                    @command(@cm(), "color", hex)

            button_bar_input.change (ev) =>
                hex = button_bar_input.val()
                set(hex)

            button_bar_input.on "changeColor", (ev) =>
                hex = ev.color.toHex()
                set(hex)

            sample.click (ev) =>
                button_bar_input.colorpicker('show')

            set("#000000", true)

        init_color_control()
        # initialize the color control
        init_background_color_control = () =>
            elt   = button_bar.find(".sagews-output-editor-background-color-selector")
            if IS_MOBILE
                elt.hide()
                return
            button_bar_input = elt.find("input").colorpicker()
            sample = elt.find("i")
            set = (hex, init) =>
                button_bar_input.css("background-color", hex)
                elt.find(".input-group-addon").css("background-color", hex)
                if not init
                    @command(@cm(), "background-color", hex)

            button_bar_input.change (ev) =>
                hex = button_bar_input.val()
                set(hex)

            button_bar_input.on "changeColor", (ev) =>
                hex = ev.color.toHex()
                set(hex)

            sample.click (ev) =>
                button_bar_input.colorpicker('show')

            set("#fff8bd", true)

        init_background_color_control()

    print: () =>
        if @_printing
            return
        @_printing = true
        @print_button.icon_spin(start:true, delay:0).addClass("disabled")
        @convert_to_pdf (err, output) =>
            @_printing = false
            @print_button.removeClass('disabled')
            @print_button.icon_spin(false)
            if err
                alert_message(type:"error", message:"Printing error -- #{err}")
            else
                salvus_client.read_file_from_project
                    project_id : @project_id
                    path       : output.filename
                    cb         : (err, mesg) =>
                        if err
                            cb(err)
                        else
                            url = mesg.url + "?nocache=#{Math.random()}"
                            window.open(url,'_blank')

    convert_to_pdf: (cb) =>  # cb(err, {stdout:?, stderr:?, filename:?})
        s = misc.path_split(@filename)
        target = s.tail + '.pdf'
        if @ext in ['md', 'html', 'rst', 'mediawiki']
            # pandoc --latex-engine=xelatex a.wiki -o a.pdf
            command = 'pandoc'
            args    = ['--latex-engine=xelatex', s.tail, '-o', target]
            bash = false
        else if @ext == 'tex'
            t = "." + misc.uuid()
            command = "mkdir -p #{t}; xelatex -output-directory=#{t} '#{s.tail}'; mv '#{t}/*.pdf' '#{target}'; rm -rf #{t}"
            bash = true

        target = @filename + ".pdf"
        output = undefined
        async.series([
            (cb) =>
                @save(cb)
            (cb) =>
                salvus_client.exec
                    project_id  : @project_id
                    command     : command
                    args        : args
                    err_on_exit : true
                    bash        : bash
                    path        : s.head
                    cb          : (err, o) =>
                        if err
                            cb(err)
                        else
                            output = o
                            cb()
        ], (err) =>
            if err
                cb?(err)
            else
                output.filename = @filename + ".pdf"
                cb?(undefined, output)
        )

    misspelled_words: (opts) =>
        opts = defaults opts,
            lang : undefined
            cb   : required
        if not opts.lang?
            opts.lang = misc_page.language()
        if opts.lang == 'disable'
            opts.cb(undefined,[])
            return
        if @ext == "html"
            mode = "html"
        else if @ext == "tex"
            mode = 'tex'
        else
            mode = 'none'
        #t0 = misc.mswalltime()
        salvus_client.exec
            project_id  : @project_id
            command     : "cat '#{@filename}'|aspell --mode=#{mode} --lang=#{opts.lang} list|sort|uniq"
            bash        : true
            err_on_exit : true
            cb          : (err, output) =>
                #console.log("spell_check time: #{misc.mswalltime(t0)}ms")
                if err
                    opts.cb(err); return
                if output.stderr
                    opts.cb(output.stderr); return
                opts.cb(undefined, output.stdout.slice(0,output.stdout.length-1).split('\n'))  # have to slice final \n

    spell_check: () =>
        @misspelled_words
            cb : (err, words) =>
                if err
                    return
                else
                    for cm in @source_editor.codemirrors()
                        cm.spellcheck_highlight(words)

    has_unsaved_changes: () =>
        return @source_editor.has_unsaved_changes()

    save: (cb) =>
        @source_editor.syncdoc.save (err) =>
            if not err
                @spell_check()
            cb?(err)

    sync: (cb) =>
        @source_editor.syncdoc.sync(cb)

    outside_tag: (line, i) ->
        left = line.slice(0,i)
        j = left.lastIndexOf('>')
        k = left.lastIndexOf('<')
        if k > j
            return k
        else
            return i

    file_path: () =>
        if not @_file_path?
            @_file_path = misc.path_split(@filename).head
        return @_file_path

    to_html: (cb) =>
        f = @["#{@ext}_to_html"]
        if f?
            f(cb)
        else
            @to_html_via_pandoc(cb:cb)

    html_to_html: (cb) =>   # cb(error, source)
        # add in cursor(s)
        source = @source_editor._get()
        cm = @source_editor.syncdoc.focused_codemirror()
        # figure out where pos is in the source and put HTML cursor there
        lines = source.split('\n')
        markers =
            cursor : "\uFE22"
            from   : "\uFE23"
            to     : "\uFE24"

        if @ext == 'html'
            for s in cm.listSelections()
                if s.empty()
                    # a single cursor
                    pos = s.head
                    line = lines[pos.line]
                    # FUTURE: for now, tags have to start/end on a single line
                    i = @outside_tag(line, pos.ch)
                    lines[pos.line] = line.slice(0,i)+markers.cursor+line.slice(i)
                else if false  # disable
                    # a selection range
                    to = s.to()
                    line = lines[to.line]
                    to.ch = @outside_tag(line, to.ch)
                    i = to.ch
                    lines[to.line] = line.slice(0,i) + markers.to + line.slice(i)

                    from = s.from()
                    line = lines[from.line]
                    from.ch = @outside_tag(line, from.ch)
                    i = from.ch
                    lines[from.line] = line.slice(0,i) + markers.from + line.slice(i)

        if @ext == 'html'
            # embed position data by putting invisible spans before each element.
            for i in [0...lines.length]
                line = lines[i]
                line2 = ''
                for j in [0...line.length]
                    if line[j] == "<"  # WARNING: worry about < in mathjax...
                        s = line.slice(0,j)
                        c = s.split(markers.cursor).length + s.split(markers.from).length + s.split(markers.to).length - 3  # OPTIMIZATION: ridiculously inefficient
                        line2 = "<span data-line=#{i} data-ch=#{j-c} class='smc-pos'></span>" + line.slice(j) + line2
                        line = line.slice(0,j)
                lines[i] = "<span data-line=#{i} data-ch=0 class='smc-pos'></span>"+line + line2

        source = lines.join('\n')

        source = misc.replace_all(source, markers.cursor, "<span class='smc-html-cursor'></span>")

        # add smc-html-selection class to everything that is selected
        # WARNING: this will *only* work when there is one range selection!!
        i = source.indexOf(markers.from)
        j = source.indexOf(markers.to)
        if i != -1 and j != -1
            elt = $("<span>")
            elt.html(source.slice(i+1,j))
            elt.find('*').addClass('smc-html-selection')
            source = source.slice(0,i) + "<span class='smc-html-selection'>" + elt.html() + "</span>" + source.slice(j+1)

        cb(undefined, source)

    md_to_html: (cb) =>
        source = @source_editor._get()
        m = require('../markdown').markdown_to_html(source)
        cb(undefined, m.s)

    rst_to_html: (cb) =>
        @to_html_via_exec
            command     : "rst2html"
            args        : [@filename]
            cb          : cb

    to_html_via_pandoc: (opts) =>
        opts.command = "pandoc"
        opts.args = ["--toc", "-t", "html", '--highlight-style', 'pygments', @filename]
        @to_html_via_exec(opts)

    to_html_via_exec: (opts) =>
        opts = defaults opts,
            command     : required
            args        : required
            postprocess : undefined
            cb          : required   # cb(error, html, warnings)
        html = undefined
        warnings = undefined
        async.series([
            (cb) =>
                @save(cb)
            (cb) =>
                salvus_client.exec
                    project_id  : @project_id
                    command     : opts.command
                    args        : opts.args
                    err_on_exit : false
                    cb          : (err, output) =>
                        #console.log("salvus_client.exec ", err, output)
                        if err
                            cb(err)
                        else
                            html = output.stdout
                            warnings = output.stderr
                            cb()
        ], (err) =>
            if err
                opts.cb(err)
            else
                if opts.postprocess?
                    html = opts.postprocess(html)
                opts.cb(undefined, html, warnings)
        )

    update_preview: () =>
        if @disable_preview
            return

        if @_update_preview_lock
            @_update_preview_redo = true
            return

        t0 = misc.mswalltime()
        @_update_preview_lock = true
        #console.log("update_preview")
        @to_html (err, source) =>
            @_update_preview_lock = false
            if err
                console.log("failed to render preview: #{err}")
                return

            # remove any javascript and make html more sane
            elt = $("<span>").html(source)
            elt.find('script').remove()
            elt.find('link').remove()
            source = elt.html()

            # finally set html in the live DOM
            @preview_content.html(source)

            @localize_image_links(@preview_content)

            ## this would disable clickable links...
            #@preview.find("a").click () =>
            #    return false
            # Make it so preview links can be clicked, don't close SMC page.
            @preview_content.find("a").attr("target","_blank")
            @preview_content.find("table").addClass('table')  # bootstrap table

            @preview_content.mathjax()

            #@preview_content.find(".smc-html-cursor").scrollintoview()
            #@preview_content.find(".smc-html-cursor").remove()

            #console.log("update_preview time=#{misc.mswalltime(t0)}ms")
            if @_update_preview_redo
                @_update_preview_redo = false
                @update_preview()

    localize_image_links: (e) =>
        # make relative links to images use the raw server
        for x in e.find("img")
            y = $(x)
            src = y.attr('src')
            if not src? or src[0] == '/' or src.indexOf('://') != -1
                continue
            new_src = "/#{@project_id}/raw/#{@file_path()}/#{src}"
            y.attr('src', new_src)
        # make relative links to objects use the raw server
        for x in e.find("object")
            y = $(x)
            src = y.attr('data')
            if not src? or src[0] == '/' or src.indexOf('://') != -1
                continue
            new_src = "/#{@project_id}/raw/#{@file_path()}/#{src}"
            y.attr('data', new_src)

    init_preview_select: () =>
        @preview_content.click (evt) =>
            sel = window.getSelection()
            if @ext=='html'
                p = $(evt.target).prevAll(".smc-pos:first")
            else
                p = $(evt.target).nextAll(".smc-pos:first")

            #console.log("evt.target after ", p)
            if p.length == 0
                if @ext=='html'
                    p = $(sel.anchorNode).prevAll(".smc-pos:first")
                else
                    p = $(sel.anchorNode).nextAll(".smc-pos:first")
                #console.log("anchorNode after ", p)
            if p.length == 0
                console.log("clicked but not able to determine position")
                return
            pos = p.data()
            #console.log("p.data=#{misc.to_json(pos)}, focusOffset=#{sel.focusOffset}")
            if not pos?
                pos = {ch:0, line:0}
            pos = {ch:pos.ch + sel.focusOffset, line:pos.line}
            #console.log("clicked on ", pos)
            @cm().setCursor(pos)
            @cm().scrollIntoView(pos.line)
            @cm().focus()

    _get: () =>
        return @source_editor._get()

    _set: (content) =>
        @source_editor._set(content)

    _show: (opts={}) =>
        if not @_split_pos?
            @_split_pos = .5
        @_split_pos = Math.max(editor.MIN_SPLIT, Math.min(editor.MAX_SPLIT, @_split_pos))
        @element.css(left:0, top: redux.getProjectStore(@project_id).get('editor_top_position'), position:'fixed')
        @element.width($(window).width())

        width = @element.width()
        chat_pos = @element.find(".salvus-editor-codemirror-chat").offset()
        if chat_pos.left
            width = chat_pos.left

        {top, left} = @element.offset()
        editor_width = (width - left)*@_split_pos

        @_dragbar.css('left',editor_width+left)

        # console.log("@source_editor.show: top=#{top} + @edit_buttons.height()=#{@edit_buttons.height()}")

        @source_editor.show
            width : editor_width
            top   : top + @edit_buttons.height()

        button_bar_height = @element.find(".salvus-editor-codemirror-button-container").height()
        @element.maxheight(offset:button_bar_height)
        @preview.maxheight(offset:button_bar_height)

        @_dragbar.height(@source_editor.element.height())
        @_dragbar.offset(top: @source_editor.element.offset() + button_bar_height)
        @_dragbar.css('top', "#{@edit_buttons.height() + button_bar_height + 9}px") # +9 is not good

        # position the preview
        @preview.offset
            top: @source_editor.element.offset() + button_bar_height

        @preview.css
            left  : editor_width + left + 7
            width : width - (editor_width + left + 7)
            top   : "#{@edit_buttons.height() + button_bar_height + 15}px"

        @preview.scrollTop(@preview_scroll_position)

    focus: () =>
        @source_editor?.focus()
