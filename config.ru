require 'rubygems'
require 'bundler'
require 'sinatra'
require 'toopaste'

Bundler.require
set :run => false

run Sinatra::Application
