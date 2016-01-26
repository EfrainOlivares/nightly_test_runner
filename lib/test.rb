#!/usr/bin/env ruby
require 'jenkins_api_client'
require 'json'
require 'right_api_client'
require 'forwardable'
require 'tco'
require 'pry'
require 'pry-byebug'

# This class executes against jenkins_api_client and right_api_client to run the tests.
#   There is no behavior in this class, it simply picks up state information from a string
#   passed in during initialization and executes actions as driven by the stage classes.
#
#   This class does not transition stage.  This has an effect on how some functions behave.
#   For example, launch_if_cleared will do it's best effort to launch.  There may be various
#   reasons why it may not, we may have hit a threshold on a cloud, or jenkins won't respond.
#   The stage class will react on next iteration depending on what state it finds the job, in
#   other words, this class tries to execute, if it fails, the state will be dealt with the next
#   time we iterate on the jobs.
#
#   Some notes:
#     The /root/.test_runner/options.yaml file is processed here.
#       * thresholds are per cloud, (ex. "AWS_ORG" : 5).  If this is set to 0 all tests matching
#       that regex will be skipped
#       * run_anyway flag, if set to true, green dots will be rerun, otherwise they will be skipped
#
class Test
  attr_accessor :percepts, :jclient, :rsclient, :opts
  attr_accessor :stage, :thresholds, :cloud_name, :prefix
  extend Forwardable
  def_delegators :@stage, :process

  # test_in_string_format is a representation of the test state.
  # It's elements are stage, name, deployment status, jenkins job status, jenkins destroyer status
  def initialize(test_in_string_format, jclient, rsclient, opts)
    @jclient = jclient
    @rsclient = rsclient
    @opts = opts
    @thresholds = @opts[:thresholds]
    @prefix = @opts[:prefix]

    elems = test_in_string_format.split(' ')
    @percepts = {}
    if elems.size == 1
      @name = test_in_string_format.chomp
      @cloud_name = cloud_name(@name)
      if @thresholds.key?(@cloud_name) && (@thresholds[@cloud_name] == 0)
        puts "Cloud #{@cloud_name} has threshold 0, moving to Done"
        @stage = Done
      else
        init_percepts
        if opts[:run_anyway] == false && @percepts[:job_status] == 'success'
          puts 'run_always flag is off, and test passsed, going straight to Done'.fg 'yellow'
          @stage = Done
        else
          puts 'New test, set to DestroyAndRerun'.fg 'yellow'
          @stage = DestroyAndRerun
        end
      end
    elsif elems.size == 7
      @stage  = Object.const_get(elems[0])
      @percepts[:build] = elems[6]
      @percepts[:build_id] = elems[5]
      @name   = elems[1]
      @percepts[:deployment]    = elems[2]
      @percepts[:job_status] = elems[3]
      @percepts[:destroyer_status]   = elems[4]
      @cloud_name = cloud_name(@name)
    else
      @stage = Object.const_get(elems[0])
      unless @stage == Done
        error_mssg = <<-ERRORMSG.gsub(/^\s*/, '')
          ERROR:  Invalid string formation. todo strings should be one of
          - single word for name of test
          - 7 words with stage, name, depstatus, jobstatus, destroystatus, build_id, build
          -
          Received #{elems.size} words in string.
          -
          #{elems.inspect}
        ERRORMSG
        puts error_mssg.fg 'red'
        exit 1
      end
      @name = elems[1]
    end
  end # initialize

  def is_up?
    @rsclient.deployments.index(filter: ["name==#{@name}"]).empty? ? 'down' : 'up'
  end

  def get_line
    "#{@stage} #{@name} #{@percepts[:deployment]} #{@percepts[:job_status]} \
      #{@percepts[:destroyer_status]} #{@percepts[:build_id]} #{@percepts[:build]}"
  end

  def save_state_as_json
    info_hash = {}
    info_hash["#{@name}"] = {}
    info_hash["#{@name}"][:stage] = "#{@stage}"
    info_hash["#{@name}"][:percepts] = @percepts
    info_hash.to_json
  end

  def done?
    @stage == Done || @stage == Failed || @stage == ErrorState
  end

  def init_percepts
    @percepts[:deployment] = is_up?
    @percepts[:job_status] = job_status
    @percepts[:destroyer_status] = destroyer_status
    @percepts[:build_id]   = job_id
    @percepts[:build]      = 'same'
  end

  def update_percepts
    @percepts[:deployment]        = is_up?
    @percepts[:job_status] = job_status
    @percepts[:destroyer_status] = destroyer_status
    new_id = job_id
    delta = new_id.to_i - @percepts[:build_id].to_i
    unless delta == 0
      case
      when delta == 1
        @percepts[:build] = 'next'
        @percepts[:build_id] = new_id
      when delta > 1
        puts "ERROR: More than one build difference. last: #{@percepts[:build_id]} new: #{new_id}"
        @percepts[:build_id] = 'error'
      end
    end
    puts "#{@stage} #{@name} #{@percepts.inspect}".fg 'yellow'
  end

  def job_id
    jenkins_client_job(:build_number, @name)
  end

  def job_status
    jenkins_client_job(:get_current_build_status, @name)
  end

  def destroyer_status
    jenkins_client_job(:get_current_build_status, "Z_#{@name}")
  end

  def launch_if_cleared
    if @thresholds.key? @cloud_name
      allowed = @thresholds[@cloud_name]
      current =  total_deps_up("#{@prefix}_#{@cloud_name}")
      if current < allowed
        puts "Threshold clear, currently #{current} up out of #{allowed}".fg 'yellow'
        launch_job
      else
        puts "Holding on #{@name} launch.".fg 'yellow'
        puts "Hit allowed limit.  #{current} deployments out of #{allowed} running.".fg 'yellow'
      end
    else
      puts "No limit on number of deployments found, launching #{@name}"
      launch_job
    end
  end

  def launch_job
    build_status = build_jenkins_job(@name, 9)
    unless build_status.nil?
      (0..9).each do |_i|
        sleep 10
        puts "Waiting for #{@name} to come up"
        if is_up? == 'up'
          return true
        end
      end
      puts "Timeout waiting for #{@name} deployment to be created".fg 'red'
    end
    @percepts[:build] = 'error'
  end

  def abort_job
    jenkins_client_job(:abort, "#{@name}")
  end

  def abort_destroyer
    jenkins_client_job(:abort, "Z_#{@name}")
  end

  def launch_destroyer
    build_jenkins_job("Z_#{@name}", 3)
  end

  def process
    @stage.process(self, @percepts)
  end

  def wait
    puts 'No-op waiting'.fg 'light-blue'
  end

  private

  def jenkins_client_job(command, arg)
    tries ||= 5
    @jclient.job.send(command, arg)
  rescue
    sleep 1
    puts "Retrying jenkins api command #{command}"
    (tries -= 1) > 0 ? retry : (puts 'Jenkins client exception, retrying')
  end

  def cloud_name(name)
    # The rocket monkey naming convention goes like this:
    # prefix_cloud_region_testname...
    # What this test calls cloud name is actually 'cloud_region'
    # So split on _ and get those two, for example.
    # rl10lin_Google_Silicon_monitoring...
    # yields 'Google_Silicon' as cloud name.
    name.split('_')[1..2].join('_')
  end

  def total_deps_up(filter)
    tries ||= 5
    @rsclient.deployments.index(filter: ["name==#{filter}"]).size
  rescue
    sleep 1
    (tries -= 1) > 0 ? retry : (puts 'RightApi client exception, retrying')
  end

  def build_jenkins_job(job_name, wait_seconds)
    current_launches = @jclient.job.get_builds(job_name).size
    jenkins_client_job(:build, job_name)
    (0..wait_seconds).each do |i|
      print "Waiting #{wait_seconds - i} for #{job_name} to start\r"
      arr_new_launches = jenkins_client_job(:get_builds, job_name)
      next if arr_new_launches.nil?
      new_launches = arr_new_launches.size
      if current_launches + 1 == new_launches
        puts "Registered new build for #{job_name}".fg 'yellow'
        return new_launches
      end
      sleep 10
    end
    puts "Jenkins job did not launch in #{wait_seconds} for #{job_name}".fg 'red'
    nil
  end
end
