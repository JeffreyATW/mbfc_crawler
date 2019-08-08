#!/usr/bin/env ruby

require 'wombat'
require 'json'
require 'leveldb'
require './dry'

base = 'https://mediabiasfactcheck.com'

biases = {}

if ARGV[0].nil?
  directory = 'output'
  unless File.directory?('output')
    Dir.mkdir('output')
  end
else
  directory = ARGV[0]
end
Dir.chdir(directory)

db = LevelDB::DB.new('cache')

# (shrug)
class Mechanize
  attr_accessor :cache_key
  attr_accessor :cached
end

class Hash
  def symbolize_keys
    inject({}) do |memo,(k,v)|
      memo[k.to_sym] = v
      memo
    end
  end
end

# When the response is cached we use the cache+text/html parser (an instance of
# this class), which pulls the body out of the side channel and runs the regular
# parser.
class CachedPage < Mechanize::Page
  def initialize(uri=nil, response=nil, body=nil, code=nil, mech=nil)
    yield self if block_given?
    @uri = uri
    @response = @mech.cached[:resp]
    @body = @mech.cached[:resp].body
    @code = @mech.cached[:resp].code
    super @uri, @response, @body, @code
  end
end

%w(left leftcenter center right-center right pro-science conspiracy satire fake-news).each do |p|
  begin
    bias = Wombat.crawl do
      base_url base
      path "/#{p}/"

      name({ css: '.page > h1.page-title' })
      description({ css: '.entry > *:nth-child(2)' }) do |d|
        d.sub(/see also:/i, '').strip
      end
      url "#{base}/#{p}/"
      # for some kind of bias, they are in a table-container
      source_urls({ xpath: '//*/div[contains(@class, "entry")]/p/a/@href | //*/table[@id="mbfc-table"]//tr/td/a/@href' }, :list)
    end

    puts "Bias crawled: #{bias['name']}"

    biases[p] = bias
  rescue Exception => e
    puts "Could not crawl bias: #{p}"
    puts e.backtrace
  end
end

sources = {}
source_ids = []

biases.each do |k, b|
  b['source_urls'].each do |u|
    source_uri = URI(u)

    begin
      source = Wombat.crawl do
        # There's probably a better way to dry it out
        instance_eval &DRY.mech_cache(db)

        base_url base
        path source_uri.path

        # share these DSL rules between here and tests
        instance_eval &DRY.source_dsl
        url "#{source_uri.scheme}://#{source_uri.host}#{source_uri.path}"
      end

      source['bias'] = k

      unless (source_ids.include?(source['id']) || source['domain'] == '')
        domain = source['domain']
        source.delete('domain')

        source['path'] = source['thepath']
        source.delete('thepath')

        if (sources[domain].nil?)
          sources[domain] = [source]
        else
          sources[domain] << source
        end

        source_ids << source['id']
        puts "Source crawled: #{source['name']}"
      end
    rescue Exception => e
      puts "Could not crawl source: #{source_uri}"
      puts e.backtrace
    end
  end

  b.delete('source_urls')
end

if (biases.count > 0)
  File.open("biases.json", "w") do |f|
    f.write(biases.to_json)
  end
else
  puts "No biases to write."
end

if (sources.count > 0)
  File.open("sources.json", "w") do |f|
    f.write(sources.to_json)
  end
else
  puts "No sources to write."
end
