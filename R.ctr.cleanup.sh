#!/bin/bash
#CTR (01) [UTC-2025-04-09-00=06-51] ./R.ctr.cleanup.sh [Summary: ] [Next steps: ] [Notes: ]

# --- Default Configuration ---
TARGET="."
RECURSIVE=false
EXCLUDE_PATTERN=""
TARGET_IS_FILE=false
TARGET_IS_DIR=false

# --- Helper Functions ---

# Function to determine comment prefix (copied from R.ctr.sh)
get_comment_prefix() {
    local filename="$1"
    local ext="${filename##*.}"
    # Handle filenames like .bashrc
    [[ "$filename" == .* ]] && [[ ! "$filename" == *. ]] && ext="${filename#.}"

    case "$ext" in
        sh|bash|py|pl|rb|conf|ini|txt|yaml|yml|md|R|ls|ctr) echo "#" ;;
        c|cpp|h|hpp|java|js|ts|css|go|php|swift|kt) echo "//" ;;
        html|xml|svg) echo "<!--" ;;
        sql|ada) echo "--" ;;
        f|f90|f95|f03|f08) echo "!" ;;
        *) echo "" ;; # No known comment leader
    esac
}

# Function to check if a file/directory basename matches the exclusion pattern
should_exclude() {
    local name_to_check="$1" # Basename of the file/dir
    if [[ -n "$EXCLUDE_PATTERN" ]]; then
        if grep -qE -- "$EXCLUDE_PATTERN" <<< "$name_to_check"; then
            # echo "Debug: Excluding '$name_to_check' due to pattern '$EXCLUDE_PATTERN'" >&2
            return 0 # 0 means yes, exclude (shell true)
        fi
    fi
    return 1 # 1 means no, do not exclude (shell false)
}

# Function to remove CTR lines from within a file
process_file_cleanup() {
    local file_path="$1"
    local base_name=$(basename "$file_path")

    # Skip if excluded
    if should_exclude "$base_name"; then
        echo "Skipping excluded file: $file_path" >&2
        return
    fi

    # Skip .CTR.* files themselves (they are handled by delete function)
    [[ "$base_name" == ".CTR."* ]] && return

    local prefix=$(get_comment_prefix "$base_name")

    # Only process files that support comments
    if [[ -n "$prefix" ]]; then
        # Escape prefix for sed, especially '/' and other regex chars
        local escaped_prefix=$(sed -e 's/[][\\/.^$*]/\\&/g' <<< "$prefix")
        local pattern="^${escaped_prefix}[[:space:]]*CTR"

        # Check if the pattern exists before trying to modify
        if grep -qE -- "$pattern" "$file_path"; then
            echo "Cleaning CTR lines from: $file_path"
            # Use sed to delete matching lines in-place
            sed -i -E "/${pattern}/d" "$file_path"
            if [[ $? -ne 0 ]]; then
                 echo "Error: sed command failed for $file_path" >&2
            # Optional: Remove file if it becomes empty after cleanup?
            # if [[ ! -s "$file_path" ]]; then
            #     echo "Removing empty file after cleanup: $file_path"
            #     rm "$file_path"
            # fi
            fi
        # else
            # echo "Debug: No CTR lines found in $file_path" >&2
        fi
    fi

    # Also check if a corresponding .CTR file exists and delete it
    local meta_file="$(dirname "$file_path")/.CTR.$base_name"
    if [[ -f "$meta_file" ]]; then
         # Check exclusion for the original file's name, not the meta file's name directly
         if ! should_exclude "$base_name"; then
             delete_metadata_file "$meta_file"
         else
             echo "Skipping deletion of excluded metadata file: $meta_file (linked to $base_name)" >&2
         fi
    fi

}

# Function to delete a .CTR.* metadata file
delete_metadata_file() {
    local meta_file_path="$1"
    local original_base_name="${meta_file_path##*/.CTR.}" # Extract original name

    # Check exclusion based on the *original* file's name
    if should_exclude "$original_base_name"; then
        echo "Skipping deletion of excluded metadata file: $meta_file_path (linked to $original_base_name)" >&2
        return
    fi

    if [[ -f "$meta_file_path" ]]; then
        echo "Deleting metadata file: $meta_file_path"
        rm "$meta_file_path"
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to delete $meta_file_path" >&2
        fi
    fi
}

# Function to process a directory
process_directory_cleanup() {
    local dir_path="$1"
    local start_dir="$PWD" # Remember where we were

    # Check exclusion for the directory itself before entering
    local dir_base_name=$(basename "$dir_path")
     # Handle "." case for starting directory
    [[ "$dir_path" == "." ]] && dir_base_name=$(basename "$PWD")

    if [[ "$dir_path" != "." ]] && should_exclude "$dir_base_name"; then
         echo "Skipping excluded directory: $dir_path" >&2
         return
    fi

    # Change into the directory
    if ! cd "$dir_path"; then
        echo "Error: Cannot cd into directory '$dir_path'" >&2
        return
    fi

    echo "Processing directory: $PWD"

    # Iterate through entries in the current directory
    for entry in *; do
        local entry_base_name=$(basename "$entry")

        # Check exclusion for the entry
        if should_exclude "$entry_base_name"; then
             # echo "Debug: Skipping excluded entry '$entry' in $PWD" >&2
             continue
        fi

        if [[ "$entry_base_name" == ".CTR."* ]]; then
            # This is a metadata file, handle its deletion
            delete_metadata_file "$entry" # Pass relative path within current dir
        elif [[ -f "$entry" ]]; then
            # This is a regular file, clean CTR lines from within it
            process_file_cleanup "$entry" # Pass relative path
        elif [[ -d "$entry" && "$RECURSIVE" == true ]]; then
            # This is a directory, recurse if enabled
            # Pass relative path for recursion
            process_directory_cleanup "$entry"
        fi
    done

    # Go back to the original directory
    if ! cd "$start_dir"; then
        echo "Critical Error: Cannot cd back to '$start_dir' from '$PWD'. Exiting." >&2
        exit 1
    fi
}


# --- Argument Parsing ---
# Usage: R.ctr.cleanup.sh [target] [-r] [-e <pattern>]

# Use getopt for robust parsing
# -o allows short options, --long allows long options
# r is simple flag, e needs an argument (e:)
TEMP=$(getopt -o 're:' --long 'recursive,exclude:' -n 'R.ctr.cleanup.sh' -- "$@")
if [ $? != 0 ] ; then echo "Usage: R.ctr.cleanup.sh [target] [-r] [-e <pattern>]" >&2 ; exit 1 ; fi
eval set -- "$TEMP"
unset TEMP

# Extract options
while true; do
    case "$1" in
        -r|--recursive) RECURSIVE=true; shift ;;
        -e|--exclude) EXCLUDE_PATTERN="$2"; shift 2 ;;
        --) shift ; break ;; # End of options
        *) echo "Internal error parsing options!" >&2 ; exit 1 ;;
    esac
done

# Positional argument (target)
# If an argument remains after option processing, it's the target
if [[ -n "$1" ]]; then
    TARGET="$1"
fi

# --- Target Validation and Execution ---
initial_pwd=$(pwd) # Store initial directory

if [[ -f "$TARGET" ]]; then
    TARGET_IS_FILE=true
    echo "Target is file: $TARGET"
    target_abs=$(realpath "$TARGET")
    # Process the specific file
    process_file_cleanup "$target_abs"
    # No cd needed as process_file_cleanup handles paths and metadata lookup
elif [[ -d "$TARGET" ]]; then
    TARGET_IS_DIR=true
    echo "Target is directory: $TARGET"
    # process_directory_cleanup handles cd internally
    process_directory_cleanup "$TARGET"
elif [[ "$TARGET" == "." && ! -e "$TARGET" ]]; then
    # Handle case where default "." is used but doesn't exist (unlikely but possible)
     echo "Error: Current directory '.' seems invalid." >&2
     exit 1
else
    # Handle case where target doesn't exist but wasn't the default "."
    if [[ "$TARGET" != "." ]]; then
         echo "Error: Target '$TARGET' not found or is not a regular file or directory." >&2
         exit 1
    else
         # Default target "." is a directory, proceed as directory
         TARGET_IS_DIR=true
         echo "Target is current directory: ."
         process_directory_cleanup "$TARGET" # TARGET is "."
    fi
fi

# Ensure we are back in the starting directory if cd occurred
if [[ "$(pwd)" != "$initial_pwd" ]]; then
    echo "Warning: Script did not end in the initial directory. Attempting to return." >&2
    cd "$initial_pwd" || echo "Error: Failed to return to initial directory '$initial_pwd'." >&2
fi

echo "Cleanup process finished."
exit 0
