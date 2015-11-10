#!/usr/bin/env ruby
require 'yaml'
require 'jenkins_api_client'
require 'pry'
require 'pry-byebug'
require 'tco'

# Description:  This script is intended to provide access to a remote jenkins.
#
# Usually, the nigntly automation will run on the same master jenkins.  When that
# is the case, getting a list of available jobs is as easy as 'ls /var/lib/jenkins/jobs'
# A list of the jobs to run is consumed by the test_runner.
# However, with the need to run linux, windows and publish matrices, and two different cloud accounts,
# it is desired goal to be able to run all masters from one single machine.  This nightly_test_runner
# is a start.  In particular, this script, (jclient) gives you access to job lists from remote jenkins
# servers.  Future updates will allow multiple jenkins servers, and thus all matrices run from one monkey.
#
# This repo is still a WIP

@client_opts = YAML.load_file(File.expand_path("~/.jenkins_api_client/login.yml"))
@prefix = 'rl10'

class Matrix
  attr_reader :client
  attr_reader :jobs, :z_jobs, :all_jobs
  attr_accessor :debug
  @jobs = nil
  @client = nil
  @temp_jobs = nil

  def initialize(opts, prefix)
    @debug = false
    @client = JenkinsApi::Client.new(opts)
    @prefix = prefix
    @jobs = @client.job.list_all.reject { |job| job =~ /#{@prefix}_000/ || job !~ /rl10/ }
    raise "No jobs retrieved" if @jobs.nil?
    self.check
  end

  ['build', 'enable', 'disable'].each do |meth|
    define_method(meth) do |arg|
      action(meth, arg)
    end
  end

  def reload
    @jobs = @client.job.list_all.reject { |job| job =~ /#{@prefix}_000/ || job !~ /rl10/ }
    @jobs.nil? ? (raise "MATRIX RELOAD FAILED!") : info("MATRIX RELOADED!")
  end

  def check
    puts "PREFIX: #{@prefix}".fg 'yellow'
    puts "Jobs: #{@jobs.length} including destroyers".fg 'yellow'
  end

  def select(regex, status = "any")
    case status
    when "any"
      @temp_jobs = @jobs.select { |job| job =~ /#{regex}/ }
    when "not_green"
      @temp_jobs = @jobs.select { |job| job =~ /#{regex}/ && @client.job.status(job) != 'success' }
    end
    self
  end

  def show
    @temp_jobs.each { |job| puts job.fg 'yellow' }
    nil
  end

  def clear
    @temp_jobs = nil
    info "Cleared temp jobs, nothing to do"
    nil
  end


  private
  def countdown(seconds)
    seconds.times { |i| print "countdown: #{seconds - i}  ".fg 'green'; print "\r"; sleep 1 }
  end

  def info(str)
    puts str.fg 'green'
  end

  def action(act, gap)
    @temp_jobs.each do |job|
      @debug ? info("DEBUG: #{act} #{job}") : @client.job.method(act.to_sym).call(job)
      info "Sleeping for #{gap} seconds"
      countdown(gap)
    end
  end
end

matrix = Matrix.new(@client_opts, @prefix)

binding.pry
puts
