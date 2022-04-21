function accept_upload_conditions(){
  top_border
  echo -e "|     ${red}~~~~~~~~~~~ [ Upload Agreement ] ~~~~~~~~~~~~${white}     |"
  hr
  echo -e "| The following function will help to quickly upload    |"
  echo -e "| logs for debugging purposes. With confirming this     |"
  echo -e "| dialog, you agree that during that process your logs  |"
  echo -e "| will be uploaded to: ${yellow}http://paste.c-net.org/${white}          |"
  hr
  echo -e "| ${red}PLEASE NOTE:${white}                                          |"
  echo -e "| Be aware that logs can contain network information,   |"
  echo -e "| private data like usernames, filenames, or other      |"
  echo -e "| information you may not want to make public.          |"
  blank_line
  echo -e "| Do ${red}NOT${white} use this function if you don't agree!          |"
  bottom_border
  while true; do
    read -p "${cyan}Do you accept? (Y/n):${white} " yn
    case "${yn}" in
      Y|y|Yes|yes|"")
        sed -i "/logupload_accepted=/s/false/true/" "${INI_FILE}"
        clear && print_header && upload_selection
        ;;
      N|n|No|no)
        clear
        main_menu
        break
        ;;
      *)
        error_msg "Invalid command!";;
    esac
  done
}

function upload_selection(){
  read_kiauh_ini
  local upload_agreed="${logupload_accepted}"
  [ "${upload_agreed}" = "false" ] && accept_upload_conditions

  local logfiles
  local klipper_logs="${HOME}/klipper_logs"
  local webif_logs="/var/log/nginx"

  function find_logfile(){
    local name=${1} location=${2}
    for log in $(find "${location}" -maxdepth 1 -type f -name "${name}" | sort -g); do
      logfiles+=("${log}")
    done
  }

  find_logfile "kiauh.log" "/tmp"
  find_logfile "klippy*.log" "${klipper_logs}"
  find_logfile "moonraker*.log" "${klipper_logs}"
  find_logfile "telegram*.log" "${klipper_logs}"
  find_logfile "mainsail*" "${webif_logs}"
  find_logfile "fluidd*" "${webif_logs}"
  find_logfile "KlipperScreen.log" "/tmp"
  find_logfile "webcamd*" "/var/log"

  ### draw interface
  local i=0
  top_border
  echo -e "|     ${yellow}~~~~~~~~~~~~~~~ [ Log Upload ] ~~~~~~~~~~~~~~${white}     |"
  hr
  echo -e "| You can choose the following files for uploading:     |"
  blank_line
  for log in "${logfiles[@]}"; do
    log=${log//${HOME}/"~"}
     ((i < 10)) && printf "|  ${i}) %-50s|\n" "${log}"
    ((i >= 10)) && printf "| ${i}) %-50s|\n" "${log}"
    i=$((i + 1))
  done
  blank_line
  back_footer
  while true; do
    read -p "${cyan}Please select:${white} " option
    if [ -n "${option}" ] && ((option < ${#logfiles[@]})); then
      upload_log "${logfiles[${option}]}"
      upload_selection
    elif [[ "${option}" == "B" || "${option}" == "b" ]]; then
      return
    else
      error_msg "Invalid command!"
    fi
  done
}

function upload_log(){
  local link
  clear && print_header
  status_msg "Uploading ${1} ..."
  link=$(curl -s --upload-file "${1}" 'http://paste.c-net.org/')
  if [ -n "${link}" ]; then
    ok_msg "${1} upload successfull!"
    echo -e "\n${cyan}###### Here is your link:${white}"
    echo -e ">>>>>> ${link}\n"
  else
    error_msg "Uploading failed!"
  fi
}
