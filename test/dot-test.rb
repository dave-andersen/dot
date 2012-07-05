#!/usr/bin/env ruby

##
# To run:  ruby dot-test.rb -v
# (You want the verbose flag;  it makes the testing more clear)
##

$LOAD_PATH << (File.dirname(__FILE__))

require 'test/unit'
require 'thread'
require 'tempfile'

require 'unit_test_hack'
require 'spawn_buffered'
require 'tmpdir'
require 'fileutils'

class GTCD < SpawnBufferedReader
    attr_reader :cachedir, :sock, :port_base, :logpath
    def initialize(conf_contents, port_base = 15000, 
		   sockname_override = nil, extra_args = nil)
	@port_base = port_base
	@dottmpdir = "/tmp/dot_" + @port_base.to_s
	#@cachedir = "/tmp/" + @cachedir_base
	@sock = @dottmpdir + "/gtcd.sock"
        @conf_file = @dottmpdir + "/gtcd_" + @port_base.to_s + ".conf"
	if (sockname_override)
	    @sock = sockname_override
	end

        system("rm -rf #{@dottmpdir}")
        Dir.mkdir(@dottmpdir)

        ea = extra_args || ""
	ENV["DOT_TMP_DIR"] = @dottmpdir

        conf = File.new(@conf_file, "w")
        conf.write(conf_contents)
        conf.close

	ea = extra_args || ""

        @logpath = "/tmp/gtcd_#{@port_base}" + ".log"
        super("gtcd/gtcd -D 2 -f #{@conf_file} #{ea}", @logpath)
	@keep_log = true
    end

    def keep_log
	@keep_log = true
    end

    def gcp_args
	"-p #{sock}"
    end

    def kill
	super
	system("rm -rf #{@dottmpdir}")
        if (!@keep_log)
	    File.unlink(@logpath)
	end
    end
end

module DOTTestUtil
    def make_tmpdirname(base)
        return "#{base}-#{$$}-#{rand(99999)}"
    end

    def create_tmpdir()
        done = false
        name = nil
        while (!done)
            done = true
            begin
                name = File.join(Dir.tmpdir, make_tmpdirname("dottest"))
                Dir.mkdir(name)
            rescue => err
                done = false
                trycount += 1
                if (trycount > 10)
                    throw "Too many failures creating tmpdir"
                end
            end
        end
        return name
    end

    def create_random_dir(nfiles, avgsize)
        tmpdir = create_tmpdir()
        files = Array.new
        while (nfiles > 0)
            size = rand(avgsize*2)
            files << create_random_file(size, tmpdir)
            nfiles -= 1
        end
        return tmpdir, files
    end

    def create_random_file(size, base=nil)
	t = Tempfile.new("dottest", base || Dir::tmpdir)
	dr = File.open("/dev/urandom", "r")
	while (size > 0)
	    toread = [size, 4096].min
	    t.syswrite(dr.sysread(toread))
	    size -= toread
	end
	return t
    end

    def do_gcp_put(gtcd, path, extra_gcp_args="")
	run_gcp = "gcp/gcp " + extra_gcp_args + " " + gtcd.gcp_args + 
                  " --put-only #{path} 2>/dev/null"
	put_res = `#{run_gcp}`
	assert_match(/PUT_OID:([^:]+)/, put_res, "output of gcp put incorrect")
	oid = ""
	if (put_res =~ /PUT_OID:([^:]+)/)
	    oid = $1.chomp
	end
	return oid
    end

    def do_gcp_get(gtcd, oid, outpath)
        #run_gcp = "gcp/gcp " + gtcd.gcp_args + " --get-only dot://#{oid} HINTFILE #{outpath} 2>/dev/null"
        run_gcp = "gcp/gcp " + gtcd.gcp_args + " --get-only current.dot #{outpath} 2>/dev/null"
	get_res = `#{run_gcp}`
	assert_equal($?, 0, "Exit code of gcp get was non-zero")
    end

    def do_cross_gtc_put_get(p1, p2)
	oid = do_gcp_put(@g[0], p1)
	oid += ":127.0.0.1:#{@g[0].port_base.to_s}:1"
	do_gcp_get(@g[1], oid, p2)
	assert_files_equal(p1, p2)
    end
end

module SingleSetup
    def create_config(xgtc_port=nil)
        config = "[storage]\ndisk\n\n[transfer]\nxgtc null\n\n[server]\nsegtc null %d\n[chunker]\ndefault null static\n"
        xgtc_port ||= 12000
        return sprintf(config, xgtc_port)
    end

    def setup_once
	@g = Array.new
	@g[0] = GTCD.new(create_config(12000), 12000) # a "normal" gtcd
	@g[1] = GTCD.new(create_config(15000), 15000)
	sleep(1)
	return @g # passed to setup_real each time
    end

    def setup_real(params)
	@g = params
	@t1 = Tempfile.new("dottest")
	@t2 = Tempfile.new("dottest")
    end

    def cleanup
	@g.each { |g| g.kill if g }
	super
    end

    def teardown
	@t1.close if @t1
	@t1.unlink if @t1
	@t2.close if @t2
	@t2.unlink if @t2
	@t1 = nil
	@t2 = nil
    end
end

class TestDOT < CleanupTestCase
    include DOTTestUtil
    include SingleSetup

    def test_gtcds_run
	@g.each { |g| assert(g.is_alive?, "gtcd was dead") }
    end

    def test_gcp_put
	assert(@g[0].is_alive?, "gtcd is dead at start of test_gcp_put")
	@t1.write('a' * 500)
	@t1.close
	oid = do_gcp_put(@g[0], @t1.path)
	assert_equal($?, 0, "gcp put exit code was non-zero")
	assert(@g[0].is_alive?, "gtcd is dead after running gcp put")
	assert_equal(oid, "e62ca5609e96073ffdc80ad480510d6de0a13f3e", "OID returned by DOT was wrong")
    end

    def test_gcp_put_get
	@t1.write('a' * 500)
	@t1.close
	@t2.close
	oid = do_gcp_put(@g[0], @t1.path)
	oid += ":127.0.0.1:#{@g[0].port_base.to_s}:1"
	do_gcp_get(@g[0], oid, @t2.path)
	assert_files_equal(@t1.path, @t2.path)
    end

    def test_cross_gtc_put_get
	@t1.write('a' * 500)
	@t1.close
	@t2.close
	do_cross_gtc_put_get(@t1.path, @t2.path)
    end

    def test_bigzeros_put_get
          @t1.write('\0' * 200000)
          @t1.close
          @t2.close
          do_cross_gtc_put_get(@t1.path, @t2.path)
    end

    def test_random_put_gets
	return
	10.times do
	    begin
		t1 = create_random_file(rand(1000000))
		t1.close
		t2 = Tempfile.new("dottest")
		t2.close
		do_cross_gtc_put_get(t1.path, t2.path)
	    ensure
		t1.unlink if t1
		t2.unlink if t2
	    end
	end
    end

    def test_zero_byte_put_get
	@t1.close
	@t2.close
	do_cross_gtc_put_get(@t1.path, @t2.path)
	assert(@g[0].is_alive?, "gtcd1 dead after zero byte put/get")
	assert(@g[1].is_alive?, "gtcd2 dead after zero byte put/get")
    end

end

class TestChunkCache < CleanupTestCase
    include DOTTestUtil
    include SingleSetup
    
    def create_params
      #make the cache size 100 MB
      p = "MAX_CHUNKS_MEM_FOOTPRINT = 104857600\nCHUNKS_HIGH_WATER = 100\nCHUNKS_LOW_WATER  = 100\n"
      return p
    end

    def setup_once
        conf = File.new("/tmp/params.conf", "w")
        conf.write(create_params())
        conf.close

	@g = Array.new
	@g[0] = GTCD.new(create_config(12000), 12000, nil, "-v /tmp/params.conf") # a "normal" gtcd
	@g[1] = GTCD.new(create_config(15000), 15000, nil, "-v /tmp/params.conf")
	sleep(1)
	return @g # passed to setup_real each time
    end
    
    def test_bdb_cache
        #puts "Start here"
        t1 = create_random_file(209715200) #200 MB file
        t1.close
        @t2.close
	do_cross_gtc_put_get(t1.path, @t2.path)
    end
end

class TestDOTRabin < TestDOT
    def create_config(xgtc_port=nil)
        config = "[storage]\ndisk\n\n[transfer]\nxgtc null\n\n[server]\nsegtc null %d\n[chunker]\ndefault null rabin\n"
        xgtc_port ||= 12000
        return sprintf(config, xgtc_port)
    end

    #randomly generated files create chunks of size 65536, 
    #not really variable sized
    def test_real_file
      t1 = "test/media_file"
      return unless File.exist?(t1)
      @t2.close
      do_cross_gtc_put_get(t1, @t2.path)
    end
end

module ManySetup
    def create_config(xgtc_port=nil)
        config = "[storage]\nsnoop sset\nsset disk 127.0.0.1 5852\ndisk\n\n[transfer]\nxset msrc\nmsrc xgtc\nxgtc\n\n[server]\nsegtc null %d\n[chunker]\ndefault null static\n"
        xgtc_port ||= 12000
        return sprintf(config, xgtc_port)
    end

    def setup_once
	@cdht = SpawnBufferedReader.new("cdht/cdht_server", "/tmp/cdht.log")
	gtcds = Array.new
	@g = Array.new
        g0con = create_config(12000)
	@g[0] = GTCD.new(g0con, 12000)
	(0..4).each do |x|
            localport = 15000 + (x*1000)
            conf = create_config(localport)
	    @g << GTCD.new(conf, localport)
	end
	sleep 2
	return [@cdht, @g].flatten
    end

    def setup_real(params)
	@cdht, *@g = params
	@t1 = Tempfile.new("dottest")
	@t2 = Tempfile.new("dottest")
    end


end

class TestSET < TestDOT
    include ManySetup
    # Inherits all DOT basic tests

    def cleanup
	@cdht.kill if @cdht
	super
    end

    def test_many_sources
	t1 = create_random_file(rand(1000000))
	t1.close
	oid = nil
	oldoid = nil
	@g[1..-1].each { |g|
	    oid = do_gcp_put(g, t1.path)
	    assert_equal(oid, oldoid, "OIDs from puts do not match") if oldoid
	    oldoid = oid
	}
	oidhints = "#{oid}:127.0.0.1:17000:1"
	do_gcp_get(@g[0], oidhints, @t2.path)
	assert_files_equal(t1.path, @t2.path)
    ensure
	t1.unlink if t1
    end

end

# This test doesn't actually work because the localhost source
# is too fast.  But it's a start.

class TestSET_Swarming < CleanupTestCase
    include ManySetup
    include DOTTestUtil

    def cleanup
	@g.each { |g| g.kill if g }
	@cdht.kill if @cdht
	super
    end
    
    def test_swarmers
	t1 = create_random_file(rand(1000000))
	t1.close
	oid = do_gcp_put(@g[0], t1.path)
	oidhints = "#{oid}:127.0.0.1:12000:1"
	threads = Array.new
	@g[1..-1].each { |g|
	    threads << Thread.new(g) { |target|
		t = Tempfile.new("dottest")
		t.close
		do_gcp_get(target, oidhints, t.path)
		# not clear that this assertion failure willl work!!
		assert_files_equal(t1.path, t.path);
	    }
	}
	threads.each { |t| t.join }
    end
end

class TestXdisk < TestDOT
    def create_config(xgtc_port=nil)
        config = "[storage]
snoop sset
sset disk 127.0.0.1 5852
disk

[transfer]
opt xgtc,xdisk
xgtc
xdisk null default:1 static

[server]
segtc null %d

[chunker]
default null static\n"

        xgtc_port ||= 12000
        return sprintf(config, xgtc_port)
    end

end

class TestTree < CleanupTestCase
    include DOTTestUtil
    include SingleSetup

    def tree_gcp_put_get(gcp_args = "")
        dir, files = create_random_dir(2, 4096)
        destdir = File.join(Dir.tmpdir, make_tmpdirname("dottest_out"))

	oid = do_gcp_put(@g[0], dir, gcp_args)
        oid += ":127.0.0.1:#{@g[0].port_base.to_s}:0"
        do_gcp_get(@g[0], oid, destdir)
        system("diff -q #{dir} #{destdir}/#{File.basename(dir)}")
        assert_equal($?, 0, "Input and output directories did not match")

        files.each { |f| 
            f.close
            f.unlink
        }
        FileUtils.rm_rf(dir)
        FileUtils.rm_rf(destdir)
    end
    def test_gcp_put_get
        tree_gcp_put_get()
    end

    def test_gcp_put_get_by_path
        tree_gcp_put_get("-d")
    end
end

class TestCE < TestDOT
    def create_config(xgtc_port=nil)
        config = "[storage]
ce disk u
disk

[transfer]
ce xgtc
xgtc

[server]
segtc null %d

[chunker]
default null static\n"

        xgtc_port ||= 12000
        return sprintf(config, xgtc_port)
    end

end

