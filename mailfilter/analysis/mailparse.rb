#!/usr/bin/env ruby

require 'mlog'

print "Argv0:  #{ARGV[0]}\n"

mbin = Mbin.new(ARGV[0])

oc = Hash.new(0)

out = IO.popen("make-cdf > wholesize.cdf", "w")

totalbytes = 0
totalbody = 0
dotbody = 0
rabinbody = 0

mbin.mlogs.each { |m|
  out.print "#{m.wholesize}\n"
  totalbytes += m.wholesize
  totalbody += m.bodysize
  if (!oc.has_key?(m.bodyhash))
    oc[m.bodyhash] = 1
    dotbody += m.bodysize
  else
    oc[m.bodyhash] += 1
  end
}
out.close

out = IO.popen("make-hist 1 > sharedbodies.hist", "w")

numcount = Hash.new(0)
oc.each_pair { |k, v|
  out.print "#{v}\n"
}

out.close

oc = Hash.new
mbin.mlogs.each { |m|
  m.rabin_body.each { |c|
    if (!oc.has_key?(c))
      (hash, size) = c.split
      oc[c] = 1
      rabinbody += size.to_i
    else
      oc[c] += 1
    end
  }
}

rabinwhole = 0

oc = Hash.new
mbin.mlogs.each { |m|
  m.rabin_whole.each { |c|
    if (!oc.has_key?(c))
      (hash, size) = c.split
      oc[c] = 1
      rabinwhole += size.to_i
    else
      oc[c] += 1
    end
  }
}

class Hashdat
  attr_accessor :size, :count
  def initialize(size, count)
    @size = size
    @count = count
  end
  def totbytes
    @size * @count
  end
end

oc = Hash.new
mbin.mlogs.each { |m|
  if (!oc.has_key?(m.bodyhash))
    oc[m.bodyhash] = Hashdat.new(m.bodysize, 1)
  else
    oc[m.bodyhash].count += 1
  end
}

mlist = oc.values.sort { |a, b| b.totbytes <=> a.totbytes }

mlist[0..20].each { |m|
  print "ml totbytes: #{m.totbytes}  size:  #{m.size}  count: #{m.count}\n"
}

printf("   Total messages: %d\n", mbin.mlogs.size)
printf("      Total bytes: %10d\n", totalbytes)
printf(" Total body bytes: %10d\n", totalbody)
printf("   DOT body bytes: %10d\n", dotbody)
printf(" Rabin body bytes: %10d\n", rabinbody)
printf("Rabin total bytes: %10d\n", rabinwhole)

# The latex table

hb = totalbytes - totalbody
db = dotbody + hb
rb = rabinbody + hb

printf("SMTP default & #{totalbytes/(1024*1024)} MB & - \\\\\n")
printf("DOT body & #{db / (1024*1024)} MB & %.2f \\%% \\\\\n", 100.0 * db.to_f/totalbytes)
printf("Rabin body & #{rb / (1024*1024)} MB & %.2f \\%% \\\\\n", 100.0 * rb.to_f/totalbytes)
printf("Rabin whole & #{rabinwhole / (1024*1024)} MB & %.2f \\%% \\\\\n", 100.0 * rabinwhole.to_f/totalbytes)

