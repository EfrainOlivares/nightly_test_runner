#!/bin/bash -ex

# Setup directory for test_runner config files
mkdir /root/.test_runner

# add todo shell application and it's config file
cp todofiles/todo.sh /usr/local/bin/todo
cp todofiles/todo.cfg /root/.test_runner/config

# jenkins api confif gile
mkdir /root/.jenkins_api_client
cp config/jenkins_login.yml /root/.jenkins_api_client/login.yml

# right_api_client config file
mkdir /root/.right_api_client
cp config/api_login.yml /root/.right_api_client/login_test_runner.yml

# install gems at system level so we can use without bundler, optional
# bundle install --system
