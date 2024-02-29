#!/usr/bin/env ruby

# == sitemap2proxy - Read a sitemap.xml file and request each entry in it through a given proxy
#
# The main idea of this is to push a request for each URL through a tool like 
# Burp so that Burp gets its eyes on the pages and you can then analyse them
# further.
#
# For more information see
#   https://digi.ninja/projects/sitemap2proxy.php
#
# == Version
#
#  1.2 - Hosting on GitHub and added expected URL count
#  1.1 - Added response code stats
#  1.0 - Released
#
# == Usage
#
# Author:: Robin Wood (robin@digininja.org
# Copyright:: Copyright (c) Robin Wood 2012
# Licence:: GPL 3
#

require 'rexml/document'
require "net/http"
require 'getoptlong'
require 'openssl'

verbose=false
url = nil
file = nil
proxy = nil
url_count = 0
user_agent = {'User-Agent' => "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"}
VERSION = "1.2"

trap("SIGINT") { throw :ctrl_c }

puts "sitemap2proxy #{VERSION} Robin Wood (robin@digininja.org) (www.digininja.org)"
puts

opts = GetoptLong.new(
	[ '--help', '-h', GetoptLong::NO_ARGUMENT ],
	[ '--file', "-f" , GetoptLong::REQUIRED_ARGUMENT ],
	[ '--url', "-u" , GetoptLong::REQUIRED_ARGUMENT ],
	[ '--proxy', "-p" , GetoptLong::REQUIRED_ARGUMENT ],
	[ '--ua', "-a" , GetoptLong::REQUIRED_ARGUMENT ],
	[ "-v" , GetoptLong::NO_ARGUMENT ]
)

# Display the usage
def usage
	puts"Usage: sitemap2proxy [OPTIONS]
	--help, -h: show help
	--file, -f <filename>: local file to parse
	--url, -u <url>: URL to the file
	--proxy, -p <proxy address>: address of the proxy
	--ua, -a <user agent>: specify an alternative user agent - default is Googlebot
	-v: verbose

"
	exit
end

def print_error error
	puts error
	puts
	exit
end

begin
	opts.each do |opt, arg|
		case opt
			when '--help'
				usage
			when "--url"
				url = arg
			when "--file"
				if !File.exists?(arg)
					print_error "Local file not found\n"
					exit
				end
				file = arg
			when "--proxy"
				proxy = arg
			when "--ua"
				user_agent = {'User-Agent' => arg}
			when '-v'
				verbose=true
		end
	end
rescue
	usage
end

if not (file.nil? or url.nil?)
	puts "Please specify either a file or URL to process, not both"
	puts
	usage
	exit
end

if file.nil? and url.nil?
	puts "You must specify either a file or URL to process"
	puts
	usage
	exit
end

if proxy.nil?
	puts "You must specify a proxy"
	puts
	usage
	exit
end

proxy = "http://" + proxy if proxy !~ /^http/

proxy_uri = URI.parse proxy
proxy = Net::HTTP::Proxy(proxy_uri.host, proxy_uri.port)

sitemap = nil

if (!file.nil?)
	if file =~ /.gz$/
		begin
			body = File.open(file, "rb").read

			gz = Zlib::GzipReader.new(StringIO.new(body))
			sitemap = gz.read
		rescue Zlib::GzipFile::Error
			sitemap = File.read(file)
		end
	else
		sitemap = File.read(file)
	end
elsif !url.nil?
	begin
		url = "http://" + url if url !~ /^http/
		uri = URI.parse(url)

		http = Net::HTTP.new(uri.host, uri.port)
		if uri.scheme == 'https'
		  http.use_ssl = true
		  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
		end

		response = http.request(Net::HTTP::Get.new(uri.request_uri, user_agent))

		if response.code != "200"
			print_error "There was a problem retrieving the sitemap"
			exit
		end

		if url =~ /.gz$/
			begin
				gz = Zlib::GzipReader.new(StringIO.new(response.body))
				sitemap = gz.read
			rescue Zlib::GzipFile::Error
				sitemap = response.body
			end
		else
			sitemap = response.body
		end
	rescue => e
		puts "There was an error: "
		puts e
		exit
	end
end

if sitemap.nil?
	print_error "No sitemap data found, aborting"
	exit
end

doc = REXML::Document.new(sitemap)

response_codes = {}

catch :ctrl_c do

    count = 0
	doc.elements.each("/urlset/url/loc") do |ele|
      count += 1
    end

	puts "Starting to retrieve #{count} URLs"
    puts 

	doc.elements.each("/urlset/url/loc") do |ele|
		url = ele.text
		puts "Requesting: " + url if verbose
		uri = URI.parse(url)
		path = uri.path
		if path == ""
			path = "/"
		end
		begin
			http = proxy.start(uri.host, :use_ssl => uri.scheme == 'https', :verify_mode => OpenSSL::SSL::VERIFY_NONE)
			resp = http.get(path, user_agent)
			if not response_codes.has_key? resp.code.to_i
				response_codes[resp.code.to_i] = 0
			end
			response_codes[resp.code.to_i] += 1

			puts "Response: " + resp.code + " " + resp.message if verbose
		rescue Errno::ECONNREFUSED
			print_error "Failed to connect to the proxy"
			exit
		rescue => e
			puts e
		end
		url_count += 1
        if url_count % 10 == 0
          print "/" if !verbose
        else
          print "." if !verbose
        end
	end
end

puts
puts
puts "Stats"
puts "-----"
puts
puts url_count.to_s + " URLs parsed"
puts
response_codes.keys.sort.each do |resp_code|
	count = response_codes[resp_code]
	puts "Code: #{resp_code} Count: #{count.to_s}"
end
