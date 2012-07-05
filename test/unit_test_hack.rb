# I want global initalizers and destructors,
# since we spawn a gtcd each time.
# Harder to do than one would want.

$setup_done = false

$ABORT_ON_FIRST_ERROR = false
if (ENV["ABORT_ON_ERROR"]=="true")
    $ABORT_ON_FIRST_ERROR = true
end

def global_setup_once(setup_real, setup_done)
    if (!$setup_done)
	$setup_done = true
	$setup_params = setup_real.call
    end
    setup_done.call($setup_params)
end

module Test
    module Unit
        class TestCase
            alias :real_add_failure :add_failure
            def add_failure(message, all_locations=caller())
                real_add_failure(message, all_locations)
                raise "Done" if $ABORT_ON_FIRST_ERROR
            end
        end
        
        class TestSuite
            def run(result, &progress_block)
                yield(STARTED, name)
                @tests.each do |test|
                    test.run(result, &progress_block)
                end
            rescue => e
                yield(FINISHED, name)
            end
        end
    end
end

class CleanupTestCase < Test::Unit::TestCase
    def self.suite
	method_names = public_instance_methods(true)
	s = super
	s << new("cleanup") if method_names.include?("cleanup")
	return s
    end

    def test_dummy
	# This is stupid.  test/unit is not designed to be subclassed.  Ick.
    end

    def setup_once
    end

    def setup_real(a)
    end

    def setup
	global_setup_once(proc { setup_once },
			  proc { |a| setup_real(a) } )
    end

    def cleanup
	# This global is an awful ugly hack. :(
	$setup_done = false
    end

    def assert_files_equal(f1, f2, message=nil)
	full_message = build_message(message,
				     "Files <?> and <?> were not identical",
				     f1, f2)
	`diff -q #{f1} #{f2}`
	assert_block(full_message) { $? == 0 }
    end

end
