#!/bin/bash

#=======================================================================#
# Copyright (C) 2020 - 2022 Dominik Willner <th33xitus@gmail.com>       #
#                                                                       #
# This file is part of KIAUH - Klipper Installation And Update Helper   #
# https://github.com/th33xitus/kiauh                                    #
#                                                                       #
# This file may be distributed under the terms of the GNU GPLv3 license #
#=======================================================================#

set -e

### global variables
MAINSAIL_DIR="${HOME}/mainsail"
MAINSAIL_REPO_API="https://api.github.com/repos/mainsail-crew/mainsail/releases"
KLIPPER_CONFIG="${HOME}/klipper_config"

#===================================================#
#================= INSTALL MAINSAIL ================#
#===================================================#

function install_mainsail(){
  ### exit early if moonraker not found
  if [ -z "$(moonraker_systemd)" ]; then
    local error="Moonraker service not found!\n Please install Moonraker first!"
    print_error "${error}" && return
  fi
  ### checking dependencies
  local dep=(nginx)
  dependency_check "${dep[@]}"
  ### check if moonraker is already installed
  system_check_webui
  ### ask user how to handle OctoPrint, Haproxy, Lighttpd, Apache2 if found
  process_octoprint_dialog
  process_services_dialog
  ### process possible disruptive services
  process_disruptive_services

  status_msg "Initializing Mainsail installation ..."
  ### check for other enabled web interfaces
  unset SET_LISTEN_PORT
  detect_enabled_sites

  ### check if another site already listens to port 80
  mainsail_port_check

  ### ask user to install mjpg-streamer
  if ! ls /etc/systemd/system/webcamd.service 2>/dev/null 1>&2; then
    get_user_selection_mjpg-streamer
  fi

  ### ask user to install the recommended webinterface macros
  if ! ls "${KLIPPER_CONFIG}/kiauh_macros.cfg" 2>/dev/null 1>&2 || ! ls "${KLIPPER_CONFIG}"/printer_*/kiauh_macros.cfg 2>/dev/null 1>&2; then
    get_user_selection_kiauh_macros "Mainsail     "
  fi
  ### create /etc/nginx/conf.d/upstreams.conf
  set_upstream_nginx_cfg
  ### create /etc/nginx/sites-available/<interface config>
  set_nginx_cfg "mainsail"

  ### symlink nginx log
  symlink_webui_nginx_log "mainsail"

  ### copy the kiauh_macros.cfg to the config location
  install_kiauh_macros

  ### install mainsail/fluidd
  mainsail_setup

  ### install mjpg-streamer
  [ "${INSTALL_MJPG}" = "true" ] && install_mjpg-streamer

  fetch_webui_ports #WIP

  ### confirm message
  print_confirm "Mainsail has been set up!"
}

function mainsail_setup(){
  ### get mainsail download url
  MAINSAIL_DL_URL=$(curl -s "${MAINSAIL_REPO_API}" | grep browser_download_url | cut -d'"' -f4 | head -1)

  ### remove existing and create fresh mainsail folder, then download mainsail
  [ -d "${MAINSAIL_DIR}" ] && rm -rf "${MAINSAIL_DIR}"
  mkdir "${MAINSAIL_DIR}" && cd "${MAINSAIL_DIR}"
  status_msg "Downloading Mainsail ${MAINSAIL_VERSION} ..."
  wget "${MAINSAIL_DL_URL}" && ok_msg "Download complete!"

  ### extract archive
  status_msg "Extracting archive ..."
  unzip -q -o *.zip && ok_msg "Done!"

  ### delete downloaded zip
  status_msg "Remove downloaded archive ..."
  rm -rf *.zip && ok_msg "Done!"

  ### check for moonraker multi-instance and if multi-instance was found, enable mainsails remoteMode
  if [ $(ls /etc/systemd/system/moonraker* | grep -E "moonraker(-[[:digit:]]+)?\.service" | wc -l) -gt 1 ]; then
    enable_mainsail_remotemode
  fi
}

#===================================================#
#================= REMOVE MAINSAIL =================#
#===================================================#

function remove_mainsail(){
  ### remove mainsail dir
  if [ -d "${MAINSAIL_DIR}" ]; then
    status_msg "Removing Mainsail directory ..."
    rm -rf "${MAINSAIL_DIR}" && ok_msg "Directory removed!"
  fi

  ### remove mainsail config for nginx
  if [ -e "/etc/nginx/sites-available/mainsail" ]; then
    status_msg "Removing Mainsail configuration for Nginx ..."
    sudo rm "/etc/nginx/sites-available/mainsail" && ok_msg "File removed!"
  fi

  ### remove mainsail symlink for nginx
  if [ -L "/etc/nginx/sites-enabled/mainsail" ]; then
    status_msg "Removing Mainsail Symlink for Nginx ..."
    sudo rm "/etc/nginx/sites-enabled/mainsail" && ok_msg "File removed!"
  fi

  ### remove mainsail nginx logs and log symlinks
  for log in $(find /var/log/nginx -name "mainsail*"); do
    sudo rm -f "${log}"
  done
  for log in $(find ${HOME}/klipper_logs -name "mainsail*"); do
    rm -f "${log}"
  done

  ### remove mainsail_port from ~/.kiauh.ini
  sed -i "/^mainsail_port=/d" "${INI_FILE}"

  print_confirm "Mainsail successfully removed!"
}

#===================================================#
#================= UPDATE MAINSAIL =================#
#===================================================#

function update_mainsail(){
  bb4u "mainsail"
  status_msg "Updating Mainsail ..."
  mainsail_setup
  match_nginx_configs
  symlink_webui_nginx_log "mainsail"
}

#===================================================#
#================= MAINSAIL STATUS =================#
#===================================================#

function get_mainsail_ver(){
  MAINSAIL_VERSION=$(curl -s "${MAINSAIL_REPO_API}" | grep tag_name | cut -d'"' -f4 | head -1)
}

function mainsail_status(){
  mcount=0
  mainsail_data=(
    $MAINSAIL_DIR
    $NGINX_SA/mainsail
    $NGINX_SE/mainsail
  )
  #count+1 for each found data-item from array
  for md in "${mainsail_data[@]}"
  do
    if [ -e $md ]; then
      mcount=$(expr $mcount + 1)
    fi
  done
  if [ "$mcount" == "${#mainsail_data[*]}" ]; then
    MAINSAIL_STATUS="${green}Installed!${default}      "
  elif [ "$mcount" == 0 ]; then
    MAINSAIL_STATUS="${red}Not installed!${default}  "
  else
    MAINSAIL_STATUS="${yellow}Incomplete!${default}     "
  fi
}

function read_local_mainsail_version(){
  unset MAINSAIL_VER_FOUND
  if [ -e "${MAINSAIL_DIR}/.version" ]; then
    MAINSAIL_VER_FOUND="true"
    MAINSAIL_LOCAL_VER=$(head -n 1 "${MAINSAIL_DIR}/.version")
  else
    MAINSAIL_VER_FOUND="false" && unset MAINSAIL_LOCAL_VER
  fi
}

function read_remote_mainsail_version(){
  #remote checks don't work without curl installed!
  if [[ ! $(dpkg-query -f'${Status}' --show curl 2>/dev/null) = *\ installed ]]; then
    MAINSAIL_REMOTE_VER=$NONE
  else
    get_mainsail_ver
    MAINSAIL_REMOTE_VER=$MAINSAIL_VERSION
  fi
}

function compare_mainsail_versions(){
  unset MAINSAIL_UPDATE_AVAIL
  read_local_mainsail_version && read_remote_mainsail_version
  if [[ $MAINSAIL_VER_FOUND = "true" ]] && [[ $MAINSAIL_LOCAL_VER == $MAINSAIL_REMOTE_VER ]]; then
    #printf fits the string for displaying it in the ui to a total char length of 12
    MAINSAIL_LOCAL_VER="${green}$(printf "%-12s" "$MAINSAIL_LOCAL_VER")${default}"
    MAINSAIL_REMOTE_VER="${green}$(printf "%-12s" "$MAINSAIL_REMOTE_VER")${default}"
  elif [[ $MAINSAIL_VER_FOUND = "true" ]] && [[ $MAINSAIL_LOCAL_VER != $MAINSAIL_REMOTE_VER ]]; then
    MAINSAIL_LOCAL_VER="${yellow}$(printf "%-12s" "$MAINSAIL_LOCAL_VER")${default}"
    MAINSAIL_REMOTE_VER="${green}$(printf "%-12s" "$MAINSAIL_REMOTE_VER")${default}"
    # add mainsail to the update all array for the update all function in the updater
    MAINSAIL_UPDATE_AVAIL="true" && update_arr+=(update_mainsail)
  else
    MAINSAIL_LOCAL_VER=$NONE
    MAINSAIL_REMOTE_VER="${green}$(printf "%-12s" "$MAINSAIL_REMOTE_VER")${default}"
    MAINSAIL_UPDATE_AVAIL="false"
  fi
}

#================================================#
#=========== MAINSAIL THEME INSTALLER ===========#
#================================================#

function get_theme_list(){
  theme_csv_url="https://raw.githubusercontent.com/mainsail-crew/docs/master/_data/themes.csv"
  theme_csv=$(curl -s -L $theme_csv_url)
  unset t_name
  unset t_note
  unset t_auth
  unset t_url
  i=0
  while IFS="," read -r col1 col2 col3 col4; do
    t_name+=("$col1")
    t_note+=("$col2")
    t_auth+=("$col3")
    t_url+=("$col4")
    if [ ! "$col1" == "name" ]; then
      printf "|  $i) %-50s|\n" "[$col1]"
    fi
    i=$((i+1))
  done <<< "$theme_csv"
}

function ms_theme_ui(){
  top_border
  echo -e "|     ${red}~~~~~~~~ [ Mainsail Theme Installer ] ~~~~~~~${default}     | "
  hr
  echo -e "|  ${green}A preview of each Mainsail theme can be found here:${default}  | "
  echo -e "|  https://docs.mainsail.xyz/theming/themes             | "
  blank_line
  echo -e "|  ${yellow}Important note:${default}                                      | "
  echo -e "|  Installing a theme from this menu will overwrite an  | "
  echo -e "|  already installed theme or modified custom.css file! | "
  hr
  get_theme_list # dynamically generate the themelist from a csv file
  echo -e "|                                                       | "
  echo -e "|  R) [Remove Theme]                                    | "
  back_footer
}

function ms_theme_menu(){
  ms_theme_ui
  while true; do
    read -p "${cyan}Install theme:${default} " a; echo
    if [ "$a" = "b" ] || [ "$a" = "B" ]; then
      clear && advanced_menu && break
    elif [ "$a" = "r" ] || [ "$a" = "R" ]; then
      ms_theme_delete
      ms_theme_menu
    elif [ "$a" -le ${#t_url[@]} ]; then
      ms_theme_install "${t_auth[$a]}" "${t_url[$a]}" "${t_name[$a]}" "${t_note[$a]}"
      ms_theme_menu
    else
      clear && print_header
      ERROR_MSG="Invalid command!" && print_msg && clear_msg
      ms_theme_menu
    fi
  done
  ms_theme_menu
}

function check_select_printer(){
  unset printer_num

  ### get klipper cfg loc and set default .theme folder loc
  check_klipper_cfg_path
  THEME_PATH="$klipper_cfg_loc"

  ### check if there is more than one moonraker instance and if yes
  ### ask the user to select the printer he wants to install/remove the theme
  MR_SERVICE_COUNT=$(find "$SYSTEMDDIR" -regextype posix-extended -regex "$SYSTEMDDIR/moonraker(-[^0])?[0-9]*.service" | wc -l)
  if [[ $MR_SERVICE_COUNT -gt 1 ]]; then
    top_border
    echo -e "|  More than one printer was found on this system!      | "
    echo -e "|  Please select the printer to which you want to       | "
    echo -e "|  apply the previously selected action.                | "
    bottom_border
    read -p "${cyan}Select printer:${default} " printer_num

    ### rewrite the .theme path matching the selected printer
    THEME_PATH="$klipper_cfg_loc/printer_$printer_num"
  fi

  ### create the cfg folder if there is none yet
  [ ! -d "$THEME_PATH" ] && mkdir -p "$THEME_PATH"
}

function ms_theme_install(){
  THEME_URL="https://github.com/$1/$2"

  ### check and select printer if there is more than 1
  check_select_printer

  ### download all files
  status_msg "Installing $3 ..."
  status_msg "Please wait ..."

  [ -d "$THEME_PATH/.theme" ] && rm -rf "$THEME_PATH/.theme"
  cd "$THEME_PATH" && git clone "$THEME_URL" ".theme"

  ok_msg "Theme installation complete!"
  [ -n "$4" ] && echo "${yellow}###### Theme Info: $4${default}"
  ok_msg "Please remember to delete your browser cache!\n"
}

function ms_theme_delete(){
  check_select_printer
  if [ -d "$THEME_PATH/.theme" ]; then
    status_msg "Removing Theme ..."
    rm -rf "$THEME_PATH/.theme" && ok_msg "Theme removed!\n"
  else
    status_msg "No Theme installed!\n"
  fi
}

#================================================#
#=================== HELPERS ====================#
#================================================#

function mainsail_port_check(){
  if [ "${MAINSAIL_ENABLED}" = "false" ]; then
    if [ "${SITE_ENABLED}" = "true" ]; then
      status_msg "Detected other enabled interfaces:"
      [ "${OCTOPRINT_ENABLED}" = "true" ] && echo -e "   ${cyan}● OctoPrint - Port: ${OCTOPRINT_PORT}${default}"
      [ "${FLUIDD_ENABLED}" = "true" ] && echo -e "   ${cyan}● Fluidd - Port: ${FLUIDD_PORT}${default}"
      if [ "${FLUIDD_PORT}" = "80" ] || [ "${OCTOPRINT_PORT}" = "80" ]; then
        PORT_80_BLOCKED="true"
        select_mainsail_port
      fi
    else
      DEFAULT_PORT=$(grep listen "${SRCDIR}/kiauh/resources/klipper_webui_nginx.cfg" | head -1 | sed 's/^\s*//' | cut -d" " -f2 | cut -d";" -f1)
      SET_LISTEN_PORT=${DEFAULT_PORT}
    fi
    SET_NGINX_CFG="true"
  else
    SET_NGINX_CFG="false"
  fi
}

function select_mainsail_port(){
  if [ "${PORT_80_BLOCKED}" = "true" ]; then
    echo
    top_border
    echo -e "|                    ${red}!!!WARNING!!!${default}                      |"
    echo -e "| ${red}You need to choose a different port for Mainsail!${default}     |"
    echo -e "| ${red}The following web interface is listening at port 80:${default}  |"
    blank_line
    [ "${OCTOPRINT_PORT}" = "80" ] && echo "|  ● OctoPrint                                          |"
    [ "${FLUIDD_PORT}" = "80" ] && echo "|  ● Fluidd                                             |"
    blank_line
    echo -e "| Make sure you don't choose a port which was already   |"
    echo -e "| assigned to one of the other webinterfaces and do ${red}NOT${default} |"
    echo -e "| use ports in the range of 4750 or above!              |"
    blank_line
    echo -e "| Be aware: there is ${red}NO${default} sanity check for the following  |"
    echo -e "| input. So make sure to choose a valid port!           |"
    bottom_border
    while true; do
      read -p "${cyan}Please enter a new Port:${default} " NEW_PORT
      if [ "${NEW_PORT}" != "${FLUIDD_PORT}" ] && [ "${NEW_PORT}" != "${OCTOPRINT_PORT}" ]; then
        echo "Setting port ${NEW_PORT} for Mainsail!"
        SET_LISTEN_PORT=${NEW_PORT}
        break
      else
        echo "That port is already taken! Select a different one!"
      fi
    done
  fi
}

function enable_mainsail_remotemode(){
  rm -f "${MAINSAIL_DIR}/config.json"
  echo -e "{\n    \"remoteMode\":true\n}" >> "${MAINSAIL_DIR}/config.json"
}