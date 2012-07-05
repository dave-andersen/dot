#!/usr/bin/env ruby

class Mlog
  attr_accessor :start_time, :headersize, :bodysize, :wholesize
  attr_accessor :wholehash, :headerhash, :bodyhash
  attr_accessor :to, :from
  attr_accessor :rabin_whole, :rabin_body, :static_whole, :static_body
  
  def initialize(messagedat)
    @static_whole = Array.new
    @static_body = Array.new
    @rabin_whole = Array.new
    @rabin_body = Array.new
    @to = Array.new
    @bodysize = @wholesize = @headersize = 0

    static_body = rabin_body = static_whole = rabin_whole = false;

    messagedat.each { |l| 
      l.chomp!
      if (l =~ /^MAIL (.*)/)
        static_body = rabin_body = static_whole = rabin_whole = false;
        @start_time = $1;
      elsif (l =~ /^CONNECT (.*)/)
	@connect = $1
      elsif (l =~ /^FROM (.*)/)
	@from = $1
      elsif (l =~ /^RCPT (.*)/)
	@to.push($1)
      elsif (l =~ /^HEADER ([0-9a-z]+) (\d+)/)
	@headerhash = $1
	@headersize = $2.to_i
      elsif (l =~ /^BODY ([0-9a-z]+) (\d+)/)
	@bodyhash = $1
	@bodysize = $2.to_i
      elsif (l =~ /^WHOLE ([0-9a-z]+) (\d+)/)
	@wholehash = $1
	@wholesize = $2.to_i
      elsif (l =~ /^STATIC_WHOLE_CHUNKS/)
	static_whole = true;
	rabin_body = static_body = rabin_whole = false;
      elsif (l =~ /^STATIC_BODY_CHUNKS/)
	static_body = true;
	rabin_body = static_whole = rabin_whole = false;
      elsif (l =~ /^RABIN_WHOLE_CHUNKS/)
	rabin_whole = true;
	rabin_body = static_whole = static_body = false;
      elsif (l =~ /^RABIN_BODY_CHUNKS/)
	rabin_body = true;
	static_body = static_whole = rabin_whole = false;
      elsif (static_whole)
	@static_whole.push(l)
      elsif (static_body)
	@static_body.push(l)
      elsif (rabin_whole)
	@rabin_whole.push(l)
      elsif (rabin_body)
	@rabin_body.push(l)
      else
	$stderr.print "Unknown line: #{l}\n"
      end
    }
  end
end

# A bin of mail - in other words, a collection of mlogs
class Mbin
  attr_reader :mlogs

  def initialize(dir)
    mailents = Dir["#{dir}/[0-9]*"]
    mailents.sort! { |a, b|  a.to_i <=> b.to_i }

    @mlogs = Array.new

    mailents.each { |ent| 
      message = ""
      IO.foreach(ent) { |f|
	if (f == "--==--\n")
	  #print "MESSGE:  #{message}\n\n"
	  nm = Mlog.new(message)
          if (nm.wholesize < 40000000)
	    @mlogs.push(nm)
          else
            print "Skipped mesage of #{nm.wholesize} bytes!\n"
          end
	  message = ""
	else
	  message += f
	end
      }
    }
  end
end
