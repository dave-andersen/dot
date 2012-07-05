#!/usr/bin/env ruby
require 'digest/sha1'
require 'sqlite3'
require 'base64'
require 'bdb'

##
# Benchmarks inserts into sqlite and BDB.
# To create sqlite DB, execute "sqlite3 dot.db"
# and then issue
#   create table chunks (hash BLOB, contents BLOB);
##

db = SQLite3::Database.open("/Users/dga/dot.db")
#db = BDB::Hash.open("/Users/dga/dotbdb", nil, BDB::CREATE, 0644)

CHUNKSIZE = 16384
count = 0
s = Time.new
puts s
$stdout.flush
db.execute("PRAGMA synchronous=OFF")
db.execute("PRAGMA count_changes=0")
db.execute("BEGIN TRANSACTION")
while ((b = $stdin.read(CHUNKSIZE)) != nil)
    dig = Digest::SHA1.digest(b)
    begin
        db.execute("insert into chunks VALUES (?,?)",
                   SQLite3::Blob.new(dig),
                   SQLite3::Blob.new(b))
    rescue => err
    end
#    db[dig] = b
    count += 1
    if (count >= 99)
        print "."
        $stdout.flush
        count = 0
    end
end
db.execute("COMMIT TRANSACTION")
db.execute("CREATE INDEX hashidx on chunks(hash)")
e = Time.new
$stdout.flush
puts e
puts (e - s)
$stdout.flush
