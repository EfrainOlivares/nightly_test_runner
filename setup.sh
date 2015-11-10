#!/bin/bash -e

# Setup directory for test_runner config files
sudo install -D --owner=root --group=root --mode=0700 config/options.yaml /root/.test_runner/options.yaml

# jenkins api confif gile
sudo install -D --owner=root --group=root --mode=0700 loginyamls/jenkins_login.yml /root/.jenkins_api_client/login.yml

# right_api_client config file
sudo install -D --owner=root --group=root --mode=0700 loginyamls/api_login.yml /root/.right_api_client/login_test_runner.yml
