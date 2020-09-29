FROM ruby:2.7-alpine

COPY LICENSE.md README.md /

COPY Gemfile Gemfile.lock /
RUN bundle install -j 8

COPY entrypoint.rb /entrypoint.rb
RUN chmod +x /entrypoint.rb

ENTRYPOINT ["/entrypoint.rb"]
