#!/bin/bash

# Get current PDF page from state file
get_page() {
    local state_file="/tmp/lf_pdf_page_$(echo "$1" | md5sum | cut -d' ' -f1)"
    if [ -f "$state_file" ]; then
        cat "$state_file"
    else
        echo "1"
    fi
}

# Preload adjacent pages in background
preload_pages() {
    local pdf="$1"
    local page="$2"
    local hash=$(echo "$pdf" | md5sum | cut -d' ' -f1)
    
    # Preload next page
    local next_page=$((page + 1))
    local next_cache="/tmp/lf_pdf_preview_${hash}_p${next_page}.png"
    if [ ! -f "$next_cache" ]; then
        (pdftoppm -f "$next_page" -l "$next_page" -scale-to 1000 -png "$pdf" > "$next_cache" 2>/dev/null &)
    fi
    
    # Preload previous page
    if [ "$page" -gt 1 ]; then
        local prev_page=$((page - 1))
        local prev_cache="/tmp/lf_pdf_preview_${hash}_p${prev_page}.png"
        if [ ! -f "$prev_cache" ]; then
            (pdftoppm -f "$prev_page" -l "$prev_page" -scale-to 1000 -png "$pdf" > "$prev_cache" 2>/dev/null &)
        fi
    fi
}

case "$(file --mime-type -Lb "$1")" in
    application/pdf)
        PAGE=$(get_page "$1")
        CACHE="/tmp/lf_pdf_preview_$(echo "$1" | md5sum | cut -d' ' -f1)_p${PAGE}.png"
        
        # Generate current page only if not cached
        if [ ! -f "$CACHE" ]; then
            pdftoppm -f "$PAGE" -l "$PAGE" -scale-to 1000 -png "$1" > "$CACHE" 2>/dev/null
        fi
        
        # Preload adjacent pages in background
        preload_pages "$1" "$PAGE"
        
        kitty +kitten icat --silent --stdin no --transfer-mode file --place "${2}x${3}@${4}x${5}" "$CACHE" < /dev/null > /dev/tty 2>/dev/null
        ;;
    image/*)
        kitty +kitten icat --silent --stdin no --transfer-mode file --place "${2}x${3}@${4}x${5}" "$1" < /dev/null > /dev/tty 2>/dev/null
        ;;
    *)
        cat "$1"
        ;;
esac
