#!/usr/bin/env bash
#
# Copyright (c) 2021 TingV
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/tingv/aria2.conf
# File name：queue.sh
# Description: Use Rclone to queue files for upload.
# Version: 1.0
#

CHECK_CORE_FILE() {
    CORE_FILE="$(dirname $0)/core"
    if [[ -f "${CORE_FILE}" ]]; then
        . "${CORE_FILE}"
    else
        echo "!!! core file does not exist !!!"
        exit 1
    fi
}

CHECK_SPECIAL_MODE() {
    if [[ "${SPECIAL_MODE}" != "queue" ]]; then
        echo -e "$(DATE_TIME) ${WARRING} SPECIAL_MODE is not \"queue\""
        exit 0
    fi
}

CHECK_RCLONE_PID() {
    PID=$(ps -ef | grep "rclone move" | grep -v grep | awk '{print $2}')
    [[ ! -z ${PID} ]] && {
        echo -e "$(DATE_TIME) ${WARRING} Rclone is uploading files, please wait."
        exit 0
    }
}

RPC_STOPPED_LIST() {
    if [[ "${RPC_SECRET}" ]]; then
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.tellStopped","id":"TingV","params":["token:'${RPC_SECRET}'",-1,1000,["gid","status","files"]]}'
    else
        RPC_PAYLOAD='{"jsonrpc":"2.0","method":"aria2.tellStopped","id":"TingV","params":[-1,1000,["gid","status","files"]]}'
    fi
    curl "${RPC_ADDRESS}" -fsSd "${RPC_PAYLOAD}" || curl "https://${RPC_ADDRESS}" -kfsSd "${RPC_PAYLOAD}"
}

GET_STOPPED_LIST() {
    READ_ARIA2_CONF
    RPC_RESULT="$(RPC_STOPPED_LIST)"
}

GET_UPLOAD_TASK_INFO() {
    [[ -z ${RPC_RESULT} ]] && {
        echo -e "$(DATE_TIME) ${ERROR} Aria2 RPC interface error!"
        exit 1
    }
    STOPPED_TASK_INDEX=$(echo "${RPC_RESULT}" | jq -r ".result|length"-1)
    if [ ${STOPPED_TASK_INDEX} = -1 ];then
        echo -e "$(DATE_TIME) ${WARRING} No completed tasks."
        exit 0
    fi
    STOPPED_TASK_INFO=$(echo "${RPC_RESULT}" | jq -r ".result|.[${STOPPED_TASK_INDEX}]")
    STOPPED_TASK_STATUS=$(echo "${STOPPED_TASK_INFO}" | jq -r ".status")
    if [[ "${STOPPED_TASK_STATUS}" != "complete" ]]; then
        echo -e "$(DATE_TIME) ${WARRING} This task is not completed and uploading is not allowed."
        exit 0
    fi

    TASK_GID=$(echo "${STOPPED_TASK_INFO}" | jq -r ".gid")
    FILE_NUM=$(echo "${STOPPED_TASK_INFO}" | jq -r ".files|length")
    FILE_PATH=$(echo "${STOPPED_TASK_INFO}" | jq -r ".files|.[0]|.path")
}

CHECK_RCLONE() {
    [[ $# -eq 0 ]] && {
        echo && echo -e "Checking RCLONE connection ..."
        rclone mkdir "${DRIVE_NAME}:${DRIVE_DIR}/P3TERX.COM"
        if [[ $? -eq 0 ]]; then
            rclone rmdir "${DRIVE_NAME}:${DRIVE_DIR}/P3TERX.COM"
            echo
            echo -e "${LIGHT_GREEN_FONT_PREFIX}success${FONT_COLOR_SUFFIX}"
        else
            echo
            echo -e "${RED_FONT_PREFIX}failure${FONT_COLOR_SUFFIX}"
            exit 1
        fi
    }
}

DEFINITION_PATH() {
    LOCAL_PATH="${TASK_PATH}"
    if [[ -f "${TASK_PATH}" ]]; then
        REMOTE_PATH="${DRIVE_NAME}:${DRIVE_DIR}${DEST_PATH_SUFFIX%/*}"
    else
        REMOTE_PATH="${DRIVE_NAME}:${DRIVE_DIR}${DEST_PATH_SUFFIX}"
    fi
}

LOAD_RCLONE_ENV() {
    RCLONE_ENV_FILE="${ARIA2_CONF_DIR}/rclone.env"
    [[ -f ${RCLONE_ENV_FILE} ]] && export $(grep -Ev "^#|^$" ${RCLONE_ENV_FILE} | xargs -0)
}

TASK_INFO() {
    echo -e "
-------------------------- [${YELLOW_FONT_PREFIX}Task Infomation${FONT_COLOR_SUFFIX}] --------------------------
${LIGHT_PURPLE_FONT_PREFIX}Task GID:${FONT_COLOR_SUFFIX} ${TASK_GID}
${LIGHT_PURPLE_FONT_PREFIX}Number of Files:${FONT_COLOR_SUFFIX} ${FILE_NUM}
${LIGHT_PURPLE_FONT_PREFIX}First File Path:${FONT_COLOR_SUFFIX} ${FILE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}Task File Name:${FONT_COLOR_SUFFIX} ${TASK_FILE_NAME}
${LIGHT_PURPLE_FONT_PREFIX}Task Path:${FONT_COLOR_SUFFIX} ${TASK_PATH}
${LIGHT_PURPLE_FONT_PREFIX}Aria2 Download Directory:${FONT_COLOR_SUFFIX} ${ARIA2_DOWNLOAD_DIR}
${LIGHT_PURPLE_FONT_PREFIX}Custom Download Directory:${FONT_COLOR_SUFFIX} ${DOWNLOAD_DIR}
${LIGHT_PURPLE_FONT_PREFIX}Local Path:${FONT_COLOR_SUFFIX} ${LOCAL_PATH}
${LIGHT_PURPLE_FONT_PREFIX}Remote Path:${FONT_COLOR_SUFFIX} ${REMOTE_PATH}
${LIGHT_PURPLE_FONT_PREFIX}.aria2 File Path:${FONT_COLOR_SUFFIX} ${DOT_ARIA2_FILE}
-------------------------- [${YELLOW_FONT_PREFIX}Task Infomation${FONT_COLOR_SUFFIX}] --------------------------
"
}

OUTPUT_UPLOAD_LOG() {
    LOG="${UPLOAD_LOG}"
    LOG_PATH="${UPLOAD_LOG_PATH}"
    OUTPUT_LOG
}

UPLOAD_FILE() {
    echo -e "$(DATE_TIME) ${INFO} Start upload files..."
    TASK_INFO
    RETRY=0
    RETRY_NUM=3
    while [ ${RETRY} -le ${RETRY_NUM} ]; do
        [ ${RETRY} != 0 ] && (
            echo
            echo -e "$(DATE_TIME) ${ERROR} Upload failed! Retry ${RETRY}/${RETRY_NUM} ..."
            echo
        )
        GENERATE_MEDIAINFO_FILE
        rclone move -v "${LOCAL_PATH}" "${REMOTE_PATH}"
        RCLONE_EXIT_CODE=$?
        if [ ${RCLONE_EXIT_CODE} -eq 0 ]; then
            UPLOAD_LOG="$(DATE_TIME) ${INFO} Upload done: ${LOCAL_PATH} -> ${REMOTE_PATH}"
            OUTPUT_UPLOAD_LOG
            DELETE_EMPTY_DIR
            REMOVE_TASK
            GET_REMOVE_TASK_INFO
            TELEGRAM_NOTIFICATION
            break
        else
            RETRY=$((${RETRY} + 1))
            [ ${RETRY} -gt ${RETRY_NUM} ] && (
                echo
                UPLOAD_LOG="$(DATE_TIME) ${ERROR} Upload failed: ${LOCAL_PATH}"
                OUTPUT_UPLOAD_LOG
            )
            sleep 3
        fi
    done
}


TELEGRAM_NOTIFICATION() {
    if [[ "${TG_BOT_TOKEN}" && "${TG_USER_ID}" ]]; then
        NOTIFICATION_RESULT=`curl -X POST -s \
            -H 'Content-Type: application/json' \
            -d "{
                    \"chat_id\": \"${TG_USER_ID}\",
                    \"parse_mode\": \"HTML\",
                    \"text\": \"<b>Task File Name</b>: <code>${TASK_FILE_NAME}</code>\n\n<b>Remote Path</b>: <code>${REMOTE_PATH}</code>\n\n<b>Completion Date</b>: $(DATE_TIME)\",
                    \"disable_web_page_preview\": true,
                    \"disable_notification\": true
                }" \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"`
            NOTIFICATION_STATE=$(echo "${NOTIFICATION_RESULT}" | jq -r ".ok")
            if [[ "${NOTIFICATION_STATE}" = "true" ]]; then
                echo -e "$(DATE_TIME) ${INFO} Telegram message sent successfully."
            elif [[ "${NOTIFICATION_STATE}" = "false" ]]; then
                NOTIFICATION_ERROR_MSG=$(echo "${NOTIFICATION_RESULT}" | jq -r ".description")
                NOTIFICATION_ERROR_CODE=$(echo "${NOTIFICATION_RESULT}" | jq -r ".error_code")
                echo -e "$(DATE_TIME) ${ERROR} Telegram message sending failed. ${NOTIFICATION_ERROR_CODE}# ${NOTIFICATION_ERROR_MSG}"
            else
               echo -e "$(DATE_TIME) ${ERROR} Telegram message sending failed. Please check your network."
            fi
    fi
}

GENERATE_MEDIAINFO_FILE() {
    if [[ "${DELETE_EMPTY_DIR}" = "true" ]]; then
        if [[ ${FILE_NUM} -eq 1 ]]; then
            echo -e "$(DATE_TIME) ${WARRING} Single file tasks do not generate mediainfo.txt."
            return 1
        fi
        VIDEO_FILE=$(ls "${LOCAL_PATH}" | grep -i 'wmv\|.*.avi\|.*.dat\|.*.asf\|.*.mpeg\|.*.mpg\|.*.rm\|.*.rmvb\|.*.ram\|.*.flv\|.*.mp4\|.*.3gp\|.*.mov\|.*.divx\|.*.dv\|.*.vob\|.*.mkv\|.*.qt\|.*.cpk\|.*.fli\|.*.flc\|.*.f4v\|.*.m4v\|.*.mod\|.*.m2t\|.*.swf\|.*.webm\|.*.mts\|.*.m2ts' | sed -n '1p') # 获取视频文件并取第一个
        if [[ -z ${VIDEO_FILE} ]]; then
            echo -e "$(DATE_TIME) ${WARRING} No video file found, can't generate mediainfo.txt!"
            return 1
        fi
        echo -e "$(DATE_TIME) ${INFO} Generate mediainfo.txt file ..."
        VIDEO_FILE_PATH="${LOCAL_PATH}/${VIDEO_FILE}"
        MEDIAINFO_INFO=$(mediainfo "${VIDEO_FILE_PATH}")
        MEDIAINFO_INFO=${MEDIAINFO_INFO/"${LOCAL_PATH}/"/""}
        echo "${MEDIAINFO_INFO}" > "${LOCAL_PATH}/mediainfo.txt"
    fi
}

CHECK_CORE_FILE "$@"
CHECK_SPECIAL_MODE
CHECK_RCLONE_PID
GET_STOPPED_LIST
GET_UPLOAD_TASK_INFO
CHECK_SCRIPT_CONF
CHECK_RCLONE "$@"
GET_TASK_INFO
GET_DOWNLOAD_DIR
CONVERSION_PATH
DEFINITION_PATH
CLEAN_UP
LOAD_RCLONE_ENV
UPLOAD_FILE

exit 0
