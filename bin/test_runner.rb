#!/usr/bin/env ruby
require 'jenkins_api_client'
require 'right_api_client'
require 'forwardable'
require 'tco'
require 'pry'
require 'pry-byebug'

class Test
  attr_accessor :todo_string, :stage_id, :stage, :name, :status, :next, :opts
  attr_accessor :percepts, :jclient, :rsclient
  extend Forwardable
  def_delegators :@stage, :process 
  def_delegators :@stage, :total_deps_up

  def initialize(string, jclient, rsclient)
    elems = string.split(' ')
    @percepts = {}
    if elems.length == 1
      @stage = Staging
      @name = string.chomp
      @percepts[:dup]  = "unknown"
      @percepts[:job_status] = "unknown"
      @percepts[:des_status] = "unknown"
    elsif elems.length == 5
      @stage  = eval elems[0]
      @name   = elems[1]
      @percepts[:dup]    = elems[2]
      @percepts[:job_status] = elems[3]
      @percepts[:des_status]   = elems[4]
    else
      error_mssg = <<-ERRORMSG.gsub(/^\s*/, "")
        ERROR:  Invalid string formation. todo strings should be one of
        - single word for name of test
        - 5 words with stage, name, depstatus, jobstatus, destroystatus
        -
        Received #{elems.length} words in string.
        -
        #{string}
      ERRORMSG
      puts error_mssg.fg 'red'
      exit 1
    end
    @jclient = jclient
    @rsclient = rsclient
    puts "#{@stage}: #{@name}\t#{@percepts.inspect}".fg 'yellow'
  end # initialize

  def is_up?
    @rsclient.deployments.index(:filter => ["name==#{@name}"]).empty? ? "down" : "up"
  end

  def get_line
    return "#{@stage} #{@name} #{@percepts[:dup]} #{@percepts[:job_status]} #{@percepts[:des_status]}"
  end

  def done?
    @stage == Done
  end

  def update_percepts
    @percepts[:dup] = is_up?
    @percepts[:job_status] = job_status 
    @percepts[:des_status] = des_status 
    puts "Updated percepts: #{@percepts.inspect}".fg 'yellow'
  end

  def job_status
    @jclient.job.get_current_build_status(@name)
  end

  def des_status
    @jclient.job.get_current_build_status("Z_#{@name}")
  end

  def launch_job
    build_jenkins_job(@name, -3)
    (-3..0).each do |i|
       sleep 10
       puts "Waiting for #{@name} to come up"
       if is_up? == "up"
         return true
       end
    end
    raise "Timeout waiting for #{@name} deployment to be created"  
  end

  def launch_destroyer
    build_jenkins_job("Z_#{@name}", -3)
  end

  def process
    @stage.process(self, @percepts)
  end

  def wait
    puts "Test #{@name} no activity to be done this round, waiting".fg 'light-blue'
  end

  private
  def build_jenkins_job(job_name, wait_seconds)
    current_launches = @jclient.job.get_builds(job_name).length
    @jclient.job.build(job_name)
    (wait_seconds..0).each do |i|
      print "Waiting #{i.abs} for #{job_name} to start\r"
      new_launches = @jclient.job.get_builds(job_name).length
      if current_launches +1 == new_launches
         puts "Registered new build for #{job_name}".fg 'yellow'
         return
      end
      sleep 10
    end
    puts "Jenkins job did not launch in #{wait_seconds} for #{job_name}".fg 'red'
  end
end

class BaseStage
  def self.subset(_opts, sub)
    subset = _opts.select { |k,v| sub.keys.include? k }
    subset == sub
  end

  def self.any(_opts, matches)
    matches.each do |key, _|
      return true if _opts[key] == matches[key] 
    end
    false
  end
     
  def self.process(test, percepts)
    raise "Base processing default should never be called"
  end

  def self.transition(test, stage)
    puts "TRANSITION: #{self} => #{stage}".fg 'yellow'
    test.stage = stage
  end
end

class Staging < BaseStage
  def self.process(test, percepts)
    case
    when any(percepts, dup: "up", job_status: "running")
      transition(test, DestroyAndRerun)
    when subset(percepts, dup: "down")
      test.launch_job
      transition(test, Running)
    end
  end
end

class Running < BaseStage
  def self.process(test, percepts)
    case
    when subset(percepts, dup: "down")
      transition(test, ErrorState)
    when subset(percepts, job_status: "running")
      test.wait
    when subset(percepts, dup: "up", job_status: "success")
      transition(test, Done)
    when subset(percepts, dup: "up", job_status: "failure")
      transition(test, Failed)
    end 
  end
end

class ErrorState < BaseStage
  def self.process(test, percepts)
  end
end

class Failed < BaseStage
  def self.process(test, percepts)
    case
    when subset(percepts, job_status: "failure")
      test.launch_destroyer
      transition(test, Done)
    when subset(percepts, job_status: "success")
      transition(test, Done)
    end
  end
end

class DestroyAndRerun < BaseStage
  def self.process(test, percepts)
    case
    when subset(percepts, job_status: "running")
      test.abort_job
    when subset(percepts, des_status: "running")
      test.wait
    when subset(percepts, dup: "up")
      test.launch_destroyer
    when subset(percepts, dup: "down")
      transition(test, Staging)
    end
  end
end

class Done < BaseStage
  def self.process(test, percepts)
  end
end


###############################################################################
# Global functions, and main loop
class Runner
  attr_accessor :options, :jclient, :rsclient
  def initialize(options, jclient, rsclient)
    raise unless @options = options
    raise unless @jclient = jclient
    raise unless @rsclient = rsclient
  end

  def check_todo_list
    raise "File location for todo list is nil" if options[:todo_file_location].nil?
    puts "Loading #{@options[:todo_file_location]}"
    begin
      todo_list = File.readlines(@options[:todo_file_location])
    rescue
      puts "File not found"
      exit
    end
    tests = []
    todo_list.each do |item|
      next if (0 == (item =~ /\s+/)) # skip on empty lines
      tests << Test.new( item , @jclient, @rsclient)
    end
    tests
  end

  def run
    ####  main running loop
    while true
      system "clear"
      # reset launch limit
      @@launched = 0
    
      # load up the todo list
      tests = check_todo_list
    
      # Iterate over and process each test
      tests.each do |test|
        test.update_percepts
        test.process
      end
    
      # save updated todo list
      File.open(@options[:todo_file_location], 'w') do |file|
        tests.each do |test|
          file.puts test.get_line
        end
      end

      system("todo list")
    
      done = false
      tests.each do |test|
        done = true if test.done?
        break unless done
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
  end
end


options = YAML.load_file(File.expand_path("~/.test_runner/options.yaml"))
jclient = JenkinsApi::Client.new(YAML.load_file(File.expand_path("~/.jenkins_api_client/login.yml")))
rsclient = RightApi::Client.new(YAML.load_file(File.expand_path('~/.right_api_client/login_test_runner.yml', __FILE__)))

runner = Runner.new(options, jclient, rsclient)
runner.check_todo_list
runner.run
