# nightly_test_runner

## Pre-requisites
 * A VirtualMonkey vm up and running
 * It should have Jenkins running
 * The repo servertemplate\_qa\_test\_configiguration is cloned and you've setup the config files for RocketMonkey
 * Jenkins should be set up with a matrix for rightlinklite\_tests jobs


## Setting up
 * Clone the repo to /root/nightly\_test\_runner
 * Run the setup.sh script
 * add your credentials to the .jenkins\_api\_client/login.yml and .right\_api\_client/login.yml

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



