#!/bin/bash

JOB_DIR=/var/lib/jenkins/jobs

ls $JOB_DIR | grep -v 000 \
            | grep ^rl10  \
            | grep -v AWS \
            > ~/.test_runner/jobs.txt

# insert a `sort -R` to get a random list
