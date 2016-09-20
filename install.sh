#!/usr/bin/env bash

PREFIX=/opt

ATHENA_PLUGIN_GIT=git@github.com:athena-oss/athena.git
ATLAS_PLUGIN_GIT=git@github.com:naspersclassifieds-shared/athena-plugin-atlas.git

function check_for_toolset()
{
  for command in ssh git; do
    if ! which "$command" >/dev/null 2>&1; then
      error "missing command '$command', please ensure that this is available on your system"
    fi
  done

  if ! which curl >/dev/null 2>&1 && ! which wget >/dev/null 2>&1; then
    error "neither 'curl' nor 'wget' are installed on your system, please install at least one of them"
  fi
}

function get()
{
  if which curl >/dev/null 2>&1; then
    curl -Lqs "$@"
  else
    wget -O- "$@"
  fi
}

function version()
{
  # http://stackoverflow.com/questions/4023830/how-compare-two-strings-in-dot-separated-version-format-in-bash$
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}

function print_out()
{
  local prefix=$1 ; shift
  local line

  for line in "$@"; do
    printf "%-5s: %s\n" "$prefix" "$line"
  done
}

function info()
{
  print_out "INFO" "$@"
}

function error()
{
  print_out "ERROR" "$@"
  exit 1
}

function uninstall()
{
  info "Removing atlas toolkit..."
  sudo rm -rf "$PREFIX/atlas-toolkit"
  sudo rm -f /usr/local/bin/atlas
}

function install_bin_script()
{
  info "Creating wrapper script in /usr/local/bin/atlas"
  sudo tee /usr/local/bin/atlas <<EOF >/dev/null
#!/usr/bin/env bash

"$PREFIX/atlas-toolkit/athena" atlas "\$@"
EOF
  sudo chmod a+x /usr/local/bin/atlas
}

function get_version()
{
  local tmp_file=$(mktemp atlas_version.XXXXX)
  get "https://github.com/naspersclassifieds-shared/atlas-web-development-environment-variables/raw/master/variables.sh" >"$tmp_file" \
    || error "the latest version couldn't be determined"

  source "$tmp_file"; rm "$tmp_file"

  echo "$ATLAS_PLUGIN_VERSION"
}

function get_installed_version()
{
  if [ -f "$PREFIX/atlas-toolkit/plugins/atlas/version.txt" ]; then
    cat "$PREFIX/atlas-toolkit/plugins/atlas/version.txt"
  fi
}

function has_github_access()
{
  ssh -T git@github.com 2>&1 | grep -q 'successfully authenticated'
}

function get_atlas_plugin()
{
  local version=$1
  local tmp_dir=$(mktemp -d atlas.XXXXX)

  git clone --depth=1 --branch v$version  "$ATLAS_PLUGIN_GIT" "$tmp_dir"

  echo "$tmp_dir"
}

function get_athena()
{
  local version=$1
  local tmp_dir=$(mktemp -d athena.XXXXX)

  git clone --depth=1 --branch v$version "$ATHENA_PLUGIN_GIT" "$tmp_dir"

  echo "$tmp_dir"
}

function install_athena()
{
  sudo mv "$1" "$PREFIX/atlas-toolkit"
}

function install_atlas_plugin()
{
  sudo mv "$1" "$PREFIX/atlas-toolkit/plugins/atlas"
}

function get_athena_version()
{
   (source "$1/dependencies.ini"; echo $base)
}

function install()
{
  local plugin_file
  local answer
  local need_uninstall=false

  INSTALLABLE_VERSION=$(get_version)
  [ $? -ne 0 ] && error "determining the installable version was not possible"

  INSTALLED_VERSION=$(get_installed_version)

  if [ -n "$INSTALLED_VERSION" ]; then
    if [ $(version "$INSTALLED_VERSION") -lt $(version "$INSTALLABLE_VERSION") ]; then
      info "You have already atlas tookit installed in a newer version ($INSTALLED_VERSION)," \
           "do you want to downgrade to version $INSTALLABLE_VERSION? (y/N)"
    elif [ $(version "$INSTALLED_VERSION") -eq $(version "$INSTALLABLE_VERSION") ]; then
      info "You have already atlas toolkit installed in this version $INSTALLED_VERSION," \
           "do you want to reinstall it? (y/N)"
    else
      info "You have already atlas toolkit installed in version $INSTALLED_VERSION," \
        "so do you want to update it to $INSTALLABLE_VERSION? (y/N)"

    fi

    read answer

    if [ "$answer" != "y" -a "$answer" != "yes" ]; then
      info "Installation aborted.."
      exit 0
    fi

    need_uninstall=true
  fi

  if ! has_github_access; then
    error "please setup github to use SSH keys like described in" \
          "https://help.github.com/articles/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent/"
  fi

  local tmp_atlas_plg=$(get_atlas_plugin "$INSTALLABLE_VERSION")
  local tmp_athena=$(get_athena $(get_athena_version "$tmp_atlas_plg"))


  info "Root permissions are required to install this toolkit.."

  if [ "$need_uninstall" == true ]; then
    uninstall
  fi

  install_athena "$tmp_athena"
  install_atlas_plugin "$tmp_atlas_plg"

  install_bin_script

  info "Installation succeeded.. please use atlas by calling 'atlas' on the commandline"
}

function main()
{
  local system=$(uname -s)

  case "$system" in
    Linux|Darwin)
      check_for_toolset
      install
      ;;
    *)
      error "your operatingsystem '$system' is unsupported"
      ;;
  esac
}

main
