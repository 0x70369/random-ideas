# zoxide replaces cd: "cd foo" jumps to the most used directory matching foo,
# "cdi foo" picks one with fzf. Loaded last, as zoxide's docs ask.
## https://github.com/ajeetdsouza/zoxide#configuration
# Never add these to the database (globs separated by ":")
export _ZO_EXCLUDE_DIRS="${HOME}:/temp/*:/tmp/*"
# shellcheck disable=SC2312 # upstream init line
eval "$(zoxide init --cmd cd bash)"

# List the directory whenever it changes (cd, cdi, pushd, popd...)
list_on_dir_change() {
    [[ ${PWD} == "${last_dir:-${PWD}}" ]] || ls
    last_dir=${PWD}
}
PROMPT_COMMAND+=(list_on_dir_change)
