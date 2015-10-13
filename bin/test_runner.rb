#!/usr/bin/env ruby
require 'jenkins_api_client'
require 'right_api_client'
require 'forwardable'
require 'tco'
require 'pry'
require 'pry-byebug'


###############################################################################
# Pick up config files and init befroe starting

runner_options = YAML.load_file(File.expand_path("~/.test_runner/options.yaml"))
@@file_location = runner_options[:todo_file_location]
@@prefix        = runner_options[:prefix]
@@launched      = runner_options[:launched]
@@launch_limit  = runner_options[:launch_limit]
@@threshold     = runner_options[:threshold]
@@cloud         = runner_options[:cloud]
@@run_anyway    = runner_options[:run_anyway]

# Jenkins api client
@@client = JenkinsApi::Client.new(YAML.load_file(File.expand_path("~/.jenkins_api_client/login.yml")))
raise "Unable to instantiate jenkins_api_client, please check config file" if @@client.nil?

# right_api_client
@@api_client = RightApi::Client.new(YAML.load_file(File.expand_path('~/.right_api_client/login_test_runner.yml', __FILE__)))
@@api_client.log  nil
raise "Unable to instanciate right api client, please check config file" if @@api_client.nil?

##############################################################################
# Class definitions

class Test
  attr_accessor :todo_string, :stage_id, :stage, :name, :status, :next, :opts
  extend Forwardable
  def_delegators :@stage, :process, :get_line, :is_up?
  def_delegators :@stage, :total_deps_up

  def initialize(string)
    elems = string.split(' ')
    @opts = {}
    if elems.length == 1
      @opts[:stage_id] = "(A)"
      @opts[:name] = string.chomp
      @opts[:status] = "@unknown"
      @opts[:next] = "+unknown"
    elsif elems.length == 4
      @opts[:stage_id]  = elems[0]
      @opts[:name]   = elems[1]
      @opts[:status] = elems[2]
      @opts[:next]   = elems[3]
    else
      error_mssg = <<-ERRORMSG.gsub(/^\s*/, "")
        ERROR:  Invalid string formation. todo strings should be one of
        - single word for name of test
        - 4 words with stage, name, status, next
        -
        Received #{elems.length} words in string.
        -
        #{string}
      ERRORMSG
      puts error_mssg.fg 'red'
      exit 1
    end

    @todo_string = "#{@opts[:stage_id]} #{@opts[:name]} #{@opts[:status]} #{@opts[:next]}"

    case @opts[:stage_id]
    when "(A)"
      @stage = Staging.new(@opts)
    when "(B)"
      @stage = Running.new(@opts)
    when "(C)"
      @stage = Done.new(@opts)
    when "(D)"
      @stage = DestroyAndRerun.new(@opts)
    when "(X)"
      @stage = Failed.new(@opts)
    else
      raise "UNKOWN STAGE ID #{stage_id}"
    end
  end
  def done?
    if @stage.class == Done || @stage.class == Failed
      true
    else
      false
    end
  end
end

class BaseStage
  attr_accessor :opts, :test_executor
  def initialize(_opts)
    @opts = _opts
  end

  def subset(_opts, sub)
    subset = _opts.select { |k,v| sub.keys.include? k }
    subset == sub
  end

  def process
    puts "Base processing default"
  end

  def set_stage( stage_id, at_status, plus_next )
    @opts[:stage_id] = stage_id
    @opts[:status] = at_status
    @opts[:next] = plus_next
  end

  def get_line
    return "#{@opts[:stage_id]} #{@opts[:name]} #{@opts[:status]} #{@opts[:next]}"
  end
  def is_up?
    name = @opts[:name]
    deployments = @@api_client.deployments.index(:filter => ["name==#{name}"])
    deployments.empty? ? false : true
  end
  def total_deps_up(prefix)
    deployments = @@api_client.deployments.index(:filter => ["name==#{prefix}"])
    deployments.length
  end
  def launch_destroyer(job_name)
    destroyer_name = "Z_#{job_name}"
    current_launches = @@client.job.get_builds(destroyer_name).length
    @@client.job.build(destroyer_name)
    wait_seconds = -30
    (wait_seconds..0).each do |i|
      print "Waiting #{i.abs} for #{job_name} Destroyer to start\r"
      new_launches = @@client.job.get_builds(destroyer_name).length
      if current_launches +1 == new_launches
         puts "Registered new destroyer for #{job_name}".fg 'yellow'
         return
      end
      sleep 1
    end
    puts "Destroyer did not launch in #{wait_seconds} for #{job_name}".fg 'red'
  end
end

class Staging < BaseStage
  def process
    puts "STAGING #{@opts.inspect}"
    if is_up? && @opts[:next] != "+check_it_launched"
      puts "Staging, shifting to Destroy and Run".fg 'red'
      set_stage("(D)", "@unknown", "+unknown")
      return
    end

    if @@run_anyway
      puts "RUN_ANYWAY flag is on, passing builds will be rerun".fg 'yellow'
      status = "@run_anyway"
    else
      status = @@client.job.get_current_build_status(@opts[:name])
      if status == "success"
        @opts[:status] = "@success"
      end
    end

    total_up = total_deps_up(@@prefix)
    puts "TOTAL DEPLOYMENTS UP IS #{total_up}".fg 'light-blue'
    case @opts[:status]
    when "@unknown", "@run_anyway"
      # Staging fist step is to launch it.
      if @@launched >= @@launch_limit
        puts "launch limit hit".fg 'yellow'
      elsif total_up >= @@threshold
        puts "Threshold (#{@@threshold}) matched or exceeded, holding".fg 'yellow'
      else
        puts "LAUNCHING #{@opts[:name]}".fg 'yellow'
        @@client.job.build( @opts[:name])
        @@launched += 1
        @opts[:status] = "@launched"
        @opts[:next] = "+check_it_launched"
        puts "Sleeping for 30 seconds to allow deployment to show up on radar".fg 'yellow'
        sleep 30
      end
    when "@launched"
      #puts "Check if it's running and if so transition to 'running' stage"
      status = @@client.job.get_current_build_status(@opts[:name])
      next_action = @opts[:next]
      puts "STATUS IS #{status}".fg 'yellow'
      if next_action == "+check_it_launched" && status != "running"
        set_stage("(X)", "@failed_to_launch", "+review")
      else
        case status
        when "success"
          set_stage("(C)", "@success", "+final_review")
        when "running"
          set_stage("(B)", "@running", "+wait_on_run")
        end
      end
    when "@success"
      # it must have passed last time, check for next action, if none, just complete
      @opts[:stage_id] = "(C)"
      case @opts[:next]
      when "+unknown"
        @opts[:next] = "+review"
        puts "Please review job #{@opts[:name]} and remove if completed"
      when "+none"
        ;
      end
    when "@failure"
      puts "Rerunning job #{@opts[:name]}, removing current jenkins status"
      set_stage("(A)", "@unknown", "+none")
    else
      raise "STAGING process:  Unrecognized status #{@opts[:status]}"
    end
  end
end

class Running < BaseStage
  def process
    @opts[:status]  = @@client.job.get_current_build_status(@opts[:name])
    puts "RUNNING #{get_line} with status #{@opts[:status]}"
    case
    when subset(@opts, status: "success")
      set_stage("(C)", "@success", "+review")
    when subset(@opts, status: "failure")
      launch_destroyer(@opts[:name])
      set_stage("(X)", "@failure", "+review")
    end
  end
end

class Failed < BaseStage
  def process
    destroyer_name = "#{@opts[:name]}"
    destroy_status = @@client.job.get_current_build_status(destroyer_name)
    case destroy_status
    when "success"
      # This is a no-op, just ignore it
      ;
    when "failure"
      # This is a no-op just ignore for now
      ;
    end
  end
end

class DestroyAndRerun < BaseStage
  def process
    case @opts[:status]
    when "@unknown"
      # first time we see this, launch destroyer
      begin
        @@client.job.build( "Z_#{@opts[:name]}")
        @opts[:status] = "@destroying"
      rescue
        puts "UNABLE TO DESTROY Z_#{@opts[:name]}!".fg 'yellow'
        @opts[:status] = "@unknown"
      end
    when "@destroying"
      begin
        status = @@client.job.get_current_build_status("Z_#{@opts[:name]}")
      rescue
        puts "UNABLE TO GET STATUS ON Z_#{@opts[:name]}!".fg 'yellow'
        status = "@unknown"
      end
      case status
      when "success"
        # destroyer completed, good to go, transition back to staging
        set_stage("(A)", "@unknown", "+run")
      when "failure"
        # destroyer bombed, got to have a look
        set_stage("(X)", "@failure", "+destroyer_failed_review")
      end
    end
  end
end

class Done < BaseStage
end


###############################################################################
# Global functions, and main loop

def check_todo_list
  raise "File location for todo list is nil" if @@file_location.nil?
  puts "Loading #{@@file_location}"
  begin
    todo_list = File.readlines(@@file_location)
  rescue
    puts "File not found: #{@@file_location}"
    exit
  end
  tests = []
  todo_list.each do |item|
    next if (0 == (item =~ /\s+/)) # skip on empty lines
    tests << Test.new( item )
  end
  tests
end


####  main running loop
while true
  system "clear"
  # reset launch limit
  @@launched = 0

  # load up the todo list
  tests = check_todo_list

  # Iterate over and process each test
  tests.each do |test|
    puts "Processing #{test.get_line}"
    test.process
  end

  # save updated todo list
  File.open(@@file_location, 'w') do |file|
    tests.each do |test|
      file.puts test.get_line
    end
  end
  system("todo list")

  done = false
  tests.each do |test|
    done = true if test.done?
  end

  if done
    puts "ALL TESTS PROCESSED, SHUTTING DOWN".fg 'green'
    exit 0
  end

  wait_seconds = 15
  (1..wait_seconds).each do |i|
    print "Sleeping #{wait_seconds- i} seconds\r"
    sleep 1
  end
end
