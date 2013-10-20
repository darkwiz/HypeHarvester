#!/usr/bin/env ruby

=begin

A simple Ruby script that allows to download files from hypem.com

    Copyright (C) 2013 Matteo Gentile

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end


require 'net/http'
require 'uri'
require 'nokogiri'
require 'time'
require 'json'


PATH = 'popular'  # hypem.com section where you intend to start downloading ex. 'popular', 'latest', '<username>'...
PAGES = 1         # Number of pages you want to scrape



DEBUG = true     # Allows the script to create some debug files
HYPEM_URL = "http://hypem.com/" #HYPEM_URL = "http://hypem.com/#{PATH}"



class HypeHarvester

  attr_accessor :path, :pages
  
  def initialize(path='popular', pg=1)

    @hype_url, @pages = path, pg.to_i

    @hype_url = HYPEM_URL + "#{@hype_url}"
    puts "-------- Initializing --------"
    puts "\tPage Url : #{@hype_url}"
    puts "\tPages: #{@pages}"  

    start
  end

  def start
     

    i=1

    while i <= @pages do

     puts "\tParsing Page no.: #{i}" 

     page_url = @hype_url + "/#{i}"
     html, cookie = fetch_html(page_url)

     if DEBUG
       File.open('hype_debug.html', 'w') { |file| file.write("#{html.body}")}
     end

      tracks = parse_html(html)
      puts "\tParsed #{tracks.length} tracks"

      puts "--------Starting Downloads--------"

      download_songs(tracks, cookie)

    i+=1
    end
  end

 def fetch_html(url)

  data = {ax: 1 ,
    ts: Time.now.to_i
    }.to_json
    enc_data = URI.escape(data)
    complete_url = url + "?#{enc_data}"

    url = URI.parse(complete_url)
    req = Net::HTTP::Get.new(url.path, initheader = {'User-Agent' => 'playbook'})
    res = Net::HTTP.start(url.host, url.port) {|http|
      http.request(req)
    }
    cookie = res.response['set-cookie'].split('; ')[0]
    return res, cookie

  end


  def parse_html(html)

    html = Nokogiri::HTML(html.body)  
    tracks_list = html.css('#displayList-data')
    tracks_list if tracks_list.nil?

    begin  
      tracks_list = JSON.parse("#{tracks_list.inner_text}") 
      tracks_list["tracks"]
    rescue ParserError
      puts "Error Parsing HypeM JSON"
      tracks_list
    end 

  end


  def download_songs(tracks, cookie)

    puts "\tDownloading..."
    tracks.each do |track|
      key = track["key"]
      id = track["id"]
      artist = HypeHarvester.remove_disallowed(track["artist"])
      title = HypeHarvester.remove_disallowed(track["song"])
      type = track["type"]
      
      puts "\tFethching tracks..."
      puts "\t#{title} by #{artist}"
      
      if !type
        puts "\tSkipping Track..."
        next
      end

      begin
        uri = "http://hypem.com/serve/source/#{id}/#{key}"
        serve_url = URI.parse(URI.encode(uri.strip))
        req = Net::HTTP::Get.new(serve_url.path, initheader = {'Content-Type' =>'application/json', 'cookie' => cookie})
        response = Net::HTTP.new(serve_url.host, serve_url.port).start {|http| http.request(req) }

        data_json = response.body
        song = JSON.parse(data_json)
        url = song["url"]

        if DEBUG
          begin
            f = open("urls.txt", "r")
          rescue IO::WaitWritable, Errno::EINTR
            sleep 2
            retry
          ensure
            File.open("urls.txt", 'a+') { |file| file << "\t #{song}" }
          end
        end
       
        res = resolve(url)

        name = "#{title}_#{artist}.mp3"

        File.open(name, 'wb') { |file| file.write(res.body) }

         rescue Timeout::Error => e
                 puts "Error #{e.code}, #{e.msg}"
         rescue Net::HTTPBadRequest => e
                 puts "Error #{e.code}, #{e.msg} :Check Url"
         end
    end
  end
  
  def self.remove_disallowed(filename)
    begin
      filename.gsub(/[\x00\/\\:\*\?\"<>\|]/, '_')
    rescue Encoding::UndefinedConversionError => e
      puts "\t#{e}"
    end
  end

   def resolve(url)
      
      url = URI.parse(URI.encode(url))
      res = Net::HTTP.get_response(url)

        case res
        when Net::HTTPSuccess     then res
        when Net::HTTPRedirection then resolve(res['location'])
        else
          res.error!
        end
    end
end

print "Type hypem.com section where you intend to start downloading (ex. 'popular', 'latest', '<username>') :\t"
path = gets

print "Now please type the number of pages you want to scrape, i suggest to start with a tiny number (ex. 1-2) :\t"
number = gets

harvester = HypeHarvester.new(path.chomp!, number.chomp!)


#harvester.start

# Press Ctrl-C to interrupt the script

interrupted = false
trap("INT") { interrupted = true }

if interrupted
  exit
end


