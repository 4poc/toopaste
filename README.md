Geekpaste
=========

Pastebin forked from [zapnap](https://github.com/zapnap/toopaste) to play with Sinatra.
Live Demo: [paste.geekosphere.org](http://paste.geekosphere.org)


Features:
---------

* Optionally limited snippet retention
* Randomly generated ids (36^4 possibilities)
* Option to post private (unlisted) snippets
* Announcing of new snippets to an IRC bot ([4poc](https://github.com/4poc))
* Include ultraviolet styles, switchable ([4poc](https://github.com/4poc))
* Change password in config, then delete snippets from the cli with

        curl -u <user>:<password> -X DELETE http://<domain>.<tld>/<snippetid>


Install:
--------

* git clone
* cd toopaste
* examine and trust .rvmrc (if you're not using [rvm](http://rvm.beginrescueend.com) yet: you should)
* gem install bundler
* bundle install
* cp toopaste.config.sample.rb toopaste.config.rb and edit it to your liking
* run with ruby toopaste.rb


Heroku Deployment:
------------------

* add dm-postgres-adapter to Gemfile and toopaste.rb
* don't forget to add the config to the repository


TODO:
-----

* tags
* line wrapping?
* spam protection
