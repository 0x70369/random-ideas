"  _   _                 _
" | \ | | ___  _____   _(_)_ __ ___
" |  \| |/ _ \/ _ \ \ / / | '_ ` _ \
" | |\  |  __/ (_) \ V /| | | | | | |
" |_| \_|\___|\___/ \_/ |_|_| |_| |_|
"
" by Stephan Raabe (2023)
" -----------------------------------------------------

" Not set here because they are already Neovim's defaults: nocompatible, hlsearch, incsearch,
" autoindent, ttyfast, "filetype plugin indent on" and "syntax on". See :help nvim-defaults
set showmatch               " show matching
set ignorecase              " case insensitive
set tabstop=4               " number of columns occupied by a tab
set softtabstop=4           " see multiple spaces as tabstops so <BS> does the right thing
set expandtab               " converts tabs to white space
set shiftwidth=4            " width for autoindents
set number                  " add line numbers
set wildmode=longest,list   " get bash-like tab completions
set mouse=a                 " mouse in all modes (the default leaves out the command line)
set clipboard=unnamedplus   " using system clipboard
" set cc=80                   " set an 80 column border for good coding style
" set cursorline              " highlight current cursorline
" set spell                 " enable spell check (may need to download language package)
" set noswapfile            " disable creating swap file
" set backupdir=~/.cache/vim " Directory to store backup files.

hi NonText ctermbg=none guibg=NONE
hi Normal guibg=NONE ctermbg=NONE
hi NormalNC guibg=NONE ctermbg=NONE
hi SignColumn ctermbg=NONE ctermfg=NONE guibg=NONE

hi Pmenu ctermbg=NONE ctermfg=NONE guibg=NONE
hi FloatBorder ctermbg=NONE ctermfg=NONE guibg=NONE
hi NormalFloat ctermbg=NONE ctermfg=NONE guibg=NONE
hi TabLine ctermbg=None ctermfg=None guibg=None
