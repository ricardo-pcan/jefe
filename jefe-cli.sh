#!/bin/bash
#
# jefe.sh
#

# print text with color
out() {
#     Num  Colour    #define         R G B
#     0    black     COLOR_BLACK     0,0,0
#     1    red       COLOR_RED       1,0,0
#     2    green     COLOR_GREEN     0,1,0
#     3    yellow    COLOR_YELLOW    1,1,0
#     4    blue      COLOR_BLUE      0,0,1
#     5    magenta   COLOR_MAGENTA   1,0,1
#     6    cyan      COLOR_CYAN      0,1,1
#     7    white     COLOR_WHITE     1,1,1
    text=$1
    color=$2
    echo "$(tput setaf $color)$text $(tput sgr 0)"
}

set_dotenv(){
    echo "$1=$2" >> .jefe/.env
}

get_dotenv(){
    echo $( grep "$1" .jefe/.env | sed -e "s/$1=//g" )
}

load_dotenv(){
    project_type=$( get_dotenv "PROJECT_TYPE" )
    project_name=$( get_dotenv "PROJECT_NAME" )
    project_root=$( get_dotenv "PROJECT_ROOT" )
    dbname=$( get_dotenv "DB_NAME" )
    dbuser=$( get_dotenv "DB_USERNAME" )
    dbpassword=$( get_dotenv "DB_PASSWORD" )
    dbhost=$( get_dotenv "DB_HOST" )
}

# read yaml file
parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

get_yamlenv(){
    echo $( parse_yaml .jefe/settings.yaml | grep "^$1_$2" | sed -e "s/$1_$2=//g" | sed -e "s/\"//g")
}

load_settings_env(){
    # access yaml content
    user=$( get_yamlenv $1 user)
    group=$( get_yamlenv $1 group)
    host=$( get_yamlenv $1 host)
    public_dir=$( get_yamlenv $1 public_dir)
    dbname=$( get_yamlenv $1 dbname)
    dbuser=$( get_yamlenv $1 dbuser)
    dbpassword=$( get_yamlenv $1 dbpassword)
    dbhost=$( get_yamlenv $1 dbhost)
    execute=$( get_yamlenv $1 execute)
}

version() {
    echo 0.1
}

init() {

    # Print logo
    tput setaf 2;
    cat .jefe/logo.txt

    # create every folder needed

    out "Make directory structure." 4

    echo "Creating app directory..."
    if [[ ! -d "./app" ]]; then
        mkdir ./app
        out "done" 2
    else
        out "it already exists." 3
    fi

    echo "Creating database directory..."
    if [[ ! -d "./database" ]]; then
        mkdir ./database
        out "done" 2
    else
        out "it already exists." 3
    fi

    ###############################################################################################
    # Configure project
    ###############################################################################################
    out "Configure project" 4

    # Select type of project language
    out "Select type of project language" 5
    out "0) PHP" 5
    out "1) Ruby" 5
    echo "Type the option (number) that you want(digit), followed by [ENTER]:"
    read option

    flag=true
    while [ $flag = true ]; do
        echo $option
        case $option in
            0)
                project_type=php
                git clone -b $project_type https://git@github.com/dgamboaestrada/jefe.git
                rm -rf jefe/.git
                mv jefe .jefe
                # Docker compose var env configuration.
                docker_env
                configure_php_project
                flag=false
                ;;
            1)
                project_type=ruby
                git clone -b $project_type https://git@github.com/dgamboaestrada/jefe.git
                rm -rf jefe/.git
                mv jefe .jefe
                # Docker compose var env configuration.
                docker_env
                configure_ruby_project
                flag=false
                ;;
            *)
                out "Wrong choice:$option" 1
                project=""
                flag=true
                ;;
        esac
    done

    echo "Writing new values to .gitigonre..."
    if [[ ! -f  "./.gitignore" ]]; then
        cat .jefe/git.gitignore >> ./.gitignore
        out "it already exists." 3
    else
        while read line
        do
            if ! grep -q "$line"  "./.gitignore"; then
                echo "$line" >> ./.gitignore
            fi
        done < .jefe/git.gitignore
        out "it already exists." 3
    fi

    # Config environments.
    config_environments
}

up() {
    cd .jefe/
    docker-compose up -d
    cd ..
}

stop() {
    cd .jefe/
    docker-compose stop
    cd ..
}

down() {
    cd .jefe/
    docker-compose down -v
    cd ..
}

bluid() {
    cd .jefe/
    docker-compose build --no-cache
    cd ..
}

importdb() {
    while getopts ":e:f:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
            f)
                f=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    if [ -z "${f}" ]; then
        f="dump.sql"
    fi

    load_dotenv
    if [[ "$e" == "docker" ]]; then
        if [[ "$project_type" == "php" ]]; then
            docker exec -i ${project_name}_db mysql -u ${dbuser} -p"${dbpassword}" ${dbname}  < ./database/${f}
        fi
        if [[ "$project_type" == "ruby" ]]; then
            docker exec -i "${project_name}_db" psql -d $dbname -U $dbuser < ./database/$f
        fi
    else
        load_settings_env $e
        if [[ "$project_type" == "php" ]]; then
            ssh "${user}@${host} 'mysql -u ${dbuser} -p\"${dbpassword}\" ${dbname} --host=${dbhost} < ./database/${f}'"
        fi
        if [[ "$project_type" == "ruby" ]]; then
            ssh "${user}@${host} 'psql -d $dbname -U $dbuser < ./database/$f'"
        fi
    fi
}

dumpdb() {
    while getopts ":e:f:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
            f)
                f=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    if [ -z "${f}" ]; then
        f="dump.sql"
    fi

    load_dotenv
    if [[ "$e" == "docker" ]]; then
        if [[ "$project_type" == "php" ]]; then
            docker exec ${project_name}_db mysqldump -u ${dbuser} -p"${dbpassword}" ${dbname}  > ./database/${f}
        fi
        if [[ "$project_type" == "ruby" ]]; then
            docker exec "${project_name}_db" pg_dump -U $dbuser $dbname > ./database/${f}
        fi
    else
        load_settings_env $e
        if [[ "$project_type" == "php" ]]; then
            ssh "${user}@${host} 'mysqldump -u ${dbuser} -p\"${dbpassword}\" ${dbname}  > ./database/${f}'"
        fi
        if [[ "$project_type" == "ruby" ]]; then
            ssh "${user}@${host} 'pg_dump -U $dbuser $dbname > ./database/${f}'"
        fi
    fi
}

resetdb() {
    while getopts ":e:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    if [[ "$e" == "docker" ]]; then
        load_dotenv
        if [[ "$project_type" == "php" ]]; then
            docker exec -i ${project_name}_db mysql -u"${dbuser}" -p"${dbpassword}" -e "DROP DATABASE IF EXISTS {dbname}; CREATE DATABASE ${dbname}"
        fi
        if [[ "$project_type" == "ruby" ]]; then
            echo "Not yet implemented"
        fi
    else
        cd .jefe/
        fab environment:${e},true resetdb
        cd ..
    fi
}

drop_tables() {
    while getopts ":e:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    cd .jefe/
    fab environment:${e},true drop_tables
    cd ..
}

deploy() {
    while getopts ":e:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    cd .jefe/
    fab environment:${e},true deploy
    cd ..
}

backup() {
    while getopts ":e:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    cd .jefe/
    fab environment:${e},true backup
    cd ..
}

execute() {
    while getopts ":e:" option; do
        case "${option}" in
            e)
                e=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${e}" ]; then
        e="docker"
    fi

    cd .jefe/
    fab environment:${e},true execute
    cd ..
}

ps() {
    docker ps
}

it() {
    while getopts ":c:" option; do
        case "${option}" in
            c)
                c=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${c}" ]; then
        c="docker-php_php"
    fi

    cd .jefe/
    fab it:${c}
    cd ..
}

logs() {
    while getopts ":c:" option; do
        case "${option}" in
            c)
                c=${OPTARG}
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${c}" ]; then
        c="docker-php_php"
    fi

    cd .jefe/
    fab logs:${c}
    cd ..
}

# configure php project
configure_php_project() {
    flag=true
    while [ $flag = true ]; do
        out "Select project:" 5
        out "0) Default" 5
        out "1) CakePHP2.x" 5
        out "2) CakePHP3.x" 5
        out "3) Symfony" 5
        out "4) Laravel" 5
        out "5) Drupal" 5
        out "6) Prestashop" 5
        echo "Type the option (number) from the project that you want(digit), followed by [ENTER]:"
        read option
        case $option in
            0)
                project="default"
                flag=false
                ;;
            1)
                project="cakephp2.x"
                flag=false
                ;;
            2)
                project="cakephp"
                flag=false
                ;;
            3)
                project="symfony"
                flag=false
                ;;
            4)
                project="laravel"
                flag=false
                ;;
            5)
                project="drupal"
                flag=false
                ;;
            6)
                project="prestashop"
                flag=false
                ;;
            *)
                out "Wrong choice:$option" 1
                project=""
                flag=true
                ;;
        esac
    done
    cp .jefe/nginx/vhosts/$project.conf .jefe/nginx/default.conf
}

# configure ruby project
configure_ruby_project() {
    load_dotenv
    cp .jefe/postinstall.sh ./$project_root/postinstall.sh
}

# Docker compose var env configuration.
docker_env() {
    out "Docker compose var env configuration." 4
    #     if [[ ! -f ".jefe/.env" ]]; then
    #         cp .jefe/default.env .jefe/.env
    #     fi
    echo "" > .jefe/.env
    set_dotenv PROJECT_TYPE $project_type
    out "Write project name (default docker_$project_type):" 5
    read option
    if [ -z $option ]; then
        set_dotenv PROJECT_NAME docker_$project_type
    else
        set_dotenv PROJECT_NAME $option
    fi
    out "Write project root, directory path from your proyect (default app):" 5
    read option
    if [ -z $option ]; then
        set_dotenv PROJECT_ROOT app
    else
        set_dotenv PROJECT_ROOT $option
    fi
    out "Write database name (default docker):" 5
    read option
    if [ -z $option ]; then
        set_dotenv DB_NAME docker
    else
        set_dotenv DB_NAME $option
    fi
    out "Write database username (default docker):" 5
    read option
    if [ -z $option ]; then
        set_dotenv DB_USERNAME docker
    else
        set_dotenv DB_USERNAME $option
    fi
    out "Write database password (default docker):" 5
    read option
    if [ -z $option ]; then
        set_dotenv DB_PASSWORD docker
    else
        set_dotenv DB_PASSWORD $option
    fi
}

# Config environments.
config_environments() {
    out "Config environments.." 4
    if [[ ! -f ".jefe/.settings.yaml" ]]; then
        cp .jefe/default.settings.yaml .jefe/settings.yaml
    fi
    out "Select editor to open environment settings file" 5
    out "0) Vi" 5
    out "1) Nano" 5
    echo "Type the option (number) from the editor that you want, followed by [ENTER]:"
    read option
    case $option in
        0)
            vi .jefe/settings.yaml
            ;;
        1)
            nano .jefe/settings.yaml
            ;;
        *)
            vi .jefe/settings.yaml
            ;;
    esac
}


help() {
    cd .jefe/
    fab --list
    cd ..
}

# call arguments verbatim:
$@
