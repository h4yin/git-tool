#! /bin/bash
# Usage:
# ./move_files_between_repos.sh -o path/to/origin/repo -t path/to/origin/repo -f path/to/file -d

# parse args
NEED_DELETED=false
while getopts "o:t:f:d" OPT; do
    case $OPT in
        o)
            ORIGIN_REPO=$OPTARG
            ;;
        t)
            TARGET_REPO=$OPTARG
            ;;
        f)
            FILES=$OPTARG
            ;;
        d)
            NEED_DELETED=true
            ;;
        \?)
            echo
            echo "Usage:"
            echo "    -o    Origin repo"
            echo "    -t    Target repo"
            echo "    -f    File which each line represents a file or a directory to be moving"
            echo "    [-d]  Delete files after moved"
            echo
            echo "Example: ./move_files_between_repos.sh -o path/to/origin/repo -t path/to/origin/repo -f path/to/file [-d]"
            echo
            exit 1
    esac
done

shift $((OPTIND -1))

ORIGIN_REPO_PATH=`pwd`/${ORIGIN_REPO}
echo "${ORIGIN_REPO_PATH}"

echo "Start..."

# move files
for PTH in `cat $FILES`; do
    echo `git log --name-only --pretty="format:" --follow  "${PTH}"` \
        | tr "[:space:]" "\n"
done \
    | sort -u \
    | xargs git log --pretty=email --patch-with-stat --reverse --full-index --binary -m --first-parent -- > "${TARGET_REPO}/_tmp_patch_"
cd "${TARGET_REPO}"
echo "Applying patch..."
git am --committer-date-is-author-date < _tmp_patch_
rm _tmp_patch_

# check result
echo "Check result..."
cd ${ORIGIN_REPO_PATH}
for PTH in `cat $FILES`; do
    diff -r ${ORIGIN_REPO}/${PTH} ${TARGET_REPO}/${PTH}
    if [ $? -ne 0 ]; then
        FAILED=true
        echo "ERROR: content in ${ORIGIN_REPO}/${PTH} is not same with ${TARGET_REPO}/${PTH}"
        break
    fi
done

if [ "$FAILED" = true ] ; then
    echo
    echo "Failed! Sorry!"
    exit 1
fi

# delete origin repo files
if [ "$NEED_DELETED" = true ] ; then
    echo 'Deleting origin files...'
    cat $FILES | while read PTH; do
        git rm -r ${ORIGIN_REPO}/${PTH}
    done
fi

echo "Succeed!"