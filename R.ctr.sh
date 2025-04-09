#!/bin/bash
#CTR (01) [UTC-2025-04-09-00=06-51] ./R.ctr.sh [Summary: ] [Next steps: ] [Notes: ]

# --- Default Configuration ---
DEFAULT_TARGET="."
MODIFY_IN_PLACE=true # Default is to modify files/create .CTR files
DESTINATION_FILE=""
DISPLAY_OUTPUT=false
RECURSIVE=false
PROCESS_ALL=false # Corresponds to -a option logic
ERROR_MODE="screen" # screen, suppress, top, bottom, file
ERROR_FILE=""
declare -a ERROR_MESSAGES=()

# --- Helper Functions ---

# Function to log errors based on ERROR_MODE
log_error() {
    local message="$1"
    case "$ERROR_MODE" in
        screen) echo "Error: $message" >&2 ;;
        suppress) : ;; # Do nothing
        file) echo "Error: $message" >> "$ERROR_FILE" ;;
        top|bottom) ERROR_MESSAGES+=("Error: $message") ;;
    esac
}

# Function to determine comment prefix
get_comment_prefix() {
    local filename="$1"
    local ext="${filename##*.}"
    # Handle filenames like .bashrc
    [[ "$filename" == .* ]] && [[ ! "$filename" == *. ]] && ext="${filename#.}"

    case "$ext" in
        sh|bash|py|pl|rb|conf|ini|txt|yaml|yml|md|R|ls|ctr) echo "#" ;; # Added R, ls, ctr common in this project
        c|cpp|h|hpp|java|js|ts|css|go|php|swift|kt) echo "//" ;;
        html|xml|svg) echo "<!--" ;;
        sql|ada) echo "--" ;;
        f|f90|f95|f03|f08) echo "!" ;;
        *) echo "" ;; # No known comment leader
    esac
}

# Function to generate the CTR line
generate_ctr_line() {
    local file_path="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%d-%H=%M-%S")
    local comment_prefix
    comment_prefix=$(get_comment_prefix "$file_path")
    # Use relative path for the CTR line content itself
    local display_path="./$(basename "$file_path")"
    echo "${comment_prefix}CTR (01) [UTC-${timestamp}] ${display_path} [Summary: ] [Next steps: ] [Notes: ]"
}

# Function to handle the output (display, destination file, or in-place)
# --- THIS IS THE UPDATED FUNCTION (with Permission Handling) ---
output_handler() {
    local target_file="$1" # The original file being processed
    local ctr_line="$2"    # The generated CTR line
    local meta_file=".CTR.$(basename "$target_file")" # Potential metadata file

    # 1. Display if requested
    [[ "$DISPLAY_OUTPUT" == true ]] && echo "$ctr_line"

    # 2. If MODIFY_IN_PLACE is false (due to DESTINATION_FILE being set),
    #    write *only* to the destination file and return.
    if [[ "$MODIFY_IN_PLACE" == false ]]; then
        if [[ -n "$DESTINATION_FILE" ]]; then
             echo "$ctr_line" >> "$DESTINATION_FILE"
        fi
        # Do not proceed to modify files in place
        return
    fi

    # 3. Modify in-place or create .CTR file (only if MODIFY_IN_PLACE is true)
    local prefix
    prefix=$(get_comment_prefix "$target_file")

    if [[ -n "$prefix" ]]; then
        # --- START MODIFIED BLOCK (Shebang & Permission Handling) ---
        # File supports comments - Add CTR line, respecting shebang & permissions

        # *** Get original permissions and owner BEFORE creating temp file ***
        local original_perms=""
        # local original_owner="" # Uncomment if chown is needed/desired
        if [[ -e "$target_file" ]]; then # Check if file exists before stat
             original_perms=$(stat -c "%a" "$target_file" 2>/dev/null)
             # original_owner=$(stat -c "%u:%g" "$target_file" 2>/dev/null) # Uncomment if chown is needed/desired
             # Handle potential stat failure (e.g., broken link)
             if [[ -z "$original_perms" ]]; then
                  log_error "Could not get permissions for existing file: $target_file"
                  # Decide behaviour: skip or use default perms? Let's try default.
                  original_perms="644" # Fallback to default rw-r--r--
             fi
        else
            # File doesn't exist yet (shouldn't happen if called from process_file on existing file, but defensive)
            original_perms="644" # Default perms for new file
        fi


        local temp_file
        # Use mktemp in the same directory to ensure mv works across filesystems
        local temp_dir=$(dirname "$target_file")
        temp_file=$(mktemp "${temp_dir}/$(basename "$target_file").tmp.XXXXXX")

        if [[ -z "$temp_file" || ! -f "$temp_file" ]]; then
            log_error "Failed to create temp file for $target_file in $temp_dir"
            return # Skip modification
        fi

        # Check for shebang on the first line
        local first_line=""
        # Handle empty file case for read
        [[ -s "$target_file" ]] && read -r first_line < "$target_file"

        local write_cmd_status=0
        # Use command grouping {} with redirection for efficiency
        if [[ "$first_line" == '#!'* ]]; then
            # Shebang detected: Write shebang, then CTR, then rest of file
            {
                echo "$first_line"         # Write shebang
                echo "$ctr_line"           # Write CTR line
                # Use tail only if file has more than 1 line
                [[ $(wc -l < "$target_file") -gt 1 ]] && tail -n +2 "$target_file"
            } > "$temp_file"
            write_cmd_status=$?
        else
            # No shebang (or empty file): Write CTR line, then whole file
            {
                echo "$ctr_line"   # Write CTR line
                cat "$target_file" # Write whole original file (or nothing if empty)
            } > "$temp_file"
            write_cmd_status=$?
        fi

        if [[ "$write_cmd_status" -eq 0 ]]; then
            # Move the temp file to replace the original
            if mv "$temp_file" "$target_file"; then
                 # *** Restore original permissions ***
                 if [[ -n "$original_perms" ]]; then
                     if ! chmod "$original_perms" "$target_file"; then
                         log_error "Failed to restore permissions ($original_perms) on $target_file"
                     fi
                 fi
                 # *** Restore original owner (Optional - may require sudo) ***
                 # if [[ -n "$original_owner" ]]; then
                 #     if ! chown "$original_owner" "$target_file" &>/dev/null; then
                 #         # Log only if verbose? Don't usually log permission errors for chown
                 #         # log_error "Failed to restore owner ($original_owner) on $target_file (permissions?)"
                 #     fi
                 # fi
            else
                 log_error "Failed to move temp file to $target_file"
                 # If move fails, temp file might still exist, try removing
                 rm -f "$temp_file" &>/dev/null
            fi
        else
            log_error "Failed to write to temp file for $target_file"
            # Writing failed, clean up temp file
            rm -f "$temp_file" &>/dev/null
        fi
        # --- END MODIFIED BLOCK (Shebang & Permission Handling) ---
    else
        # File does not support comments - Create .CTR file
        if ! echo "$ctr_line" > "$meta_file"; then
             log_error "Failed to create metadata file $meta_file"
        fi
    fi
}


# Function to process a single file
process_file() {
    local file="$1"
    local full_path="$PWD/$file" # Keep track of full path if needed, but use relative for processing

    # Skip .CTR.* files themselves
    [[ "$file" == ".CTR."* ]] && return
    # Skip temp files potentially created by this script
    [[ "$file" == *.tmp.?????? ]] && return

    local prefix
    prefix=$(get_comment_prefix "$file")
    local meta_file=".CTR.${file##*/}"
    local ctr_exists=false
    local ctr_line=""

    if [[ -f "$file" ]]; then # Ensure it's actually a file before processing
        if [[ -n "$prefix" ]]; then
            # Check if CTR line already exists
            # Need to check based on potential location (after shebang or at top)
            local escaped_prefix=$(sed -e 's/[^^]/[&]/g; s/\^/\\^/g' <<< "$prefix") # Escape basic grep chars
            local pattern="^${escaped_prefix}[[:space:]]*CTR" # Pattern for CTR line itself

            # Read first two lines to check for shebang + CTR or just CTR
            local line1=""
            local line2=""
            local line_count=0
            # Read up to two lines safely
            while IFS= read -r line && [[ $line_count -lt 2 ]]; do
                [[ $line_count -eq 0 ]] && line1="$line"
                [[ $line_count -eq 1 ]] && line2="$line"
                ((line_count++))
            done < "$file"

            if [[ "$line1" == '#!'* ]]; then
                # Shebang exists, check line 2 for CTR
                if grep -q -E -- "$pattern" <<< "$line2"; then # Use -- to mark end of opts
                    ctr_exists=true
                fi
            else
                # No shebang (or potentially empty file), check line 1 for CTR
                if grep -q -E -- "$pattern" <<< "$line1"; then
                     ctr_exists=true
                fi
            fi
        fi
        # Check metafile regardless of prefix, as it's the alternative
        if [[ "$ctr_exists" == false && -f "$meta_file" ]]; then
             # Check if .CTR meta file exists and has content
             if grep -q -E "^CTR" "$meta_file"; then # .CTR files don't have comment prefixes
                 ctr_exists=true
             fi
        fi

        # If CTR doesn't exist, generate and output/store it
        if [[ "$ctr_exists" == false ]]; then
            ctr_line=$(generate_ctr_line "$file")
            output_handler "$file" "$ctr_line"
        fi
    else
         log_error "Attempted to process non-file '$file'"
    fi
}

# Function to process a directory
# Takes directory path relative to the initial target
process_dir() {
    local dir_rel_path="$1"
    local start_dir="$PWD"

    if ! cd "$dir_rel_path"; then
        log_error "Cannot cd into directory '$PWD/$dir_rel_path'"
        return
    fi

    local current_dir_name
    current_dir_name=$(basename "$PWD")

    # Handle the directory's own .CTR file if -a or -ar is active
    if [[ "$PROCESS_ALL" == true ]]; then
        local dir_meta_file="../.CTR.$current_dir_name" # Metafile stored in parent dir
        local dir_ctr_exists=false
        local dir_ctr_line=""

        if [[ -f "$dir_meta_file" ]]; then
             # Check if .CTR meta file exists and has content
             if grep -q -E "^CTR" "$dir_meta_file"; then
                dir_ctr_exists=true
             fi
        fi

        if [[ "$dir_ctr_exists" == false ]]; then
             # Generate CTR line for the directory itself
             local dir_timestamp
             dir_timestamp=$(date -u +"%Y-%m-%d-%H=%M-%S")
             # Path for directory CTR uses relative path from parent
             local dir_display_path="./$current_dir_name/"
             # .CTR files don't use comments internally
             dir_ctr_line="CTR (01) [UTC-${dir_timestamp}] ${dir_display_path} [Summary: Directory metadata] [Next steps: ] [Notes: ]"

             # Output/Store the directory CTR line
             # Use output_handler logic, but simplified for .CTR file creation or redirection
             if [[ "$DISPLAY_OUTPUT" == true ]]; then
                 echo "$dir_ctr_line"
             fi

             if [[ "$MODIFY_IN_PLACE" == false ]]; then
                  if [[ -n "$DESTINATION_FILE" ]]; then
                      echo "$dir_ctr_line" >> "$DESTINATION_FILE"
                  fi
             else
                 # Create .CTR.<dirname> in the parent directory
                 if ! echo "$dir_ctr_line" > "$dir_meta_file"; then
                     log_error "Failed to create directory metadata file $dir_meta_file"
                 fi
             fi
        fi
    fi


    # Process files and directories in the current directory
    for entry in *; do
        # Skip .CTR meta files and temp files
         [[ "$entry" == ".CTR."* ]] && continue
         [[ "$entry" == *.tmp.?????? ]] && continue

        if [[ -d "$entry" ]]; then
            if [[ "$RECURSIVE" == true ]]; then
                # Recurse if -ar is set
                process_dir "$entry" # Pass relative path for recursion
            fi
        elif [[ -f "$entry" ]]; then
             # Process files only if -a or -ar is set, or if processing a single file target initially
             # This check ensures files are processed when called on dir with -a/-ar
             if [[ "$PROCESS_ALL" == true || "$target_is_dir_no_flags" == true ]]; then
                 process_file "$entry"
             fi
        # Handle other types like symlinks etc. if needed - currently ignored
        fi
    done

    if ! cd "$start_dir"; then
        log_error "Critical: Cannot cd back to starting directory '$start_dir'. Exiting."
        # This is serious, exit to prevent unpredictable behavior
        exit 1
    fi
}


# --- Argument Parsing ---
# Usage: R.ctr.sh [target] [-a|-ar] [-d] [<destination>] [-e:<mode>[:<errorfile>]]

# Use getopt for robust parsing
TEMP=$(getopt -o 'ad' --long 'all,all-recursive,display,error:' -n 'R.ctr.sh' -- "$@")
if [ $? != 0 ] ; then echo "Usage: R.ctr.sh [target] [-a|-ar] [-d] [<destination>] [-e:<mode>[:<errorfile>]]" >&2 ; exit 1 ; fi
eval set -- "$TEMP"
unset TEMP

# Extract options first
while true; do
    case "$1" in
        -a|--all) PROCESS_ALL=true; shift ;;
        --all-recursive) PROCESS_ALL=true; RECURSIVE=true; shift ;; # Handle long option for -ar
        -d|--display) DISPLAY_OUTPUT=true; shift ;;
        --error) # Handles -e:mode[:file]
            error_opt="$2"
            if [[ "$error_opt" == "s" ]]; then
                ERROR_MODE="suppress"
            elif [[ "$error_opt" == "T" ]]; then
                ERROR_MODE="top"
            elif [[ "$error_opt" == T:* ]]; then
                ERROR_MODE="top"
                ERROR_FILE="${error_opt#T:}"
            elif [[ "$error_opt" == "b" ]]; then
                ERROR_MODE="bottom"
            elif [[ "$error_opt" == b:* ]]; then
                ERROR_MODE="bottom"
                ERROR_FILE="${error_opt#b:}"
            elif [[ "$error_opt" == f:* ]]; then # Use 'f' for separate file branch
                ERROR_MODE="file"
                ERROR_FILE="${error_opt#f:}"
            else
                 # Use stderr for startup errors before log_error is reliable
                 echo "Error: Invalid error option format: $error_opt. Using default 'screen'." >&2
                 ERROR_MODE="screen"
            fi
            shift 2 ;;
        --) shift ; break ;; # End of options
        *) echo "Internal error parsing options!" >&2 ; exit 1 ;;
    esac
done

# Positional arguments (target and optional destination)
TARGET="${1:-$DEFAULT_TARGET}" # First non-option arg is target, default '.'
DESTINATION_FILE="${2:-}"     # Second non-option arg is destination

# --- Initial Setup & Validation ---

# Store initial PWD
initial_pwd=$(pwd)
target_is_file=false
target_is_dir_no_flags=false # Track if target is dir and no -a/-ar flags

# Validate destination path *before* changing directory
if [[ -n "$DESTINATION_FILE" ]]; then
    # Resolve destination path relative to initial PWD
    # Check if it's absolute path
    [[ "$DESTINATION_FILE" != /* ]] && DESTINATION_FILE="$initial_pwd/$DESTINATION_FILE"

    # Check if destination is a directory
    if [[ -d "$DESTINATION_FILE" ]]; then
        echo "Error: Destination cannot be a directory: $DESTINATION_FILE" >&2
        exit 1
    fi

    # Check if we can write to the destination directory
    dest_dir=$(dirname "$DESTINATION_FILE")
    if [[ ! -d "$dest_dir" ]]; then
        # Try creating the directory? Or error out? Let's error out for now.
        echo "Error: Directory for destination file does not exist: $dest_dir" >&2
        exit 1
    fi
     if [[ ! -w "$dest_dir" ]]; then
        echo "Error: Cannot write to destination directory: $dest_dir" >&2
        exit 1
    fi

    # Set flag to prevent in-place modifications
    MODIFY_IN_PLACE=false

    # Create or truncate destination file now
    > "$DESTINATION_FILE"
    if [[ $? -ne 0 ]]; then
        echo "Error: Cannot create or truncate destination file: $DESTINATION_FILE" >&2
        # This is critical if destination was specified
        exit 1
    fi
fi


# Validate error file path *before* changing directory (if specified)
if [[ "$ERROR_MODE" == "file" || ("$ERROR_MODE" == "top" || "$ERROR_MODE" == "bottom") && -n "$ERROR_FILE" ]]; then
    # Resolve error file path relative to initial PWD
    [[ "$ERROR_FILE" != /* ]] && ERROR_FILE="$initial_pwd/$ERROR_FILE"
    error_dir=$(dirname "$ERROR_FILE")

    if [[ ! -d "$error_dir" ]]; then
         echo "Error: Directory for error file does not exist: $error_dir. Switching to screen errors." >&2
         ERROR_MODE="screen"
         ERROR_FILE=""
    elif [[ ! -w "$error_dir" ]]; then
         echo "Error: Cannot write to error directory: $error_dir. Switching to screen errors." >&2
         ERROR_MODE="screen"
         ERROR_FILE=""
    else
        # Create or truncate error file only if mode is 'file' (T/b append/prepend later)
        if [[ "$ERROR_MODE" == "file" ]]; then
             > "$ERROR_FILE"
             if [[ $? -ne 0 ]]; then
                 echo "Error: Cannot create or truncate error file: $ERROR_FILE. Switching to screen errors." >&2
                 ERROR_MODE="screen"
                 ERROR_FILE=""
             fi
        fi
    fi
fi


# Determine if target is file or directory and adjust path if needed
# Initialize exit_code for validation steps
exit_code=0
if [[ -f "$TARGET" ]]; then
    target_is_file=true
    # If target is a file, need to cd to its directory for consistent processing
    target_abs=$(realpath "$TARGET" 2>/dev/null) # Get absolute path first
    if [[ $? -ne 0 || -z "$target_abs" ]]; then # Check realpath success and non-empty result
        log_error "Target file '$TARGET' not found or inaccessible."
        exit_code=1
    else
        target_dir=$(dirname "$target_abs")
        target_file_base=$(basename "$target_abs")
        if ! cd "$target_dir"; then
            log_error "Cannot cd into directory of target file '$target_abs'"
            ERROR_MESSAGES+=("Error: Cannot cd into directory of target file '$target_abs'")
            exit_code=1 # Set non-zero exit code
        else
            TARGET="$target_file_base" # Now target is just the basename relative to current dir
        fi
    fi
elif [[ -d "$TARGET" ]]; then
    # If target is a directory, cd into it
    target_abs=$(realpath "$TARGET" 2>/dev/null) # Get absolute path first
    if [[ $? -ne 0 || -z "$target_abs" ]]; then # Check realpath success and non-empty result
         log_error "Target directory '$TARGET' not found or inaccessible."
         exit_code=1
    else
         if ! cd "$target_abs"; then
            log_error "Cannot cd into target directory '$target_abs'"
            ERROR_MESSAGES+=("Error: Cannot cd into target directory '$target_abs'")
            exit_code=1
        else
            TARGET="." # Target becomes the current directory relative to where we cd'd
            # Check if it's a directory target *without* -a or -ar
            if [[ "$PROCESS_ALL" == false && "$RECURSIVE" == false ]]; then
                 target_is_dir_no_flags=true
            fi
        fi
    fi
else
    target_abs=$(realpath "$TARGET" 2>/dev/null || echo "$initial_pwd/$TARGET") # Try realpath, fallback
    log_error "Target '$target_abs' is not a valid file or directory."
    ERROR_MESSAGES+=("Error: Target '$target_abs' is not a valid file or directory.")
    exit_code=1
fi


# --- Main Execution Logic ---
# Only proceed if initial validation passed
if [[ "$exit_code" -eq 0 ]]; then
    if [[ "$target_is_file" == true ]]; then
        # Process a single file
        process_file "$TARGET" # TARGET is now basename
    elif [[ -d "$TARGET" ]]; then # TARGET is now "." relative to the target dir
        # Process a directory based on flags
        if [[ "$PROCESS_ALL" == true ]]; then
            process_dir "." # Start processing from current dir (which is the target dir)
        elif [[ "$target_is_dir_no_flags" == true ]]; then
             # Default behavior for directory target without -a/-ar:
             # Process files directly inside, no recursion, no dir CTR.
             for entry in *; do
                 [[ "$entry" == ".CTR."* ]] && continue
                 [[ "$entry" == *.tmp.?????? ]] && continue
                 [[ -f "$entry" ]] && process_file "$entry"
             done
        # Else: If target is dir but not -a/-ar and not the default case (e.g., just -r which is invalid alone), do nothing.
        fi
    fi
fi

# --- Final Error Output Handling ---
if [[ ${#ERROR_MESSAGES[@]} -gt 0 ]]; then
    # Ensure errors are visible even if script fails early
    # Only set exit_code=1 if it wasn't already set by validation
    [[ "$exit_code" -eq 0 ]] && exit_code=1 # Mark failure if any *runtime* errors occurred

    case "$ERROR_MODE" in
        top)
            # Prepend errors to destination file or error file or stderr
            output_target=""
            if [[ -n "$DESTINATION_FILE" && -f "$DESTINATION_FILE" ]]; then
                output_target="$DESTINATION_FILE"
            elif [[ -n "$ERROR_FILE" && -f "$ERROR_FILE" ]]; then
                output_target="$ERROR_FILE"
            fi

            if [[ -n "$output_target" ]]; then
                 temp_err_file=$(mktemp "${output_target}.err.tmp.XXXXXX")
                 if [[ -n "$temp_err_file" && -f "$temp_err_file" ]]; then
                    printf "%s\n" "${ERROR_MESSAGES[@]}" > "$temp_err_file"
                    cat "$output_target" >> "$temp_err_file"
                    if ! mv "$temp_err_file" "$output_target"; then
                        echo "Error: Failed to prepend errors to $output_target" >&2
                        # Print errors to stderr as fallback
                        printf "%s\n" "${ERROR_MESSAGES[@]}" >&2
                    fi
                 else
                    echo "Error: Failed to create temp file for prepending errors." >&2
                    printf "%s\n" "${ERROR_MESSAGES[@]}" >&2
                 fi
            else
                 # Prepend to standard output (print them now to stderr)
                 printf "%s\n" "${ERROR_MESSAGES[@]}" >&2 # Print errors grouped together to stderr
            fi
            ;;
        bottom)
             # Append errors to destination file or error file or stderr
            output_target=""
            if [[ -n "$DESTINATION_FILE" && -f "$DESTINATION_FILE" ]]; then
                output_target="$DESTINATION_FILE"
            elif [[ -n "$ERROR_FILE" && -f "$ERROR_FILE" ]]; then
                 output_target="$ERROR_FILE"
            fi

            if [[ -n "$output_target" ]]; then
                 printf "%s\n" "${ERROR_MESSAGES[@]}" >> "$output_target"
            else
                 # Append to standard output (print them now to stderr)
                 printf "%s\n" "${ERROR_MESSAGES[@]}" >&2 # Print errors grouped together to stderr
             fi
            ;;
        file)
             # Errors were already written to ERROR_FILE by log_error
             : # Do nothing extra here
             ;;
        screen)
            # Errors were already printed to stderr by log_error
             : # Do nothing extra here
             ;;
        suppress)
             : # Do nothing
             ;;
    esac
fi

# Return to the original directory if we changed it
if [[ "$(pwd)" != "$initial_pwd" ]]; then
    # Check if we successfully changed directory during validation before trying to cd back
    # This check might be complex depending on validation flow; simpler to just try cd-ing back if needed
     cd "$initial_pwd" || exit 1 # cd back, exit if fails
fi

exit "$exit_code"