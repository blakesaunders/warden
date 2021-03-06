#!/usr/bin/env bash
[[ ! ${WARDEN_COMMAND} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!" && exit 1

source "${WARDEN_DIR}/utils/env.sh"
WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?

if (( ${#WARDEN_PARAMS[@]} == 0 )); then
    echo -e "\033[33mThis command has required params, please use --help for details.\033[0m"
    exit 1
fi

## disable sync command on non-darwin environments where it should not be used
if [[ ${WARDEN_ENV_SUBT} != "darwin" ]]; then
    >&2 echo -e "\033[31mMutagen sync sessions are not used on \"${WARDEN_ENV_SUBT}\" host environments\033[0m"
    exit 1
fi

## attempt to install mutagen if not already present
if ! which mutagen >/dev/null; then
    echo -e "\033[33mMutagen could not be found; attempting install via brew.\033[0m"
    brew install havoc-io/mutagen/mutagen
fi

## verify mutagen version constraint
MUTAGEN_VERSION=$(mutagen version 2>/dev/null) || true
if ! { \
     (( $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f1) >= 1 )) \
  || (( $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f1) == 0 && $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f2) >= 11 )) \
  || (( $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f1) == 0 && $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f2) == 10 && $(echo ${MUTAGEN_VERSION:-0} | cut -d. -f3) >= 3 )); }
then
  >&2 printf "\e[01;31mMutagen version 0.10.3 or greater is required (version ${MUTAGEN_VERSION} is installed).\033[0m"
  >&2 printf "\n\nPlease update Mutagen:\n\n  brew upgrade havoc-io/mutagen/mutagen\n\n"
  exit 1
fi

## if no mutagen configuration file exists for the environment type, exit with error
if [[ ! -f "${WARDEN_DIR}/environments/${WARDEN_ENV_TYPE}.mutagen.yml" ]]; then
    >&2 echo -e "\033[31mMutagen configuration does not exist for environment type \"${WARDEN_ENV_TYPE}\"\033[0m"
    exit 1
fi

## sub-command execution
case "${WARDEN_PARAMS[0]}" in
    start)
        ## terminate any existing sessions with matching env label
        mutagen sync terminate --label-selector "warden-sync=${WARDEN_ENV_NAME}"

        ## create sync session based on environment type configuration
        mutagen sync create -c "${WARDEN_DIR}/environments/${WARDEN_ENV_TYPE}.mutagen.yml" \
            --label "warden-sync=${WARDEN_ENV_NAME}" \
            "${WARDEN_ENV_PATH}${WARDEN_WEB_ROOT:-}" "docker://$(warden env ps -q php-fpm)/var/www/html"
        
        ## wait for sync session to complete initial sync before exiting
        echo "Waiting for initial synchronization to complete"
        while !  mutagen sync list --label-selector "warden-sync=${WARDEN_ENV_NAME}" \
            | grep -i 'watching for changes'>/dev/null; do printf .; sleep 1; done; echo
        ;;
    stop)
        ## terminate only sessions labeled with this env name
        mutagen sync terminate --label-selector "warden-sync=${WARDEN_ENV_NAME}"
        ;;
    list)
        ## list only sessions labeled with this env name
        [[ ${WARDEN_VERBOSE} ]] && MUTAGEN_ARGS=" -l " || MUTAGEN_ARGS=
        mutagen sync list ${MUTAGEN_ARGS} --label-selector "warden-sync=${WARDEN_ENV_NAME}"
        ;;
    *)
        echo -e "\033[33mThe command \"${WARDEN_PARAMS[0]}\" does not exist. Please use --help for usage."
        exit 1
        ;;
esac
