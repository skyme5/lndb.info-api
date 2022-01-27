#!/usr/bin/ruby
# frozen_string_literal: true

# @Author: Aakash Gajjar
# @Date:   2019-10-06 12:25:27
# @Last Modified by:   Sky
# @Last Modified time: 2019-10-08 22:54:35

require 'mechanize'
require 'nokogiri'
require 'open-uri'
require 'tty-logger'

# Return search results from INDB.info
#
# @param config
#
class Search
  def initialize(config)
    @logger = TTY::Logger.new
    @config = config
  end

  def log_i(txt)
    @logger.info('LNDBSearch', txt)
  end

  def log(txt)
    @logger.debug('LNDBSearch', txt)
  end

  def get_query(query, char = '+')
    query.split.join(char)
  end

  def get_search_page_url(query)
    [@config[:base_url],
     @config[:search][:page],
     get_query(query)].join('')
  end

  def get_search_all_url(query)
    [@config[:base_url],
     @config[:search][:all],
     get_query(query)].join('')
  end

  def get_page(url)
    log(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri)
    request['Cookie'] = @config[:cookie]
    request['Host'] = @config[:host]
    request['User-Agent'] = @config[:user_agent]
    http.request(request).body
  end

  def get_results(page)
    selector = @config[:search][:results]
    doc = Nokogiri::HTML.parse(page)
    results = doc.css(selector).to_a

    results.map! do |link|
      text = link.text
      url = link['href']
      { url: url, text: text }
    end

    results.sort_by { |k| k[:text] }
  end

  def search_page(search_query)
    url = get_search_page_url(search_query)
    page = get_page(url)
    results = get_results(page)

    { results: results, success: true, count: results.length }
  end

  def search_all(search_query)
    url = get_search_all_url(search_query)
    page = get_page(url)
    results = JSON.parse(page, symbolize_names: true).map do |result|
      { label: result[:label], category: result[:category],
        url: [@config[:base_url], get_query(result[:category].downcase, '_'),
              get_query(result[:label], '_')].join('/') }
    end

    { results: results, success: true, count: results.length }
  end
end
