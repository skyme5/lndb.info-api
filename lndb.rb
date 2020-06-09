#!/usr/bin/ruby
# frozen_string_literal: true

# @Author: Aakash Gajjar
# @Date:   2019-10-06 12:24:54
# @Last Modified by:   Sky
# @Last Modified time: 2019-10-09 00:24:06

require 'json'
require 'digest'
require 'zlib'
require 'uri'
require 'net/http'
require 'net/https'

require 'lisbn'
require 'tty-prompt'
require 'tty-logger'

require_relative 'search'
require_relative 'novel'

$LOG = TTY::Logger.new

trap("INT") { exit(0) }

def normalize(text)
  text.split(%r{[:\?/\\<\">|*]+}).join(' - ').gsub(/[ ]+/, ' ')
end

def save_json(info, filepath)
  out = File.open("#{normalize(filepath)}.json", 'w+')
  out.print info.to_json
  out.close
end

def send_book(data)
  $LOG.info("submitting #{data['filepath']}")
  uri = URI.parse('https://127.0.0.1:3232/api/v2/book')
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path)
  request.add_field('Content-Type', 'application/json; charset=utf-8')
  request.body = data.to_json
  response = http.request(request)
  $LOG.info(response.body.force_encoding('UTF-8'))
  response.body.include? '{"success":true}'
end

def check_isbn(isbn_str)
  return { is_valid: false } if isbn_str.nil?
  isbn = Lisbn.new(isbn_str)
  if isbn.valid?
    {
      is_valid: isbn.valid?,
      isbn10: isbn.isbn10,
      isbn13: isbn.isbn13,
      isbn: isbn.isbn,
      isbn_pretty: Lisbn.new(isbn.isbn13).isbn_with_dash
    }
  else
    {
      is_valid: isbn.valid?
    }
  end
end

def rename_file(src, dst)
  system("rename \"#{src}\" \"#{dst}\"")
end

def map_choices(results)
  choices = {}
  results.each_with_index.map{ |e, i| choices[e[:text]] = i }
  choices['Not Found'] = -1
  choices
end

def select_novel(results)
  choices = map_choices(results)
  prompt = TTY::Prompt.new
  novel = prompt.select('Select Novel', choices, cycle: true)
  if novel < 0
    puts 'Novel not selected'
    search
  end

  results[novel]
end

def filter_key(list, key, value = nil)
  result = list.select do |field|
    (field[:name] == key) && (field[:value] == value) if !value.nil?
    field[:name] == key if value.nil?
  end
  result.first
end

def filter_volume(list, value)
  result = list.select do |e|
    volume = filter_key(e[:info], 'Volume')
    false if volume.nil?
    volume[:value].to_i == value.to_i if !volume.nil?
  end

  if result.first.nil?
    list[value.to_i - 1]
  else
    result.first
  end
end

def organize_files(info)
  files = Dir.entries('.')[2..-1].select do |e|
    ['.pdf'].include?(File.extname(e))
  end

  novel_title = info[:title]
  novel_author = filter_key(info[:info], 'Author')[:value].first[:text]

  files.each.with_index(1) do |file, index|
    file_extension = '.' + file.split('.').last
    filename = File.basename(file, file_extension)

    volume_info = filter_volume(info[:volumes], filename)
    next if volume_info.nil?

    volume_title = filter_key(volume_info[:info], 'Volume Title')[:value]
    # use index of file array as volume number
    volume_index = filter_key(volume_info[:info], 'Volume').nil? ? index : filter_key(volume_info[:info], 'Volume')[:value]

    volume_isbn10 = filter_key(volume_info[:info], 'ISBN-10')
    volume_isbn10 = volume_isbn10.nil? ? nil : volume_isbn10[:value]
    volume_isbn13 = filter_key(volume_info[:info], 'ISBN-13')
    volume_isbn13 = volume_isbn13.nil? ? nil : volume_isbn13[:value]
    # next if volume_isbn10.nil? and volume_isbn13.nil?

    isbn = check_isbn(volume_isbn10)
    isbn = check_isbn(volume_isbn13) if !isbn[:is_valid]
    warn("ISBN ERROR for #{volume_info[:url]}") if !isbn[:is_valid]

    volume_cover = 'http://lndb.info' + volume_info[:coverUrl]
    filename_dst_we = ["Volume ", volume_index, " - ", normalize(volume_title),
                    "_", isbn[:isbn13]].join('')
    filename_dst = filename_dst_we + file_extension

    rename_file(file, filename_dst)

    md5 = Digest::MD5.file(filename_dst).hexdigest
    sha1 = Digest::SHA1.file(filename_dst).hexdigest
    data = {
      id: isbn[:isbn13].to_i,
      filepath: File.join(File.expand_path('.'), filename_dst),
      isbn10: isbn[:isbn10],
      isbn13: isbn[:isbn13],
      isbn_pretty: isbn[:isbn_pretty],
      md5: md5,
      title: volume_title,
      authors: [novel_author].flatten,
      cover_url: volume_cover,
      libgen: {
        author: novel_author,
        coverurl: volume_cover,
        crc32: Zlib.crc32(File.read(filename_dst), 0).to_s(16),
        extension: file_extension.split('.').last,
        filesize: File.stat(filename_dst).size,
        identifier: "#{isbn[:isbn13]},#{isbn[:isbn10]}",
        md5: md5,
        series: novel_title,
        sha1: sha1,
        title: volume_title
      }
    }

    send_book(data)
    save_json(data, filename_dst_we)
  end
  save_json(info, info[:title])
end

def fetch_config
  path = File.expand_path(File.dirname(__FILE__)) + '/config.json'
  JSON.parse(File.read(path), symbolize_names: true)
end

def ask_keyword
  prompt = TTY::Prompt.new
  prompt.ask('Enter title/keyword to search on LNDB.info')
end

def search
  config = fetch_config
  text = ask_keyword
  lndb_search = Search.new(config)
  lndb_novel = Novel.new(config)
  results = lndb_search.search_page(text)
  results[:results]
  search unless results[:success] && results[:count].positive?

  novel = select_novel(results[:results])
  organize_files(lndb_novel.get_novel(novel))
end

search
