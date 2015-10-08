cp todo.sh /usr/local/bin/todo
mkdir /root/.test_runner
cp todo.cfg /root/.test_runner/config
bundle install --system
mkdir /root/.jenkins_api_client
cp jenkins_login.yml /root/.jenkins_api_client/login.yml
mkdir /root/.right_api_client
cp api_login.yml /root/.right_api_client/login_test_runner.yml
