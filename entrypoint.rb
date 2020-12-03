#!/usr/bin/env ruby

# frozen_string_literal: true

require "bundler"
Bundler.require

require "base64"
require "digest"
require "logger"
require "optparse"
require "tempfile"

logger = Logger.new($stdout)
logger.level = Logger::WARN

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: entrypoint.rb [options]"

  opts.on("-r ", "--repository REPOSITORY", "The project repository") do |repository|
    options[:repository] = repository
  end

  opts.on("-t", "--tap REPOSITORY", "The Homebrew tap repository") do |repository|
    options[:tap] = repository
  end

  opts.on("-f", "--formula PATH", "The path to the formula in the tap repository") do |path|
    options[:formula] = path
  end

  opts.on("-m", "--message MESSAGE", "The message of the commit updating the formula") do |message|
    options[:message] = message
  end

  opts.on_tail("-v", "--verbose", "Output more information") do
    logger.level = Logger::DEBUG
  end

  opts.on_tail("-h", "--help", "Display this screen") do
    puts opts
    exit 0
  end
end.parse!

begin
  raise "GH_PERSONAL_ACCESS_TOKEN environment variable is not set" unless ENV["GH_PERSONAL_ACCESS_TOKEN"]

  raise "missing argument: -r/--repository" unless options[:repository]
  raise "missing argument: -t/--tap" unless options[:tap]
  raise "missing argument: -f/--formula" unless options[:formula]

  Octokit.middleware = Faraday::RackBuilder.new do |builder|
    builder.use Faraday::Request::Retry, exceptions: [Octokit::ServerError]
    builder.use Octokit::Middleware::FollowRedirects
    builder.use Octokit::Response::RaiseError
    builder.use Octokit::Response::FeedParser
    builder.response :logger, logger, log_level: :debug do |logger|
      logger.filter(/(Authorization\: )(.+)/, '\1[REDACTED]')
    end
    builder.adapter Faraday.default_adapter
  end

  client = Octokit::Client.new(access_token: ENV["GH_PERSONAL_ACCESS_TOKEN"])
  repo = client.repo(options[:repository])

  releases = repo.rels[:releases].get.data
  raise "No releases found" unless (latest_release = releases.first)

  tags = repo.rels[:tags].get.data
  unless (tag = tags.find { |t| t.name == latest_release.tag_name })
    raise "Tag #{latest_release.tag_name} not found"
  end

  PATTERN = /#{Regexp.quote(repo.name)}-#{Regexp.quote(latest_release.tag_name.delete_prefix("v"))}\.(?<platform>[^.]+)\.bottle\.tar\.gz/.freeze

  assets = {}
  latest_release.assets.each do |asset|
    next unless (matches = asset.name.match(PATTERN))
    next unless (platform = matches[:platform])

    assets[platform] = Digest::SHA256.hexdigest(client.get(asset.browser_download_url))
  end

  blob = client.contents(options[:tap], path: options[:formula])
  original_formula = Base64.decode64(blob.content)

  buffer = Parser::Source::Buffer.new(original_formula, 1, source: original_formula)
  builder = RuboCop::AST::Builder.new
  ast = Parser::CurrentRuby.new(builder).parse(buffer)
  rewriter = Parser::Source::TreeRewriter.new(buffer)

  rewriter.transaction do
    if (version = ast.descendants.find { |d| d.send_type? && d.method_name == :version })
      rewriter.replace version.loc.expression, %Q(version "#{latest_release.tag_name}")
    end

    if (url = ast.descendants.find { |d| d.send_type? && d.method_name == :url })
      rewriter.replace url.loc.expression, %Q(url "#{repo.clone_url}", tag: "#{latest_release.tag_name}", revision: "#{tag.commit.sha}")
    end

    if (bottle = ast.descendants.find { |d| d.block_type? && d.send_node&.method_name == :bottle })
      if assets.empty?
        rewriter.replace bottle.loc.expression, ""
      else
        root_url = "https://github.com/#{repo.owner.login}/#{repo.name}/releases/download/#{latest_release.tag_name}"

        bottles = assets.map do |platform, checksum|
          %Q(sha256 "#{checksum}" => :#{platform})
        end

        rewriter.replace bottle.loc.expression, <<~RUBY
          bottle do
              root_url "#{root_url}"
              cellar :any
          #{bottles.map { |s| "    #{s}" }.join("\n")}
            end
        RUBY
      end
    end
  end

  updated_formula = rewriter.process
  begin
    tempfile = Tempfile.new("#{repo.name}.rb")
    File.write tempfile, updated_formula

    logger.debug `rubocop -c Homebrew/Library/.rubocop.yml -x #{tempfile.path}`
    updated_formula = File.read(tempfile)
  ensure
    tempfile.close
    tempfile.unlink
  end

  logger.info updated_formula

  if original_formula == updated_formula
    logger.warn "Formula is up-to-date"
    exit 0
  else
    client.update_contents(options[:tap],
                           options[:formula],
                           "Update #{repo.name} to #{latest_release.tag_name}",
                           blob.sha,
                           updated_formula)
  end
rescue => e
  logger.fatal(e)
  exit 1
end
