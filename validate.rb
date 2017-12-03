#!/usr/bin/env ruby
require 'pp'
require 'yaml'

require 'leveldb'
require 'mechanize'
require 'wombat'

require './dry'

db = LevelDB::DB.new('./output/cache')

# Wombat docs are wrong. The dynamic class gets eval'd after the metadata is
# dup'd so we need to do this to set our cached response here.
class LocalCrawl
  include Wombat::Crawler

  def initialize(page)
    self.metadata.page page
    super()
  end
end

broken = Hash.new do |h, k|
  h[k] = []
end

foo = broken.dup

mech = Mechanize.new
db.each do |k, v|
  next if k == 'mediabiasfactcheck.com/' # ????
  r = YAML.load(v)
  page = Mechanize::Page.new(URI("http://"+k), r[:resp], r[:resp].body, r[:resp].code, mech)

  c = LocalCrawl.new(page).crawl do
    instance_eval &DRY.source_dsl

    url k

    bias({ xpath: 'string(//div[contains(@class, "entry")]//h1/text())'})
  end

  foo[c['bias']] << k

  # assert scraped 'factual' is a valid level of factualness
  broken['factual'] << [k, c['factual']] unless [
    '',
    'MIXED',
    'LOW',
    'HIGH',
    'VERY HIGH',
  ].include? c['factual']

  # We need to scrape the bias from the page because nil factualness is only
  # valid for the articles in the next assertion
  broken['bias'] << [k, c['bias']] unless [
    'CONSPIRACY-PSEUDOSCIENCE',
    'LEAST BIASED',
    'LEFT BIAS',
    'LEFT-CENTER BIAS',
    'PRO-SCIENCE',
    'QUESTIONABLE SOURCE',
    'RIGHT BIAS',
    'RIGHT-CENTER BIAS',
    'SATIRE',
  ].include? c['bias']

  # assert nil factuality for only clearly fake sources
  if c['factual'] == ''
    broken['factual'] << [k, c['factual']] unless [
      'CONSPIRACY-PSEUDOSCIENCE',
      'QUESTIONABLE SOURCE',
      'SATIRE',
    ].include? c['bias']
  end
end

foo.each do |k,v|
  p k, v.size
end

if broken.size > 0
  puts "Please fix the content (or scraper) for these pages"
  pp broken
  exit 1
else
  puts "Scraper valid"
  exit 0
end

db.close
