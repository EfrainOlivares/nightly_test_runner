# nightly_test_runner

## Pre-requisites
 * A [VirtualMonkey](https://us-4.rightscale.com/acct/2901/server_templates/354717004#scripts) server up and running through the Boot Sequence.
 * Run the Operational Script: [MONKEY_install_jenkins_RL10](https://us-4.rightscale.com/acct/2901/right_scripts/545186004)
 * Run the Operational Script: [MONKEY_setup_rocketmonkey_RL10](https://us-4.rightscale.com/acct/2901/right_scripts/547189004)
 * Run the Operational Script: [MONKEY_setup_nightly_automation_RL10](https://us-4.rightscale.com/acct/2901/right_scripts/550573004)
 * The repo servertemplate\_qa\_test\_configuration is cloned and you've setup the config files for RocketMonkey
 * Jenkins should a matrix loaded for rightlinklite\_tests jobs

## The MONKEY_setup_nightly_automation_RL10 script above should have done the following:
 * Clone the repo to /root/nightly\_test\_runner
 * Run the setup.sh script
 * add your credentials to the .jenkins\_api\_client/login.yml and .right\_api\_client/login.yml

## Basic operation overview of how the scipt works.
At it's most basic level, the script that does the work starts with /root/nightly_test_runner/test_runner.rb.  This script
uses lib/stage.rb and lib/test.rb.  It will roughly take the following steps.
 * On startup, it will read the /root/.test_runner/options.yaml
    *  jobs_file_location is a path to the config fila
    *  prefix - This prefix should be present in all jenkins jobs and deployments the nightly runner will handle.
    *  Thresholds: This is a hash of cloud names, each value is the number of deployments allowed to run at a given time.  (5 default)
    *  run_anyway:  If this is set to true, it will rerun jenkins jobs with a passing result.  Otherwise it will skip them.

## Actually running the script
 * Create a text file containing the name of the jenkins jobs you want to run in job_file_location.
 * Open the options file and set the approriate prefix, thresholds and run_anyway status.
 * cd into /root/night_test_runner, and run bin/test_runner.rb

## What does it actually do?
It is easier to think of what it does for one job first.
 * Check if job is runnable, (no deployment, job is stopped, destroyer is stopped).
 * If it is not runnable, take appropriate actions until it is runnable.
 * Once it is runnable, trigger the jenkins job
 * If the job is successful, mark it done.
 * If the job was a failure, run the destroyer and mark it done.

It will do the above steps for every job on the list.  On the next level up it will...
 * Iterate through the list of jobs and gather state information about deployment, jobs status.
 * Take appropriate action for a job and move on to the next one. (Say trigger destroyer, or run the job etc)
 * Once it goes through the whole list, it saves status to file and goes to sleep.
 * It will iterate over and over until all jobs are marked done.
 

## Running existing lists of jobs.
 * In the scripts folder, you'll find a couple of scripts to start nightly automation. The next section explains how they work.

## Creating a list of jobs
 * Simply use ```ls /var/lib/jenkins/jobs``` to get a list if all existing jobs.
 * Using a series of greps, remove jobs from the list.
 * Example ```ls /var/lib/jenkins/jobs | grep -v 000 | grep ^rl10lin | grep -v AWS``` would get you
all existing jobs (no destructors) except for the AWS cloud.  If you inspect scripts/start_MTWT_schedule.sh
you'll see it's simply calling a script to do that in bash.

## Using a list of jobs
 * After you've created a list of jobs copy them to a file in ~/.test_runner/job_list
 * cd into /root/nightly_test_runner and execute ```bin/test_runner```

## What test\_runner execution does.
 * It opens the job_list file and will walk through that list every 30 seconds.
 * Every time it walks through the list, it will query for job information using jenkins and rightscale apis.
 * It will get deployment up or down status, jenkins job status, and jenkins destroyer status.
 * Based on those status' it will determing whether to launch, or clean up and then launch the jobs.
 * After a job terminates, it will call the destroyer to clean up.
 * As it walks the list every 30 seconds, it will update the text file with what stage it is in, 
     for example, it wlll label jobs as Staging, or Running, or Done to show where it is in the process.

## Using the ~/.test\_runner config file.
 The config file contains several parameters to help control the flow of the jobs.

### job_list\_file\_location
 * Set location and name for the file containing the list of jobs to run.

### prefix
 * This is an important parameter.  It identifies which jobs belong to this monkey and is used in searching for and
counting the number of deployments up.

### thresholds
 * This is a hash containing the cloud name in the job name, ex. AWS_ORG, or Google_Silicon.
 * The number corresponding to the cloud indicates how many deployments it should allow up.
 * Once the number of deployments is hit for this cloud, any other builds will skip until capacity opens up.
 * Use this to throttle testing on capacitly limited clouds, while allowing other high capacity clouds to pick up speed.

### force\_run
 * When this is false, a job already run and passing will be skipped automatically.
 * When this is true, the job will be rerun anyway.
 * On a first pass you might use true to run every single job on the list.  On a second pass, you might set to false to rerun 
failed or aborted tests only.



