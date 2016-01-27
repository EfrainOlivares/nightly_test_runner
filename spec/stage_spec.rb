require_relative '../lib/stage.rb'

# Short class to act as mock for TestInterface.
#   We need to know which action was called, so this mainly consists of stubs which set @action_called to
#   the name of the action requested from the test object.  The real object would actually trigger something
#   via one of the APIs.
#
class TestInterface
  attr_accessor :stage, :action_called
  def initialize
    @stage = nil
    @action = nil
  end

  %w(abort_job wait launch_destroyer launch_if_cleared).each do |method|
    define_method(method) do
      @action_called = method
    end
  end
end

Data = Struct.new(:percept, :stage)

describe 'Stage class behavior' do
  context 'When starting a new job which has not been run before, the DestroyAndRerun stage' do
    before(:each) do
      @test_interface = TestInterface.new
      @test_interface.stage = DestroyAndRerun
    end

    it 'should try to launch IF there is no deployment, and build and destroyer are not running' do
      test_data = [
        Data.new({deployment: 'down', build: 'same', job_status: 'passed', destroyer_status: 'passed'}, StageLaunch),
        Data.new({deployment: 'down', build: 'same', job_status: 'failed', destroyer_status: 'failed'}, StageLaunch),
      ]
      test_data.each do |data|
        DestroyAndRerun.process(@test_interface, data.percept)
        expect(@test_interface.stage).to eq(data.stage)
        expect(@test_interface.action_called.nil?).to be(true)
      end
    end

    it 'should abort the job if the job is already running' do
      test_data = [
        Data.new({deployment: 'up', build: 'same', job_status: 'running', destroyer_status: 'passed'}, DestroyAndRerun),
        Data.new({deployment: 'down', build: 'same', job_status: 'running', destroyer_status: 'failed'}, DestroyAndRerun),
      ]

      test_data.each do |data|
        DestroyAndRerun.process(@test_interface, data.percept)
        expect(@test_interface.stage).to eq(data.stage)
        expect(@test_interface.action_called).to eq('abort_job')
      end
    end

    it 'should wait for destroyer to complete if it is already running' do
      test_data = [
        Data.new({deployment: 'up',   build: 'same', job_status: 'success', destroyer_status: 'running'}, DestroyAndRerun),
        Data.new({deployment: 'down', build: 'same', job_status: 'failed', destroyer_status: 'running'}, DestroyAndRerun),
      ]
      test_data.each do |data|
        DestroyAndRerun.process(@test_interface, data.percept)
        expect(@test_interface.stage).to eq(data.stage)
        expect(@test_interface.action_called).to eq('wait')
      end
    end

    it 'should launch destroyer if the deployment is up' do
      test_data = [
        Data.new({deployment: 'up', build: 'same', job_status: 'success', destroyer_status: 'success'}, DestroyAndRerun),
        Data.new({deployment: 'up', build: 'same', job_status: 'failed', destroyer_status: 'failed'}, DestroyAndRerun),
      ]
      test_data.each do |data|
        DestroyAndRerun.process(@test_interface, data.percept)
        expect(@test_interface.stage).to eq(data.stage)
        expect(@test_interface.action_called).to eq('launch_destroyer')
      end
    end

    it 'should transition to StageLaunch if deployment is down, and job and destroyer are not running' do
      test_data = [
        Data.new({deployment: 'down', build: 'same', job_status: 'success', destroyer_status: 'success'}, StageLaunch),
        Data.new({deployment: 'down', build: 'same', job_status: 'failed', destroyer_status: 'failed'}, StageLaunch),
        Data.new({deployment: 'down', build: 'same', job_status: 'aborted', destroyer_status: 'failed'}, StageLaunch),
      ]
      test_data.each do |data|
        DestroyAndRerun.process(@test_interface, data.percept)
        expect(@test_interface.stage).to eq(data.stage)
        expect(@test_interface.action_called).to be_nil
      end
    end
  end

  context 'When a test job is ready to run, StageLaunch stage' do
    before(:each) do
      @test_interface = TestInterface.new
      @test_interface.stage = StageLaunch 
    end

    it 'should launch the jenkins job IF there is no deployment, and build and destroyer are not running' do
      test_data = [
        Data.new({deployment: 'down', build: 'same', job_status: 'passed', destroyer_status: 'passed'}, StageLaunch),
        Data.new({deployment: 'down', build: 'same', job_status: 'failed', destroyer_status: 'failed'}, StageLaunch),
        Data.new({deployment: 'down', build: 'same', job_status: 'aborted', destroyer_status: 'failed'}, StageLaunch),
      ]
      test_data.each do |data|
        StageLaunch.process(@test_interface, data.percept)
        expect(@test_interface.stage).to eq(data.stage)
        expect(@test_interface.action_called).to eq('launch_if_cleared')
      end
    end

    it 'should transition to Running stage IF a new build is detected and job is running' do
      test_data = [
        Data.new({deployment: 'down', build: 'next', job_status: 'running', destroyer_status: 'passed'}, Running),
        Data.new({deployment: 'down', build: 'next', job_status: 'running', destroyer_status: 'failed'}, Running),
        Data.new({deployment: 'down', build: 'next', job_status: 'running', destroyer_status: 'aborted'}, Running),
      ]
      test_data.each do |data|
        StageLaunch.process(@test_interface, data.percept)
        expect(@test_interface.stage).to eq(data.stage)
        expect(@test_interface.action_called).to be_nil 
      end
    end

  end
end
