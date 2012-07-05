#!/usr/bin/env ruby
require 'digest/sha1'
require 'sqlite3'
require 'base64'
require 'bdb'

db = SQLite3::Database.open("/Users/dga/dot.db")
#db = BDB::Hash.open("/Users/dga/dotbdb", nil, BDB::CREATE, 0644)

CHUNKSIZE = 16384
count = 0

$stdin.each_line { |l|
    dig = Base64.decode64(l.chomp)
#    b = db[dig]
    row = db.execute("select contents from chunks where hash=? LIMIT 1",
                     SQLite3::Blob.new(dig))
    b = row[0][0]
    
    dig2 = Digest::SHA1.digest(b)
    if (dig != dig2)
        puts "Error, digest mismatch\n"
    end
}
