FROM ruby:2.7-alpine

RUN apk --update add --no-cache --virtual run-dependencies build-base

COPY LICENSE.md README.md /

COPY Homebrew /Homebrew

COPY Gemfile /
RUN bundle install -j 8

COPY entrypoint.rb /
RUN chmod +x /entrypoint.rb

ENTRYPOINT ["/entrypoint.rb"]
