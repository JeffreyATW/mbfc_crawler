#!/usr/bin/env ruby

require 'wombat'
require 'json'

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

%w(left leftcenter center right-center right pro-science conspiracy satire).each do |p|
  bias = Wombat.crawl do
    base_url base
    path "/#{p}/"

    name({ css: '.page > .entry-header h1.entry-title' })
    description({ css: '.entry-content p:first-child' }) do |d|
      d.sub(/see also:/i, '').strip
    end
    url "#{base}/#{p}/"
    source_urls 'xpath=//*/div[@class="entry-content"]//p[position()=2]/a/@href', :list
  end

  puts "Bias crawled: #{bias['name']}"

  biases[p] = bias
end

sources = {}
source_ids = []
source_domains = []

biases.each do |k, b|
  b['source_urls'].each do |u|
    source_uri = URI(u)
    
    begin
      source = Wombat.crawl do
        base_url base
        path source_uri.path

        id({ xpath: '/html/body/@class' }) do |i|
          page_match = /page-id-([0-9]+)/.match(i)
          if page_match.nil?
            /postid-([0-9]+)/.match(i)[1]
          else
            page_match[1]
          end
        end
        name({ css: 'article > .entry-header h1.entry-title' })
        notes({ xpath: '//*[text()[contains(.,"Notes:")]]' }) do |n|
          n.nil? ? '' : n.sub(/notes:/i, '').strip
        end
        homepage({ xpath: '//*[text()[contains(.,"Source:")]]/a/@href'})
        domain({ xpath: '//*[text()[contains(.,"Source:")]]/a/@href'}) do |d|
          d.nil? ? '' : URI(d).host.sub(/^www\./, '')
        end
        url "#{source_uri.scheme}://#{source_uri.host}#{source_uri.path}"
      end

      source['bias'] = k

      unless (source_ids.include?(source['id']) ||
              source_domains.include?(source['domain']) ||
              source['domain'] == '')
        domain = source['domain']
        source.delete('domain')
        sources[domain] = source
        source_ids << source['id']
        source_domains << source['domains']

        puts "Source crawled: #{source['name']}"
      end
    rescue
      puts "Could not crawl #{source_uri}"
    end
  end

  b.delete('source_urls')
end

File.open("biases.json", "w") do |f|
  f.write(biases.to_json)
end

File.open("sources.json", "w") do |f|
  f.write(sources.to_json)
end