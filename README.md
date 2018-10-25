# git-tool

Convenient scripts for development on git projects.

Tool list:
- [move files between repos](##move-files-between-repos)

## move files between repos
Move all files defines in a file between repositories with commit logs preserved.  
Also supports specifying module directory in repository.  
Also supports auto deleting origin repository files with -d option.  

Usage:
```text
    -o    Origin repo name
    -t    Target repo name
    -f    File which each line represents a file to be moving
    [-p]  Module name in origin repo
    [-s]  Module name in target repo
    [-d]  Delete files after moved
```

Example:
```bash
./move_files_between_repos.sh -o origin_repo_name -t target_repo_name -f \
path/to/file [-p module_name_in_origin_repo] [-s module_name_in_target_repo] [-d]
```
Notice:
1. Origin repo, target repo and script should be in the same directory.  
2. Path in files must be relative path in origin repo or module(if -p option used).  
3. Not support directory, you can list all files in the directory intending to move instead.
4. The script will try its best to preserve all commit log, but it may failed due to conflict 
in merging or misunderstanding commit logs by git. The script will retry once only using 
commits in the first-parent when merging and disable following renamed log.

