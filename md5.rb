#!/usr/bin/env ruby
require 'digest/md5'
puts ARGV.join
puts Digest::MD5.hexdigest(ARGV.join)

