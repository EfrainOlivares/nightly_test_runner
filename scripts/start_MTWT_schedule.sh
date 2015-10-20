#!/bin/bash

cd /root/nightly_test_runner

scripts/get_jobs_all_except_aws.sh
sleep 1

scripts/start_test_runner.sh
