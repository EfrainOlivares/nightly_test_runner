
# Get all google jobs except smoke tests (already on)
ls /var/lib/jenkins/jobs | grep ^rl10.*AWS.* | grep -v life_cycle
ls /var/lib/jenkins/jobs | grep ^rl10.*Google.* | grep -v life_cycle
ls /var/lib/jenkins/jobs | grep ^rl10.*OST.*    | grep -v life_cycle
ls /var/lib/jenkins/jobs | grep ^rl10.*SL_DAL.* | grep -v life_cycle

# Get all Smoke tests
ls /var/lib/jenkins/jobs | grep ^rl10.*life_cycle*


