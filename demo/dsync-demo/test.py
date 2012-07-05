
import sys, os, os.path, random, time

for i in range(2):
  l = []
  try:
    fname = "data/%d.log" % i
    fsock = open(fname, "r")
    try:
      for line in fsock:
        #removing newline from the end of string
        line = line[:-1]
        parts = line.split(" ")
        print "id ", parts[0], " t ", parts[1], " s ", parts[2]
        #l.append((t, s))	    
    finally:
      fsock.close()
      #node.chunks.extend(l)
      #node.total_chunks = len(l)
      #self.total_chunks += node.total_chunks
  except IOError, e:
    print e 
        
