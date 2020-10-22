FROM ruby:2.7-alpine

RUN apk --update add --no-cache --virtual run-dependencies build-base git

COPY LICENSE.md README.md /

RUN git clone --depth 1 https://github.com/Homebrew/brew Homebrew

COPY Gemfile /
RUN bundle install -j 8

COPY entrypoint.rb /
RUN chmod +x /entrypoint.rb

ENTRYPOINT ["/entrypoint.rb"]
