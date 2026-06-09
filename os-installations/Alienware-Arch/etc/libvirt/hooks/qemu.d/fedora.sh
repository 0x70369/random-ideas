#!/bin/env sh

OBJECT="$1"
OPERATION="$2"

case "$OBJECT" in
    "fedora")
        case "$OPERATION" in
            prepare)
                systemctl set-property --runtime -- system.slice AllowedCPUs=8-23
                systemctl set-property --runtime -- user.slice AllowedCPUs=8-23
                systemctl set-property --runtime -- init.scope AllowedCPUs=8-23
                ;;

            release)
                systemctl set-property --runtime -- system.slice AllowedCPUs=0-31
                systemctl set-property --runtime -- user.slice AllowedCPUs=0-31
                systemctl set-property --runtime -- init.scope AllowedCPUs=0-31
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
