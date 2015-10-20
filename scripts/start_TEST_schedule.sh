#!/bin/bash

cd /root/nightly_test_runner

scripts/test_google_ubu14_monitoring.sh
sleep 1

scripts/start_test_runner.sh
