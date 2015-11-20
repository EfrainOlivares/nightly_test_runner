#!/usr/bin/env ruby
require 'pry'
require 'rexml/document'
require 'jenkins_api_client'


opts = YAML.load_file(File.expand_path("~/.jenkins_api_client/login.yml"))

@client = JenkinsApi::Client.new(opts)

xml_config = @client.job.get_config("rl10lin_Google_Silicon_Ubu14_004_enable_running-base__monitoring")

doc = REXML::Document.new xml_config

def remove_create(command_text)
    command_text.gsub(/^bundle exec \"monkey create.*$/, '# this job  is created by the first job in loop')  
end

doc.elements.each("project/builders/hudson.tasks.Shell/command") do |element|
  puts element.text
  binding.pry
  new_text = remove_create(element.text)
  element.text = new_text
  puts element.get_text
end


