#!/bin/bash

# these are intended as relative paths *inside* the deb package
ICON_SRC="usr/lib/goose/resources/images/icon.png"
ICON_DEST="usr/share/pixmaps/goose.png"
DESKTOP_FILE="usr/share/applications/goose.desktop"

# Array of unwanted icon hashes 
HASHES=(
    "9f6e9d0f39ef3f78a5e72aae8c6ebf7c5e39b078398e4c1b154e80c492330981"
    # if/when an icon slips through, add its hash here
    # eg, sha256sum <path/to/img.png> | cut -d' ' -f1
)

# Exit on any error
set -e

echo "Removing 'subatomic' icon(s) from deb package(s) in favor of Goose icon..."

# Find all deb packages and put them into an array
deb_packages=()
while IFS= read -r -d '' deb_file; do
    if [[ "$deb_file" == *.deb ]]; then
        deb_packages+=("$deb_file")
    fi
done < <(find "out/" -type f -name "*.deb" -print0)

# Process deb packages
if [ ${#deb_packages[@]} -gt 0 ]; then
    echo "  Found ${#deb_packages[@]} *.deb"
    
    for deb_file in "${deb_packages[@]}"; do
        echo "Processing deb package: $deb_file"

        needs_repackaging=0
        
        # Create temporary directory
        temp_dir=$(mktemp -d)
        
        #Extract the package
        dpkg-deb -R "$deb_file" "$temp_dir"

        # Compare packaged icon against unwanted hashes
        if [ -f "${temp_dir}/${ICON_DEST}" ]; then
            icon_hash=$(sha256sum "${temp_dir}/${ICON_DEST}" | cut -d' ' -f1)
            for hash in "${HASHES[@]}"; do
                if [ ${icon_hash} == ${hash} ]; then
                    echo "  ¯\_(ツ)_/¯ packaged icon matches unwanted hash"
                    needs_repackaging+=1
                fi
            done
        fi

        # Replace the Electron icon file with our own
        if [ -f "${temp_dir}/${ICON_SRC}" ] && 
        [ $needs_repackaging -gt 0 ]; then
            printf "  Overwriting electron's icon with ours..."
            cp ${temp_dir}/${ICON_SRC} $temp_dir/${ICON_DEST}
            echo "done."
        else 
            echo "  Packaged icon is not banned."
        fi

        # Check for desktop file in package
        if [ -f "${temp_dir}/${DESKTOP_FILE}" ]; then
            # Compare path in desktop with intended path
            if ! grep -q "^Icon=/${ICON_DEST}$" "${temp_dir}/${DESKTOP_FILE}"; then
                needs_repackaging+=1
                # Update desktop file with real icon path
                printf "  Adding icon path to desktop file..."
                sed -i "s|^Icon=.*|Icon=/${ICON_DEST}|" "${temp_dir}/${DESKTOP_FILE}"
                echo "done."
            else 
                echo "  Icon path looks good."
            fi
        fi

        # Rebuild package if neccesary
        if [ ${needs_repackaging} -gt 0 ]; then
            printf "  🙄 repackaging deb... "
            dpkg-deb -b "${temp_dir}" "${deb_file}"
        else 
            printf "  Repackaging unnecessary..."
        fi
        
        # Clean up
        printf "  Cleaning up..."
        rm -rf "${temp_dir}"
        echo "done."
    done
fi

echo "Package post-processing complete."
