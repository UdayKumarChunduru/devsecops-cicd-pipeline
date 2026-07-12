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
  grep "^${key}=" .env 2>/dev/null | cut -d '=' -f2-
}
