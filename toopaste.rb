#!/usr/local/bin/ruby -rubygems


require 'sinatra'
require 'toopaste.config'
require 'dm-core'
require 'dm-validations'
require 'dm-timestamps'
require 'dm-migrations'
require 'dm-types'
require 'haml'
require 'sass'
require 'uv'
require 'rack-flash'
require 'facets/time'
require 'drb' if settings.announce_irc[:active]

configure do
  use Rack::Flash
  enable :sessions
end

helpers do
  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
      throw(:halt, [401, "Y U NO AUTHENTICATE?\n"])
    end
  end

  def authorized?
    @auth ||= Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == ['admin', settings.adminpass]
  end

  def base_url
    @base_url ||= "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
  end
end

# setup constants for supported languages and themes, in ultraviolet they are 
# called syntax_name and render_style. In order to access the Textpow objects
# that include pretty names for each supported syntax file we need to extend
# the ultraviolet module because it does not provide an accessor:
module Uv
  def Uv.get_syntaxes
    @syntaxes
  end
end
languages = {}
Uv.init_syntaxes unless Uv.get_syntaxes
Uv.get_syntaxes.each do |syntax|
  languages[syntax.first] = syntax[1].name
end
LANGUAGES = languages
THEMES = Uv.themes

# the default location of sinatra for static files is ./public, this
# creates the directory for ultraviolet and copies the theme stylesheets.
# the other solution would be to copy the files in the repo.
uv_path = File.join(File.dirname(__FILE__), 'public', 'ultraviolet')
if not File.exists? uv_path
  Dir.mkdir(uv_path)
  Uv.copy_files('xhtml', uv_path)
end

DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/toopaste.db")

class Snippet
  include DataMapper::Resource

  property :random_id,  String,    :key => true
  property :title,      String
  property :language,   String
  property :author,     String
  property :visibility, Enum[:public, :private], :default => :public
  property :body,       Text,      :required => true
  property :delete_at,  DateTime
  property :created_at, DateTime
  property :updated_at, DateTime

  def title
    if not @title.empty?
      @title
    else
      "##{@random_id}"
    end
  end

  # make sure the accessed language is supported by ultraviolet
  def language
    if LANGUAGES.keys.include? @language
      return @language
    else
      return 'plain_text'
    end
  end

  def filename
    safe_title = 'toopaste-' + title.gsub(/[^\w\-\.]/,'')
    Uv.get_syntaxes.each do |syntax|
      if syntax.first == @language and not syntax[1].fileTypes.empty?
        return "#{safe_title}.#{syntax[1].fileTypes.first}"
      end
    end
    return "#{safe_title}.txt"
  end
end

DataMapper.finalize
DataMapper.auto_upgrade!

# stylesheet
get '/stylesheet.css' do
    scss :stylesheet, :style => :compact
end

# new
get '/' do
  @preferred_languages = settings.preferred_languages
  @snippets = Snippet.all(:visibility => 'public', :order => [:created_at.desc], :limit => settings.snippets_in_sidebar_count)
  if session.has_key? :author
    @author = session[:author]
  end
  haml :new
end

# create
post '/' do
  if LANGUAGES.keys.include? params[:snippet_language]
    language = params[:snippet_language]
  else
    language = 'plain_text'
  end

  delete_at = Time.now.shift(params[:snippet_delete_at].to_i, params[:snippet_delete_at_unit].to_sym) unless params[:snippet_delete_at].empty?
  session[:author] = params[:snippet_author]
  visibility = params[:snippet_visibility] || 'public'

  o = [('a'..'z'),('0'..'9')].map{|i| i.to_a}.flatten
  begin random_id = (0..3).map{ o[rand(o.length)] }.join end until not Snippet.get(random_id)

  @snippet = Snippet.new(:title => params[:snippet_title],
                         :language => language,
                         :body  => params[:snippet_body],
                         :author => params[:snippet_author],
                         :visibility => visibility,
                         :delete_at => delete_at,
                         :random_id => random_id
                        )

  if @snippet.save
    if settings.announce_irc and params.has_key? 'announce_irc'
      announce = 'new toopaste snippet'
      if params[:snippet_author] and not params[:snippet_author].empty?
        announce += " by #{params[:snippet_author]}"
      end
      if params[:snippet_title] and not params[:snippet_title].empty?
        announce += ": #{params[:snippet_title]}"
      end
      announce += " #{base_url}/#{@snippet.random_id}"

      drb = DRbObject.new_with_uri(settings.announce_irc[:uri])
      random_id = drb.delegate(nil, "remote login #{settings.announce_irc[:user]} #{settings.announce_irc[:pass]}")[:return]
      drb.delegate(random_id, "dispatch say #{settings.announce_irc[:channel]} #{announce}")
    end

    redirect "/#{@snippet.random_id}"
  else
    flash[:error] = "<strong>Uh-oh, something went wrong:</strong><br />"
    @snippet.errors.each { |e| flash[:error] += e.to_s + ".<br />" }
    redirect '/'
  end
end

# show
get %r{/(raw|download)?/?([a-z0-9]+)} do # '/:random_id' do
  raw = true if (params[:captures][0] and params[:captures][0] == 'raw') or request.user_agent.match /^curl\// 
  download = true if params[:captures][0] and params[:captures][0] == 'download'
  random_id = params[:captures][1]

  @snippet = Snippet.get(random_id)
  if @snippet
    delete_at = Time.parse(@snippet.delete_at.to_s)
    if delete_at.past? and not @snippet.delete_at.nil?
      @snippet.destroy
      raise not_found
    end

    if raw or download
      disposition = 'inline'
      disposition = 'attachment' if download

      content_type 'text/plain'
      headers['Content-Disposition'] = "#{disposition}; filename=\"#{@snippet.filename}\""
      return @snippet.body
    end

    # active theme (render_style)
    if session.has_key? :active_theme 
      # user selected theme saved in cookie
      @active_theme = session[:active_theme]  
    else
      @active_theme = settings.default_theme
    end

    @content = Uv.parse(@snippet.body, 'xhtml', @snippet.language, true, @active_theme)

    @title = "#{@snippet.title} | #{settings.pagetitle}"

    haml :show
  else
    raise not_found
  end
end

# switch active theme
post '/switch_theme' do
  if THEMES.include? params[:theme]
    session[:active_theme] = params[:theme]
  end
  redirect to("/#{params[:snippet_random_id]}")
end

# delete snippet
delete '/:random_id' do
  protected!
  snippet = Snippet.get(params[:random_id])
  if snippet.destroy
    "snippet ##{params[:random_id]} won't be a problem anymore, sir."
  else
    "snippet ##{params[:random_id]} is in another castle."
  end
end

# 404
not_found do
  haml :error404
end

# 403
error 403 do
  haml :error403
end

# other errors
error do
  haml :error500
end

