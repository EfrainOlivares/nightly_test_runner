#!/bin/bash

JOB_DIR=/var/lib/jenkins/jobs

ls $JOB_DIR | grep -v 000 \
            | grep ^rl10  \
            | grep Google \
            | grep Ubu14 \
            | grep monitoring \
            > ~/.test_runner/jobs.txt
# insert `| sort -R` to get a random list
