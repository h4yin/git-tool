# git-tool

Convenient scripts for development on git.

Tool list:
- [move files between repos](##move files between repos)


## move files between repos
Move all files or directory defines in a file between repositories with commit logs preserved.
Also support auto delete origin repository files with -d option.

Usage:
```bash
    -o    Origin repo
    -t    Target repo
    -f    File which each line represents a file or a directory to be moving
    [-d]  Delete files after moved
```
Example:

```bash
./move_files_between_repos.sh -o path/to/origin/repo -t path/to/origin/repo -f path/to/file -d
```

