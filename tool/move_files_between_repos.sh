#! /bin/bash
#
# author: Henry Yin(h4yin)
#
# Example:
# ./move_files_between_repos.sh -o origin_repo_name -t target_repo_name -f  \
# path/to/file [-p module_name_in_origin_repo] [-s module_name_in_target_repo] [-d]

# parse args
NEED_DELETED=false
HAS_ORIGIN_SUBMODULE=false
HAS_TARGET_SUBMODULE=false

while getopts "o:t:f:p:s:d" OPT; do
    case ${OPT} in
        o)
            ORIGIN_REPO=${OPTARG}
            ;;
        t)
            TARGET_REPO=${OPTARG}
            ;;
        f)
            FILES=${OPTARG}
            ;;
        p)
            ORIGIN_SUBMODULE=${OPTARG}
            HAS_ORIGIN_SUBMODULE=true
            ;;
        s)
            TARGET_SUBMODULE=${OPTARG}
            HAS_TARGET_SUBMODULE=true
            ;;
        d)
            NEED_DELETED=true
            ;;
        \?)
            echo
            echo "Usage:"
            echo "    -o    Origin repo name"
            echo "    -t    Target repo name"
            echo "    -f    File which each line represents a file to be moving"
            echo "    [-p]  Module name in origin repo"
            echo "    [-s]  Module name in target repo"
            echo "    [-d]  Delete files after moved"
            echo
            echo "Example: ./move_files_between_repos.sh -o origin_repo_name -t target_repo_name -f " \
                 "path/to/file [-p module_name_in_origin_repo] [-s module_name_in_target_repo] [-d]"
            echo
            echo "Notice:"
            echo "1. Origin repo, target repo and script should be in the same directory."
            echo "2. Path in files must be relative path in origin repo or module(if -p option used)."
            echo "3. Not support directory, you can list all files in the directory intending to move instead."
            echo
            exit 1
    esac
done

shift $((OPTIND -1))

# define variables
BASE_DIR=$(pwd)
ORIGIN_REPO_PATH=${BASE_DIR}/${ORIGIN_REPO}
TARGET_REPO_PATH=${BASE_DIR}/${TARGET_REPO}
TARGET_FILES=${BASE_DIR}/_tmp_need_to_move_files_
PATCH_FILE=${BASE_DIR}/_tmp_patch_

echo "ORIGIN_REPO_PATH: ${ORIGIN_REPO_PATH}"
echo "TARGET_REPO_PATH: ${TARGET_REPO_PATH}"
echo "TARGET_FILES: ${TARGET_FILES}"
echo "PATCH_FILE: ${PATCH_FILE}"

# Find all commits in origin repo, then copy to target repo.
function move() {

    # clear tmp file
    > ${TARGET_FILES}
    > ${PATCH_FILE}
    
    cd "${ORIGIN_REPO_PATH}"

    # Use first-parent in merging and disable --follow to exclude renaming commit in conservative mode.
    if [ "${GIT_LOG_MODE}" = "ALL" ]; then
        local GIT_LOG_OPTION_FIRST_PARENT=""
        local GIT_LOG_OPTION_FOLLOW="--follow"
    else
        local GIT_LOG_OPTION_FIRST_PARENT="--first-parent"
        local GIT_LOG_OPTION_FOLLOW=""
    fi

    for ORIGIN_FILE in $(cat ${FILES}); do
        local FILE_PATH=${ORIGIN_FILE}
        if [ "${HAS_ORIGIN_SUBMODULE}" = true ] ; then
            local FILE_PATH=${ORIGIN_SUBMODULE}/${ORIGIN_FILE}
        fi
        if [ -e "${FILE_PATH}" ]; then
            echo "${ORIGIN_FILE}" >> ${TARGET_FILES}
            echo $(git log -m ${GIT_LOG_OPTION_FIRST_PARENT} ${GIT_LOG_OPTION_FOLLOW}  \
                --name-only --pretty="format:" "${FILE_PATH}") \
                | tr "[:space:]" "\n"
        fi
    done    \
        | sort -u \
        | xargs git log -m ${GIT_LOG_OPTION_FIRST_PARENT} --pretty=email --patch-with-stat \
            --reverse --full-index --binary -- > "${PATCH_FILE}"

    if [ "${HAS_ORIGIN_SUBMODULE}" = true ] ; then
        sed "s/${ORIGIN_SUBMODULE}\///g" ${PATCH_FILE} > ${PATCH_FILE}.tmp && mv ${PATCH_FILE}.tmp ${PATCH_FILE}
    fi

    cd "${TARGET_REPO_PATH}"
    echo 
    echo "Applying patch..."

    local GIT_LOG_DIRECTORY_OPTION=""
    if [ "${HAS_TARGET_SUBMODULE}" = true ] ; then
        local GIT_LOG_DIRECTORY_OPTION="--directory=${TARGET_SUBMODULE}"
    fi
    git am --keep-non-patch ${GIT_LOG_DIRECTORY_OPTION} -C1 --ignore-whitespace \
        --committer-date-is-author-date < ${PATCH_FILE}

    # Abort git am when failed.
    if [ $? -ne 0 ]; then
        echo
        echo "Git am failed and aborted."
        git am --abort
        return 1
    fi

    rm ${PATCH_FILE}
    echo
    echo "Git am succeed!"
    return 0
}


function exit_when_failed_after_retry() {
    echo 
    echo "Still failed after retried with GIT_LOG_MODE=CONSERVATIVE."
    exit 1
}


function retry_move_with_conservative_mode() {
    echo
    echo "Will retry with GIT_LOG_MODE=CONSERVATIVE."
    GIT_LOG_MODE="CONSERVATIVE"
    move
    if [ $? -ne 0 ]; then
        exit_when_failed_after_retry
    fi
}


# Conditions of success should meet the following three conditions simultaneously:
# 1. Files list intends to move must be equals to deleted file list in origin repo.
# 2. Files list intends to move must be equals to added file list in target repo.
# 3. Content in files of origin repo must be equals to target repo.
function check_result() {
    echo
    echo "Checking result..."
    cd ${ORIGIN_REPO_PATH}

    cat ${TARGET_FILES} | sort -u > _m_ && mv _m_ ${TARGET_FILES}

    # Check if content of added files in target repo is equals to origin repo.
    echo
    echo "Checking if content of added files in target repo is equals to origin repo..."
    for FILE_PATH in $(cat ${TARGET_FILES}); do
        if [ "${HAS_ORIGIN_SUBMODULE}" = true ] ; then
            local ORIGIN_FILE_PATH=${ORIGIN_REPO_PATH}/${ORIGIN_SUBMODULE}/${FILE_PATH}
        else
            local ORIGIN_FILE_PATH=${ORIGIN_REPO_PATH}/${FILE_PATH}
        fi 
        if [ "${HAS_TARGET_SUBMODULE}" = true ] ; then
            local TARGET_FILE_PATH=${TARGET_REPO_PATH}/${TARGET_SUBMODULE}/${FILE_PATH}
        else
            local TARGET_FILE_PATH=${TARGET_REPO_PATH}/${FILE_PATH}
        fi 
        diff -r ${ORIGIN_FILE_PATH} ${TARGET_FILE_PATH}
        if [ $? -ne 0 ]; then
            FAILED=true
            echo
            echo "ERROR: content in ${ORIGIN_FILE_PATH} is not same with ${TARGET_FILE_PATH}"
            break
        fi
    done

    if [ "${FAILED}" = true ] ; then
        echo
        echo "Failed! Sorry!"
        # Roll back.
        echo "${TARGET_REPO} roll back..."
        cd ${TARGET_REPO_PATH}
        git reset --hard ${TARGET_REPO_ORIGIN_GIT_HEAD}
        return 1
    else
        echo "Succeed! Content of added files in target repo is equals to origin repo."
    fi

    # Delete origin repo files.
    if [ "${NEED_DELETED}" = true ] ; then
        echo 
        echo 'Deleting origin files...'
        cat ${TARGET_FILES} | while read FILE_PATH; do
            if [ "${HAS_ORIGIN_SUBMODULE}" = true ] ; then
                git rm -r ${ORIGIN_REPO_PATH}/${ORIGIN_SUBMODULE}/${FILE_PATH}
            else
                git rm -r ${ORIGIN_REPO_PATH}/${FILE_PATH}
            fi
        done
    fi

    # Check if file list in moving is equals to deleted in origin repo.
    echo
    echo "Check if file list in moving is equals to deleted in origin repo."
    ORIGIN_RM_FILES=${BASE_DIR}/_rm_in_${ORIGIN_REPO}_

    git diff --cached --name-only | sort -u > ${ORIGIN_RM_FILES}
    if [ "${HAS_ORIGIN_SUBMODULE}" = true ] ; then
        sed "s/${ORIGIN_SUBMODULE}\///g" ${ORIGIN_RM_FILES} > ${ORIGIN_RM_FILES}.tmp \
            && mv ${ORIGIN_RM_FILES}.tmp ${ORIGIN_RM_FILES}
    fi

    diff -r ${ORIGIN_RM_FILES} ${TARGET_FILES}
    if [ $? -ne 0 ]; then
        # Roll back.
        echo "${ORIGIN_REPO} and ${TARGET_REPO} roll back..."
        cd ${ORIGIN_REPO_PATH}
        git reset --hard HEAD
        cd ${TARGET_REPO_PATH}
        git reset --hard ${TARGET_REPO_ORIGIN_GIT_HEAD}

        echo
        echo "ERROR: deleted file list: ${ORIGIN_RM_FILES} is not same with moving file list: ${TARGET_FILES}"
        return 1
    else
        echo "Succeed! File list in moving is equals to deleted in origin repo."
    fi
    rm ${ORIGIN_RM_FILES}

    # Check if file list in moving is equals to added in target repo.
    echo
    echo "Check if file list in moving is equals to added in target repo."
    cd "${TARGET_REPO_PATH}"
    TARGET_ADDED_FILES=${BASE_DIR}/_tmp_added_in_${TARGET_REPO}_
    git diff ${TARGET_REPO_ORIGIN_GIT_HEAD} HEAD --name-only | sort -u > ${TARGET_ADDED_FILES}
    if [ "${HAS_TARGET_SUBMODULE}" = true ] ; then
        sed "s/${TARGET_SUBMODULE}\///g" ${TARGET_ADDED_FILES} > ${TARGET_ADDED_FILES}.tmp \
            && mv ${TARGET_ADDED_FILES}.tmp ${TARGET_ADDED_FILES}
    fi

    diff -r ${TARGET_ADDED_FILES} ${TARGET_FILES}
    if [ $? -ne 0 ]; then
        # Roll back.
        echo "${ORIGIN_REPO} and ${TARGET_REPO} roll back..."
        cd ${ORIGIN_REPO_PATH}
        git reset --hard HEAD
        cd ${TARGET_REPO_PATH}
        git reset --hard ${TARGET_REPO_ORIGIN_GIT_HEAD}

        echo
        echo "ERROR: added file list: ${TARGET_ADDED_FILES} is not same with moving file list: ${TARGET_FILES}"
        return 1
    else
        echo "Succeed! File list in moving is equals to added in target repo."
    fi
}

cd "${TARGET_REPO_PATH}"
# Save hash of target repo origin HEAD for checking result.
TARGET_REPO_ORIGIN_GIT_HEAD=$(git rev-parse HEAD |tail -1)
echo
echo "Target repo origin HEAD: ${TARGET_REPO_ORIGIN_GIT_HEAD}"

# Git may not or can't understand commit logs correctly when show all logs where branch merging or renaming exists.
# That is -m or --follow option in git log command can result in conflict or unintended files moved.
# So when the above errors occur, retry moving in conservative mode
# which specify first branch when merging using --first-parent, and disable --follow.

GIT_LOG_MODE="ALL"
move

if [ $? -ne 0 ]; then
    retry_move_with_conservative_mode
fi

check_result
if [ $? -ne 0 ]; then
    if [ "${GIT_LOG_MODE}" = "ALL" ]; then
        retry_move_with_conservative_mode
        check_result
        if [ $? -ne 0 ]; then
            exit_when_failed_after_retry
        else
            echo
            echo "Succeed!"
        fi
    else
        exit_when_failed_after_retry
    fi
else
    echo
    echo "Succeed!"
fi

# rm tmp files
 rm ${TARGET_FILES}

