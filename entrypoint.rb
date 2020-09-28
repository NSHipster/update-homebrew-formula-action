#!/usr/bin/env ruby

require 'bundler'
Bundler.require

require 'optparse'
require 'logger'
require 'digest'
require 'base64'

logger = Logger.new(STDOUT)
logger.level = Logger::WARN

options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: entrypoint.rb [options]'

  opts.on('-r ', '--repository REPOSITORY', 'The project repository (e.g. mona/hello)') do |repository|
    options[:repository] = repository
  end

  opts.on('-t', '--tap REPOSITORY', 'The Homebrew tap repository (e.g. mona/homebrew-formulae)') do |repository|
    options[:tap] = repository
  end

  opts.on('-f', '--formula PATH', 'The path to the formula in the tap repository (e.g. Formula/hello.rb)') do |path|
    options[:formula] = path
  end

  opts.on_tail('-v', '--verbose', 'Output more information') do
    logger.level = Logger::DEBUG
  end

  opts.on_tail('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end
end.parse!

raise 'GITHUB_TOKEN environment variable is not set' unless ENV['GITHUB_TOKEN']

raise 'missing argument: -r/--repository' unless options[:repository]
raise 'missing argument: -t/--tap' unless options[:tap]
raise 'missing argument: -f/--formula' unless options[:formula]

Octokit.middleware = Faraday::RackBuilder.new do |builder|
  builder.use Faraday::Request::Retry, exceptions: [Octokit::ServerError]
  builder.use Octokit::Middleware::FollowRedirects
  builder.use Octokit::Response::RaiseError
  builder.use Octokit::Response::FeedParser
  builder.response :logger, logger
  builder.adapter Faraday.default_adapter
end

client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])
repo = client.repo(options[:repository])

releases = repo.rels[:releases].get.data

exit unless latest_release = releases.first

tags = repo.rels[:tags].get.data
exit unless tag = tags.find { |t| t.name == latest_release.tag_name }

PATTERN = /#{Regexp.quote(repo.name)}-#{Regexp.quote(latest_release.tag_name)}\.(?<platform>[^.]+)\.bottle\.tar\.gz/.freeze

assets = {}
latest_release.assets.each do |asset|
  next unless matches = asset.name.match(PATTERN)
  next unless platform = matches[:platform]

  assets[platform] = Digest::SHA256.hexdigest(client.get(asset.browser_download_url))
end

tap = client.repo(options[:tap])

blob = client.contents(options[:tap], path: options[:formula])
formula = Base64.decode64(blob.content)

buffer = Parser::Source::Buffer.new(formula, 1, source: formula)
builder = RuboCop::AST::Builder.new
ast = Parser::CurrentRuby.new(builder).parse(buffer)
rewriter = Parser::Source::TreeRewriter.new(buffer)

rewriter.transaction do
  if url = ast.descendants.find { |d| d.send_type? && d.method_name == :url }
    rewriter.replace url.loc.expression, %(url "#{repo.clone_url}", tag: "#{latest_release.tag_name}", revision: "#{tag.commit.sha}")
  end

  if bottle = ast.descendants.find { |d| d.block_type? && d.send_node&.method_name == :bottle }
    if assets.empty?
      rewriter.replace bottle.loc.expression, ''
    else
      root_url = "https://github.com/#{repo.owner.login}/#{repo.name}/releases/download/#{latest_release.tag_name}"

      bottles = assets.map do |platform, checksum|
        %(sha256 "#{checksum}" => :#{platform})
      end

      rewriter.replace bottle.loc.expression, <<~RUBY
        bottle do
            root_url "#{root_url}"
            #{bottles.join("\n")}
        end

      RUBY
    end
  end
end

client.update_contents(options[:tap],
                       options[:formula],
                       "Update #{repo.name} to #{latest_release.tag_name}",
                       blob.sha,
                       rewriter.process)
