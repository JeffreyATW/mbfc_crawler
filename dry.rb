module DRY
  class << self
    # This sets up a simple cache so the result of the wombat crawl is saved.
    def mech_cache(db)
      proc {
        @mechanize.pluggable_parser['cache+text/html'] = CachedPage

        @mechanize.pre_connect_hooks << lambda do |agent, request|
          agent.context.cache_key = nil

          if request.is_a?(Net::HTTP::Get)
            agent.context.cache_key = request['host'] + request.path
            if cached = db.get(agent.context.cache_key)
              cached = agent.context.cached = YAML.load(cached)
              request['If-Modified-Since'] = cached[:headers][:'last-modified']
            end
          end
        end

        @mechanize.post_connect_hooks << lambda do |agent, uri, response, body|
          begin
            if response.code == "200"
              ok = response.dup
              ok.body = body
              db.put(agent.context.cache_key, {
                resp: ok,
                headers: response.to_hash.symbolize_keys,
              }.to_yaml)
            elsif response.code == "304"
              p "Using cached body for #{agent.context.cache_key}"
              #agent.context.watch_for_set = agent.context.cached
              response['content-type'] = 'cache+text/html'
            end
          end
        end
      }
    end

    def source_dsl
      proc {
        id({ xpath: '//article/@id' }) do |i|
          /page-([0-9]+)/.match(i)[1]
        end

        name({ css: 'article.page > h1.page-title' })

        notes({ xpath: '//div[contains(@class, "entry-content")]' }) do |n|
          return '' if n.nil?
          notes_index = n.index(/notes:/i)
          if notes_index.nil?
            history_index = n.index(/\nhistory\n/i)
            source_index = n.index(/\nsource:/i)
            p "history_index: #{history_index}"
            p "source_index: #{source_index}"
            result = history_index.nil? ? '' : n[history_index, source_index].strip
          else
            sub = n[notes_index + 6, n.length]
            eol_index = sub.index(/\n/)
            if eol_index.nil?
              eol_index = sub.length
            end
            p "notes_index: #{notes_index}"
            p "eol_index: #{eol_index}"
            result = sub[0, eol_index].strip
          end
          result
        end

        homepage({ xpath: '//div[contains(@class, "entry-content")]//p[text()[starts-with(.,"Sourc")]]/a[@target="_blank"]/@href'})

        domain({ xpath: '//div[contains(@class, "entry")]//p[text()[starts-with(.,"Sourc")]]/a[@target="_blank"]/@href'}) do |d|
          # remove www, www2, etc.
          d.nil? ? '' : URI(d).host.sub(/^www[0-9]*\./, '')
        end

        thepath({ xpath: '//div[contains(@class, "entry")]//p[text()[starts-with(.,"Sourc")]]/a/@href'}) do |p|
          # remove trailing (but not leading) slash
          p.nil? ? '' : URI(p).path.sub(/(.+)\/$/, '\1')
        end

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
      }
    end
  end
end
