#!/usr/bin/env ruby

# Spawn a child;  read its input into a limited-length buffer
# that our parent can read from if they want to.
# Captures stderr and stdout

require 'thread'

class SpawnBufferedReader
    def initialize(prog, logfile=nil)
	@PROG = prog
	sb_spawn_child
	setup_child
	@buf = ""
	@logfile = nil
	if (logfile)
	    @logfile = File.new(logfile, "a")
	end
    end

    def sb_spawn_child
	rd, wr = IO.pipe
	if ((pid = fork))
	    @kidpid = pid
	    @child = rd
	    wr.close
	    return @child
	else
	    rd.close
	    $stderr.reopen(wr)
	    $stdout.reopen(wr)
	    exec @PROG
	end
    end
    
    def setup_child
	@bufmutex = Mutex.new
	@reader = Thread.new(@child) { |mychild|
	    begin
		    while ((dat = mychild.readpartial(8192))) do
		    @logfile.syswrite(dat) if @logfile
		    @bufmutex.synchronize do
			@buf << dat
		    end
		end
	    rescue => err
	    end
	    Process.waitpid(-1, Process::WNOHANG)
	}
    end

    def read
	retbuf = ""
	@bufmutex.synchronize do
	    retbuf = @buf
	    @buf = ""
	end
	return retbuf
    end
    
    def is_alive?
	begin
	    Process.kill 0, @kidpid
	    return true
	rescue => err
	    return false
	end
    end

    def kill
	begin
	@logfile.close if @logfile
	@child.close
	@reader.kill
	rescue => err
	    puts "Err during kill (ignored): #{err}"
	end
	@buf = ""
	begin
	    Process.kill("INT", @kidpid)
	    Process.kill("KILL", @kidpid)
	rescue => err
	    # We don't care if the child is dead already
	end
	Process.waitpid(-1, Process::WNOHANG)
    end

    def wait
	@reader.join
    end
end

if ($0 == __FILE__)
    echo = SpawnBufferedReader.new("echo hello")
    sleep 1
    echo.kill
    sleep 1
end
