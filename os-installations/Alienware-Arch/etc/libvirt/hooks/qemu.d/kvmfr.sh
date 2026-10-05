#!/bin/env sh

OBJECT="$1"
OPERATION="$2"

case "$OBJECT" in
    "Bosta11-bare-metal"|"Bosta10")
        case "$OPERATION" in
            prepare)
                modprobe -s kvmfr
                ;;

            release)
                modprobe -sr kvmfr
                ;;
        
            *)
                exit 0
                ;;

        esac
        ;;
        
    *)
        exit 0
        ;;
    
esac
