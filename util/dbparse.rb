#!/usr/bin/env ruby

class Node
    attr_accessor :name, :obj
    def initialize(name, obj)
        @name = name
        @obj = obj
    end
end

class Chartree
    def initialize()
        @root = Array.new(26) { nil; }
    end
    def insert(s, obj)
        insert_int(s, @root, obj)
    end
    def insert_int(s, r, obj)
        c = s[0]
        case s.size
        when 0
            return
        when 1
            r[c] = Node.new(s[1..-1], obj)
        else
            if (r[c] == nil)
                r[c] = Node.new(s[1..-1], obj)
            elsif (r[c].class == Node)
                old = r[c]
                r[c] = Array.new
                insert_int(old.name, r[c], old.obj)
                insert_int(s[1..-1], r[c], obj)
            else
                insert_int(s[1..-1], r[c], obj)
            end
        end
    end
    def get
        get_r(@root, "")
    end
    def get_r(r, accum)
        ret = Array.new
        (0..255).each { |c|
            case r[c]
            when Node
                ret << [accum + c.chr, r[c].obj]
            when Array
                ret.concat(get_r(r[c], accum + c.chr))
            end
        }
        return ret
    end
end

t = Chartree.new
vals = Array.new
names = Hash.new
texts = Hash.new
ARGF.each_line { |l|
    if (l =~ /^\#define\s+([^\s]+)\s*([^\s]+)\s.*DBTEXT:\s*(.*)/)
        name = $1
        val = $2
        text = $3
        name.downcase!
        t.insert(name.sub("debug_", ""), val)
        vals << val
        names[val] = name
        texts[val] = text
    end
}
r = t.get()
minstr = Hash.new
r.each { |m|
    minstr[m[1]] = m[0]
}
vals.each { |v|
    puts "{ " + names[v].upcase + ", \"" + texts[v] + "\", \"" + minstr[v] + "\"},"
}
