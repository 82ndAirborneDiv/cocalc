###
SageMathCloud: A collaborative web-based interface to Sage, IPython, LaTeX and the Terminal.
Copyright (C) 2015, William Stein, GPL v3.
---

Site Customize -- dynamically customize the look of SMC for the client.
###


{Actions, Store, flux, Flux, rclass, rtypes, React} = require('./r')
{Loading} = require('./r_misc')

misc = require('smc-util/misc')

class CustomizeActions extends Actions
    setTo: (payload) ->
        return payload

    # email address that help emails go to
    set_help_email: (email) ->
        @setTo(help_email: email)

    # name that we call the site, e.g., "SageMathCloud"
    set_site_name: (site_name) ->
        @setTo(site_name: site_name)

    set_site_description: (site_description) ->
        @setTo(site_description: site_description)

    set_terms_of_service: (terms_of_service) ->
        @setTo(terms_of_service: terms_of_service)

    set_account_creation_email_instructions: (account_creation_email_instructions) ->
        @setTo(account_creation_email_instructions: account_creation_email_instructions)


actions = flux.createActions('customize', CustomizeActions)

# Define account store
class CustomizeStore extends Store
    constructor: (flux) ->
        super()
        ActionIds = flux.getActionIds('customize')
        @register(ActionIds.setTo, @setTo)

    setTo: (payload) ->
        @setState(payload)

store = flux.createStore('customize', CustomizeStore)

# initially set to defaults
actions.setTo(misc.dict( ([k, v.default] for k, v of require('smc-util/schema').site_settings_conf) ))

# If we are running in the browser, then we customize the schema.  This also gets run on the backend
# to generate static content, which can't be customized.
$?.get (window.smc_base_url + "/customize"), (obj, status) ->
    if status == 'success'
        actions.setTo(obj)

HelpEmailLink = rclass
    displayName : 'HelpEmailLink'
    propTypes :
        help_email : rtypes.string
        text : rtypes.string
    render : ->
        if @props.help_email
            <a href={"mailto:#{@props.help_email}"} target='_blank'>{@props.text ? @props.help_email}</a>
        else
            <Loading/>

exports.HelpEmailLink = rclass
    displayName : 'HelpEmailLink'
    propTypes :
        text : rtypes.string
    render      : ->
        <Flux flux={flux} connect_to={help_email:'customize'}>
            <HelpEmailLink text={@props.text} />
        </Flux>

SiteName = rclass
    displayName : 'SiteName'
    propTypes :
        site_name : rtypes.string
    render : ->
        if @props.site_name
            <span>{@props.site_name}</span>
        else
            <Loading/>

exports.SiteName = rclass
    displayName : 'SiteName'
    render      : ->
        <Flux flux={flux} connect_to={site_name:'customize'}>
            <SiteName />
        </Flux>

SiteDescription = rclass
    displayName : 'SiteDescription'
    propTypes :
        site_description : rtypes.string
    render : ->
        if @props.site_description?
            <span style={color:"#666", fontSize:'16px'}>{@props.site_description}</span>
        else
            <Loading/>

exports.SiteDescription = rclass
    displayName : 'SiteDescription'
    render      : ->
        <Flux flux={flux} connect_to={site_description:'customize'}>
            <SiteDescription />
        </Flux>

TermsOfService = rclass
    displayName : 'TermsOfService'

    propTypes :
        terms_of_service : rtypes.string
        style : rtypes.object

    render : ->
        if not @props.terms_of_service?
            return <div></div>
        return <div style={@props.style} dangerouslySetInnerHTML={__html: @props.terms_of_service}></div>

exports.TermsOfService = rclass
    displayName : 'TermsOfService'

    propTypes :
        style : rtypes.object

    render : ->
        <Flux flux={flux} connect_to={terms_of_service : 'customize'}>
            <TermsOfService style={@props.style} />
        </Flux>

AccountCreationEmailInstructions = rclass
    displayName : 'AccountCreationEmailInstructions'

    propTypes :
        account_creation_email_instructions : rtypes.string

    render : ->
        <h3 style={marginTop: 0, textAlign: 'center'} >{@props.account_creation_email_instructions}</h3>

exports.AccountCreationEmailInstructions = rclass
    displayName : 'AccountCreationEmailInstructions'

    render : ->
        <Flux flux={flux} connect_to={account_creation_email_instructions : 'customize'}>
            <AccountCreationEmailInstructions />
        </Flux>