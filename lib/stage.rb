# Stage classes define transitions between lifecycle of a test.
# This set of classes is essentially a 'Simple Reflex Agent'
#
# It is the simplest form of agent described here https://en.wikipedia.org/wiki/Intelligent_agent
# As per the article, it acts only the present set of inputs, (percepts), obtained by quering for
# various states.  These state include for example, the state of the jenkins job, if the deployment
# is up or not.  The actions are taken against the present set of states of job and deployment, and
# that matches the definition of a simple reflex agent, EXCEPT for one thing... it keeps track
# of the jenkins job build number to determine if it is the 'same' or 'next' from the point it started.
# This was done in order to keep it from going amuck in case for example, the jenkins matrix is chained.
#
# BaseStage provides some basic common functionality and does not account for any action triggering or
# transitions.
#
class BaseStage
  def self.subset(opts, sub)
    subset = opts.select { |k, _v| sub.keys.include? k }
    subset == sub
  end

  def self.any(opts, matches)
    matches.each do |key, _|
      return true if opts[key] == matches[key]
    end
    false
  end

  def self.process(test, percepts)
    raise 'Base processing default should never be called'
  end

  def self.transition(test, stage)
    puts "TRANSITION: #{self} => #{stage}".fg 'green'
    test.stage = stage
  end

  def self.action(test, action)
    puts "ACTION: #{self} stage, calling test.#{action}".fg 'green'
    test.send(action)
  end
end

# This stage is transitioned into by DestroyAndRerun, so it's starting state
#   should be
#     RightScale deployment is not created
#     Jenkins job is not running
#     Jenkins destroyer is not running
#     Jenkins Build number is the same as we started the test run
#
#   From this initial state, it wll attempt to launch, but not transition incase the launch
#     either failed or was impeded, say by a threshold as we wait for clearance on a cloud.
#     On each iteration it will check state and transition out or retry a launch.
#
#   If a launch was successful the build number will be 'next', in that case it will
#     transition accordingly.
#     'Running' if job status is running
#     'Done' if job was succesfull
#     'Failed' if job failed
#     'ErrorState' for various reasons including a jenkins abort status,
#       or a build error was detected.
#
class StageLaunch < BaseStage
  def self.process(test, percepts)
    case
    when subset(percepts, build: 'next', job_status: 'running')
      transition(test, Running)
    when subset(percepts, build: 'next', job_status: 'failure')
      action(test, 'launch_destroyer')
      transition(test, Failed)
    when subset(percepts, build: 'next', job_status: 'aborted')
      transition(test, ErrorState)
    when subset(percepts, build: 'next', job_status: 'success')
      transition(test, Done)
    when subset(percepts, build: 'error', deployment: 'down')
      transition(test, ErrorState)
    when subset(percepts, build: 'same', deployment: 'down')
      action(test, 'launch_if_cleared')
    end
  end
end

# This stage is transitioned into by StageLaunch thus its initial state should be
#   RightScale deployment up
#   Jenkins job is 'running'
#   Jenkins destroyer is not running
#   Jenkins build is 'next'
#
# In the happy path it will wait on jenkins job running, then transition to 'Done'
#   if the job passed.
#
# If the job fails, it will trigger the destroyer then transition to 'Failed'
#
# Other transition include transition to error if job is aborted.
#
class Running < BaseStage
  def self.process(test, percepts)
    case
    when subset(percepts, job_status: 'aborted')
      transition(test, ErrorState)
    when subset(percepts, job_status: 'running')
      action(test, 'wait')
    when subset(percepts, job_status: 'success')
      transition(test, Done)
    when subset(percepts, deployment: 'up', job_status: 'failure')
      action(test, 'launch_destroyer')
      transition(test, Failed)
    when subset(percepts, deployment: 'down', job_status: 'failure')
      transition(test, Failed)
    end
  end
end

# Endpoint class, represents a test run that was stopped without getting valid results.
#   Error states like aborted jenkins jobs will terminate here.
#
class ErrorState < BaseStage
  def self.process(test, percepts)
  end
end

# Endpoint class, represente a test run that detected a 'clean' run but the jenkins job
#   reported a failure (VirtualMonkey failed test)
#
class Failed < BaseStage
  def self.process(test, percepts)
  end
end

# Initial stage, calls actions to deal with an already running job, running destoyer, or
#   a deployment being up before a run.
#
# In the happy path scenario, no deployment, job and destroyer not running, it transitions to
#   StageLaunch
#
class DestroyAndRerun < BaseStage
  def self.process(test, percepts)
    case
    when subset(percepts, job_status: 'running')
      action(test, 'abort_job')
    when subset(percepts, destroyer_status: 'running')
      action(test, 'wait')
    when subset(percepts, deployment: 'up')
      action(test, 'launch_destroyer')
    when subset(percepts, deployment: 'down')
      transition(test, StageLaunch)
    end
  end
end

# Endpoint stage, it is transitioned in from Running if success on jenkins build.
#
class Done < BaseStage
  def self.process(test, percepts)
  end
end
