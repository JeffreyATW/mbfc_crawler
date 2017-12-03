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

%w(left leftcenter center right-center right pro-science conspiracy satire fake-news).each do |p|
  begin
    bias = Wombat.crawl do
      base_url base
      path "/#{p}/"

      name({ css: '.page > h1.page-title' })
      description({ css: '.entry > *:first-child' }) do |d|
        d.sub(/see also:/i, '').strip
      end
      url "#{base}/#{p}/"
      source_urls 'xpath=//*/div[contains(@class, "entry")]/*[position()=2]/a/@href', :list
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
        base_url base
        path source_uri.path

        id({ xpath: '//article/@id' }) do |i|
          /page-([0-9]+)/.match(i)[1]
        end
        name({ css: 'article.page > h1.page-title' })
        notes({ xpath: '//*[text()[contains(.,"Notes:")]]' }) do |n|
          n.nil? ? '' : n.sub(/notes:/i, '').strip
        end
        homepage({ xpath: '//div[contains(@class, "entry")]//p[text()[starts-with(.,"Sourc")]]/a/@href'})
        domain({ xpath: '//div[contains(@class, "entry")]//p[text()[starts-with(.,"Sourc")]]/a[@target="_blank"]/@href'}) do |d|
          # remove www, www2, etc.
          d.nil? ? '' : URI(d).host.sub(/^www[0-9]*\./, '')
        end
        thepath({ xpath: '//div[contains(@class, "entry")]//p[text()[starts-with(.,"Sourc")]]/a/@href'}) do |p|
          # remove trailing (but not leading) slash
          p.nil? ? '' : URI(p).path.sub(/(.+)\/$/, '\1')
        end
        url "#{source_uri.scheme}://#{source_uri.host}#{source_uri.path}"

        factual({ xpath: '//div[contains(@class, "entry-content") or contains(@class, "entry")]//p[text()[starts-with(.,"Factual")]]'}) do |f|
          f = '' if f.nil?
          f = f.gsub(/\p{Space}/u, ' ') # turn unicode space into ascii space
          f = f.upcase
          if mg = f.match(/\b((?:VERY )?(HIGH|LOW)|MIXED)\b/)
            f = mg[1]
          else
            f = ''
          end
          f
        end
      end

      source['bias'] = k

      unless (source_ids.include?(source['id']) ||
              source['domain'] == '')
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

File.open("biases.json", "w") do |f|
  f.write(biases.to_json)
end

File.open("sources.json", "w") do |f|
  f.write(sources.to_json)
end

