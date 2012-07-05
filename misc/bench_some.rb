#!/usr/bin/env ruby
require 'digest/sha1'
require 'base64'

CHUNKSIZE = 16384

while ((b = $stdin.read(CHUNKSIZE)) != nil)
    dig = Digest::SHA1.digest(b)
    if (rand < 0.01)
	puts Base64.encode64(dig)
    end
end
