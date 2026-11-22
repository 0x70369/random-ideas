# Extracts any archive(s)
extract() {
    local archive
    for archive in "$@"; do
        if [[ ! -f ${archive} ]]; then
            printf "'%s' is not a valid file!\n" "${archive}" >&2
            continue
        fi
        case ${archive} in
            *.tar.* | *.tbz2 | *.tgz | *.tar) tar -xf "${archive}" ;;
            *.7z) 7z x "${archive}" ;;
            *.bz2) bunzip2 -v "${archive}" ;;
            *.exe) cabextract "${archive}" ;;
            *.gz) gunzip -v "${archive}" ;;
            *.rar) unar "${archive}" ;;
            *.xz) unxz -vv "${archive}" ;;
            *.Z) uncompress -v "${archive}" ;;
            *.zip) unzip "${archive}" ;;
            *.zst) unzstd -v "${archive}" ;;
            *) printf "Don't know how to extract '%s'\n" "${archive}" >&2 ;;
        esac
    done
}

# Searches for text in all files below the current folder (case-insensitive,
# binaries skipped, with file names and line numbers)
findtext() {
    # shellcheck disable=SC2312 # interactive pipeline
    grep -iIHrn --color=always -- "$1" . | less -R
}

# Copy/move, then go to the destination if it's a directory
cpgo() {
    cp -- "$1" "$2" || return
    [[ ! -d $2 ]] || builtin cd -- "$2" || return
}
mvgo() {
    mv -- "$1" "$2" || return
    [[ ! -d $2 ]] || builtin cd -- "$2" || return
}

# Create and go to the directory
mkdirgo() {
    mkdir -p -- "$1" && builtin cd -- "$1" || return
}

# Goes up a number of directories (goup 4); one if none is given
goup() {
    local i path=
    for ((i = 0; i < ${1:-1}; i++)); do
        path+=../
    done
    builtin cd -- "${path:-.}" || return
}

# Internal and external IP addresses
whatsmyip() {
    local internal external
    internal=$(ip route get 1.1.1.1) || return
    internal=${internal#* src }
    external=$(curl -4s ifconfig.me) || return
    printf 'Internal IP: %s\nExternal IP: %s\n' "${internal%% *}" \
        "${external}"
}

