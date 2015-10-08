
# Get all google jobs except smoke tests (already on)
ls /var/lib/jenkins/jobs | grep ^rl10.*AWS.*life_cycle*
ls /var/lib/jenkins/jobs | grep ^rl10.*Google.*life_cycle*
ls /var/lib/jenkins/jobs | grep ^rl10.*VScale.*life_cycle*
ls /var/lib/jenkins/jobs | grep ^rl10.*OST.*life_cycle*
ls /var/lib/jenkins/jobs | grep ^rl10.*SL_DAL.*life_cycle*

# Get all Smoke tests
ls /var/lib/jenkins/jobs | grep ^rl10.*rl10_smoke_test*
