#!/bin/bash -ex

# Setup directory for test_runner config files
mkdir /root/.test_runner
cp config/options.yaml /root/.test_runner/

# jenkins api confif gile
mkdir /root/.jenkins_api_client
cp loginyamls/jenkins_login.yml /root/.jenkins_api_client/login.yml

# right_api_client config file
mkdir /root/.right_api_client
cp loginyamls/api_login.yml /root/.right_api_client/login_test_runner.yml

