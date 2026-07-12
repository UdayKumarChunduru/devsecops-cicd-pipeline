set_env_var() {
  key=$1
  value=$2
  touch .env
  if grep -q "^${key}=" .env; then
    sed -i "s#^${key}=.*#${key}=${value}#" .env
  else
    echo "${key}=${value}" >> .env
  fi
}

get_env_var() {
  key=$1
  touch .env
  value=$(grep "^${key}=" .env | cut -d '=' -f2-) || true
  echo "$value"
}

generate_strong_password() {
  python3 -c "
import random
import string
upper = random.choice(string.ascii_uppercase)
lower = random.choice(string.ascii_lowercase)
digit = random.choice(string.digits)
special = random.choice('!@#\$%^&*_-+=')
rest = ''.join(random.choices(string.ascii_letters + string.digits, k=12))
pw = list(upper + lower + digit + special + rest)
random.shuffle(pw)
print(''.join(pw))
"
}
