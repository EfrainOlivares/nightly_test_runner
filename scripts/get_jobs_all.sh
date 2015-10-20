#!/bin/bash

JOB_DIR=/var/lib/jenkins/jobs

ls $JOB_DIR | grep -v 000 \
            | grep ^rl10  \
            > ~/.test_runner/todo.txt
# insert `| sort -R` to get a random list
