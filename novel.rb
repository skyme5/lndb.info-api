#!/usr/bin/ruby
# frozen_string_literal: true

# @Author: Aakash Gajjar
# @Date:   2019-10-06 12:25:27
# @Last Modified by:   Sky
# @Last Modified time: 2019-10-08 23:28:27

require 'mechanize'
require 'nokogiri'
require 'open-uri'
require 'tty-logger'

# Return novel list from INDB.info
#
class Novel
  def initialize(config)
    @logger = TTY::Logger.new do |config|
      config.level = :debug # or "INFO" or TTY::Logger::INFO_LEVEL
    end
    @config = config
    @config_selectors = @config[:light_novel][:selectors]
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

  def get_page(url)
    log(url)
    begin
        uri = URI.parse(url)
    rescue
        uri = URI.parse(URI.escape(url))
    end
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri)
    request['Cookie'] = @config[:cookie]
    request['Host'] = @config[:host]
    request['User-Agent'] = @config[:user_agent]
    request['Referer'] = url.gsub('/light_novel/view/', '/light_novel/')
    http.request(request).body.to_s
  end

  def extract_side_info(doc, selector)
    doc.css(selector[:info]).to_a.map! do |field|
      td = field.css(selector[:info_list]).map { |e| e.text.strip }
      links = field.css(selector[:info_list]).last.css('a').map do |a|
        { text: a.text, url: a['href'] }
      end

      { name: td[0], value: links.empty? ? td[1] : links }
    end
  end

  def extract_volume_info(doc)
    doc.css(@config_selectors[:volumes]).to_a.map do |field|
      volume_url = field['href']
      # volume_page = Nokogiri::HTML.parse(open(volume_url))
      volume_page = Nokogiri::HTML.parse(get_page(volume_url))
      cover_url = volume_page.css(@config[:volume][:cover])[1]['src']
      side_info = extract_side_info(volume_page, @config[:volume])

      { url: volume_url, coverUrl: cover_url, info: side_info }
    end
  end

  def extract_info(page)
    doc = Nokogiri::HTML::DocumentFragment.parse(page)
    title = doc.css(@config_selectors[:title]).text.strip
    cover_url = doc.css(@config_selectors[:cover]).to_a.last

    info = extract_side_info(doc, @config_selectors)
    volumes = extract_volume_info(doc)
    { title: title, 
    coverUrl: @config[:host] + cover_url['src'], 
    info: info,
      volumes: volumes }
  end

  def get_novel(novel)
    page = get_page(novel[:url].gsub('/light_novel/', '/light_novel/view/'))
    info = extract_info(page)

    info
  end
end
