#!/bin/bash

cd /root/nightly_test_runner

scripts/get_jobs_all.sh
sleep 1

scripts/start_test_runner.sh
