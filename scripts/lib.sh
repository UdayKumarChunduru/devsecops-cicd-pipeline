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
