#!/usr/bin/env ruby
require 'jenkins_api_client'
require 'right_api_client'
require 'forwardable'
require 'tco'
require 'pry'
require 'pry-byebug'

require_relative '../lib/test'
require_relative '../lib/stage'

# Main class running loop.  Essentially a timed loop to keep the tests running.
#   1. Read a file with the list of jobs to be run.
#   2. Load a config file which has thresholds for each cloud.
#   3. Load rightscale and jenkins clients
#   4. Loop through Test objects, asking them to update and execute.
#   5. Check if all tests are 'done'
#   6. On each iteration, update list of running jobs to disk.
#   7. Exit when all tests report 'done'
#
#   For maintainability sake, do NOT put ANY behavior or low level actions in this file.
#   This file is concerned only with looping through the tests.
#   All behavior in terms of job/test management is in lib/stage.rb
#   All exeution, communication with jenkins/rightscale api's is in lib/test.rb
#
class Runner
  attr_accessor :options, :jclient, :rsclient
  def initialize(options, jclient, rsclient)
    @options = options
    @jclient = jclient
    @rsclient = rsclient

    # If the options file or a client is missing, do not start.
    raise unless @options
    raise unless @jclient
    raise unless @rsclient
  end

  # Loads list of jobs to run.  Initially this is just a list of names, one per line for each job.
  #     After the initial load, the file is saved on each iteration but has stage and jenkins
  #     job status information.
  def load_jobs_list
    raise 'File location for jobs list is nil' if @options[:jobs_file_location].nil?
    puts "Loading #{@options[:jobs_file_location]}"
    begin
      jobs_list = File.readlines(@options[:jobs_file_location])
    rescue
      raise "File not found at #{@options[:jobs_file_location]}"
    end
    tests = []
    jobs_list.each do |item|
      next if (0 == (item =~ /\s+/)) # skip on empty lines
      tests << Test.new(item, @jclient, @rsclient, @options)
    end
    tests
  end

  # Simple run loop.
  #     1. Load up the file with job information
  #     2. Call update, and process on each test.
  #     3. Save current status back to the jobs file
  #     4. Check if all tests are done, if not, sleep and iterate
  #
  def run
    ####  main running loop
    loop do
      # load up the jobs list
      tests = load_jobs_list

      # Iterate over and process each test
      tests.each do |test|
        next if test.done?
        test.update_percepts
        test.process
      end

      # save updated jobs list
      File.open(@options[:jobs_file_location], 'w') do |file|
        tests.each do |test|
          file.puts test.get_line
        end
      end

      # save updated jobs list in json format
      File.open(@options[:jobs_file_location].gsub('txt', 'json'), 'w') do |file|
        tests.each do |test|
          file.puts test.save_state_as_json
        end
      end

      if tests.detect { |test| !test.done? }
        wait_seconds = 15
        wait_seconds.downto(0) do |i|
          puts "Sleeping #{i} seconds"
          sleep 1
        end
      else
        puts 'ALL TESTS PROCESSED, SHUTTING DOWN'.fg 'green'
        exit 0
      end
    end
  end
end

# Program start
#     1. Load all creds for clients
#     2. Create Runner object
#     3. Start the runner.
#

options = YAML.load_file(File.expand_path('~/.test_runner/options.yaml'))
jclient = JenkinsApi::Client.new(YAML.load_file(File.expand_path('~/.jenkins_api_client/login.yml')))
rsclient = RightApi::Client.new(YAML.load_file(File.expand_path('~/.right_api_client/login_test_runner.yml', __FILE__)))

puts 'Entered runner script'
runner = Runner.new(options, jclient, rsclient)
puts 'About to start run'
runner.run
