#!/usr/bin/env ruby
require 'jenkins_api_client'
require 'right_api_client'
require 'forwardable'
require 'tco'
require 'pry'
require 'pry-byebug'

runner_options = YAML.load_file("./config/options.yaml")
@@file_location = runner_options[:todo_file_location]
@@launched      = runner_options[:launched] 
@@launch_limit  = runner_options[:launch_limit] 
@@threshold     = runner_options[:threshold] 
@@cloud         = runner_options[:cloud]

client_opts = YAML.load_file(File.expand_path("~/.jenkins_api_client/login.yml"))
@@client = JenkinsApi::Client.new(client_opts)
@@api_client = RightApi::Client.new(YAML.load_file(File.expand_path('~/.right_api_client/login_test_runner.yml', __FILE__)))
#@@api_client.log = -1 
raise "Unable to instanciate right api client, please check config file" if @@api_client.nil?



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
      puts "ERROR:  Invalid string formation"
      puts "todo strings should be single word for name of test"
      puts "or 4 words with stage, name, status, next"
      puts "#{elems.inspect} length: #{elems.length}"
      raise "Invalid todo formation for #{string}"
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
end

class BaseStage
  attr_accessor :opts, :test_executor
  def initialize(_opts)
    @opts = _opts
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
    # Temp hack to exclude windows deployments.
    deployments.reject! { |d| d.name =~ /windows/ }
    deployments.length
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
    status = @@client.job.get_current_build_status(@opts[:name])
    if status == "success"
      @opts[:status] = "@success"
    end

    total_up = total_deps_up(@@cloud)
    puts "TOTAL DEPLOYMENTS UP IS #{total_up}".fg 'light-blue'
    case @opts[:status]
    when "@unknown"
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
    status = @@client.job.get_current_build_status(@opts[:name])
    puts "RUNNING #{get_line} with status #{status}"
    case @opts[:status]
    when "@running"
      # Job was running when we last checked, so let's see if we need a state transition
      case status
      when "success"
        set_stage("(C)", "@success", "+review")
      when "failure"
        set_stage("(X)", "@failure", "+review")
      end
    end
  end
end

class Failed < BaseStage
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
  wait_seconds = 15 
  (1..wait_seconds).each do |i|
    print "Sleeping #{wait_seconds- i} seconds\r"
    sleep 1 
  end
end
