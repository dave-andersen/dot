#!/usr/bin/env ruby
require 'mlog'

mbin = Mbin.new(ARGV[0])

PRINTABLES = "01234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ~\!@\#$%^&*()_+,<.>/?\'\"\n"
PRINTABLESNOCR = "01234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ~\!@\#$%^&*()_+,<.>/?\'\""

def gen_rand(size, seed, cr)
  a = Array.new
  srand(seed)
  while (size > 0)
    if (cr)
      a.push(PRINTABLES[rand(PRINTABLES.size)].to_i)
    else 
      a.push(PRINTABLESNOCR[rand(PRINTABLESNOCR.size)].to_i)
    end
    size -= 1
  end
  return a.pack("c*")
end

ob = Hash.new
idx = 1
mbin.mlogs.each { |m|
  #out = File.new("out/#{idx}", "w") 
  outrand = File.new("outrand/#{idx}", "w")
  #out.print "To: dga@fuchsia.aura.cs.cmu.edu\n"
  #out.print "Subject: " + gen_rand(m.headersize - 200, m.headerhash.hex % (2**31), false) + "\n\n"
  outrand.print "To: dga@fuchsia.aura.cs.cmu.edu\n"
  outrand.print "Subject: " + gen_rand(m.headersize - 200, rand(2**31), false) + "\n\n"
  m.rabin_body.each { |b|
    p b
    h, s = b.split
    #out.print gen_rand(s.to_i, h.hex % (2**31), true)
    outrand.print gen_rand(s.to_i, rand(2**31), true)
  }
  #out.close
  outrand.close
  idx += 1
}
