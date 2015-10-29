#!/bin/bash -e

# Setup directory for test_runner config files
if [[ ! -d /root/.test_runner ]];then
  mkdir /root/.test_runner
fi
cp config/options.yaml /root/.test_runner/

# jenkins api confif gile
if [[ ! -d /root/.jenkins_api_client ]];then
  mkdir /root/.jenkins_api_client
fi
cp loginyamls/jenkins_login.yml /root/.jenkins_api_client/login.yml

# right_api_client config file
if [[ ! -d /root/.right_api_client ]];then
  mkdir /root/.right_api_client
fi
cp loginyamls/api_login.yml /root/.right_api_client/login_test_runner.yml

