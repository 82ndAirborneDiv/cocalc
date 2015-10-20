###
Webpack configuration file

Run dev server with source maps:

    npm run webpack-watch

Then visit (say)

    https://dev0.sagemath.com/static/webpack.html

This is far from ready to use yet, e.g., we need to properly serve primus websockets, etc.:

    webpack-dev-server --port=9000 -d

Resources for learning webpack:

    - https://github.com/petehunt/webpack-howto
    - http://webpack.github.io/docs/tutorials/getting-started/

###

webpack      = require('webpack')
path         = require('path')

module.exports =
    entry:
        landing : './page/landing.coffee'
        client  : './client_browser.coffee'
        vendors : ['react', 'async', 'events', 'marked', 'flummox', 'react-timeago', 'react-bootstrap',
                   'sha1', 'underscore', 'immutable', 'react-dropzone-component', 'jquery.payment',
                   'react-widgets/lib/Combobox', 'react-widgets/lib/DateTimePicker', 'md5',
                   './page/codemirror/codemirror.coffee'
                  ]

    output:
        path       : path.resolve(__dirname, 'static/webpack/')
        publicPath : "/static/webpack/"
        filename   : '[name].js'

    module:
        loaders: [
            { test: /\.css$/,    loader: 'style!css' },
            { test: /\.cjsx$/,   loaders: ['coffee', 'cjsx'] },
            { test: /\.coffee$/, loader: 'coffee-loader' },
            { test: /\.sass$/,   loaders: ["style", "css", "sass?indentedSyntax"]},  # https://github.com/jtangelder/sass-loader
            { test: /\.json$/,   loaders: ['json'] },
            { test: /\.png$/,    loader: "url-loader?limit=100000" },
            { test: /\.jpg$/,    loader: "file-loader"},
            { test: /\.html$/,   loader: "html-loader"}
        ]

    resolve:
        # So we can require('file') instead of require('file.coffee')
        extensions : ['', '.js', '.json', '.coffee', '.cjsx']
        root: [path.resolve('.'), path.resolve('node_modules'), path.resolve('page')]

    plugins: [
        new webpack.optimize.CommonsChunkPlugin('vendors', 'vendors.js')
    ]

