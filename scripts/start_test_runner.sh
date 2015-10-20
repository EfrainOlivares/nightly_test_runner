#!/bin/bash

tmux has-session -t night_run
if [ $? == 0 ];then
  echo "Previous session of night_run found, killing it now"
  tmux kill-session -t night_run
fi

echo "Starting new tmux session for night_run"
tmux new-session -s night_run -n NIGHTLY -d
tmux send-keys   -t night_run 'cd /root/nightly_test_runner' C-m
tmux send-keys   -t night_run 'bin/test_runner.rb' C-m
