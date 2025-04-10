#!/bin/bash

# --- Help Flag Handling --- 
if [[ "$1" == "--h" ]]; then
    cat << EOF

Usage: $(basename "$0") [options] [arguments]



Options:

  --h    Display this help message and exit.



Arguments:



EOF
    exit 0
fi
# --- End Help Flag Handling ---


#CTR (01) [UTC-2025-04-09-00=06-51] ./R.ls.sh [Summary: ] [Next steps: ] [Notes: ]

timestamp=$(date -u +"%Y-%m-%d-%H=%M-%S")
# Resolve output file path relative to the script's execution directory
output_file_rel="./R.ls.[UTC-${timestamp}].txt"
output_file_abs=$(realpath "$output_file_rel")

root_dir_abs=$(pwd)
root_dir_home_rel=$(realpath --relative-to="$HOME" "$root_dir_abs" 2>/dev/null || echo "$root_dir_abs") # Handle case outside HOME
# Use ~ prefix only if the path is actually within HOME and relative path doesn't start with ..
if [[ "$root_dir_home_rel" != /* && "$root_dir_home_rel" != ".."* ]]; then
    root_dir_display="~/${root_dir_home_rel}"
else
    root_dir_display="$root_dir_abs" # Fallback to absolute if not nicely relative to HOME
fi


# --- Configuration ---
R_CTR_SCRIPT_PATH="${HOME}/scripts/R.ctr.sh" # Explicit path as requested
if [[ ! -x "$R_CTR_SCRIPT_PATH" ]]; then
    echo "Error: Cannot find or execute R.ctr.sh script at ${R_CTR_SCRIPT_PATH}" >&2
    exit 1
fi
# Fixed Indentation String
INDENT="    " # 4 spaces for indentation


# --- Header ---
echo "#CTR (01) [UTC-${timestamp}] ${output_file_abs}  [Recursive LS output]" > "$output_file_abs"
echo >> "$output_file_abs" # Add a blank line after header
echo "${root_dir_display}/" >> "$output_file_abs" # Add root dir marker


# --- Helper Functions ---

# Function to determine comment prefix
get_comment_prefix() {
    local filename="$1"
    local ext="${filename##*.}"
    [[ "$filename" == .* ]] && [[ ! "$filename" == *. ]] && ext="${filename#.}"

    case "$ext" in
        sh|bash|py|pl|rb|conf|ini|txt|yaml|yml|md|R|ls|ctr) echo "#" ;;
        c|cpp|h|hpp|java|js|ts|css|go|php|swift|kt) echo "//" ;;
        html|xml|svg) echo "<!--" ;;
        sql|ada) echo "--" ;;
        f|f90|f95|f03|f08) echo "!" ;;
        *) echo "" ;;
    esac
}

# Function to get CTR lines for a file
get_ctr_lines() {
    local file_abs_path="$1"
    local file_rel_path # Relative to PWD where find was run (root_dir_abs)
    file_rel_path=$(realpath --relative-to="$root_dir_abs" "$file_abs_path")
    local dir_path=$(dirname "$file_abs_path")
    local base_name=$(basename "$file_abs_path")
    local meta_file="$dir_path/.CTR.$base_name"
    local prefix=$(get_comment_prefix "$base_name")
    local found_ctr=false
    local ctr_output=""

    # *** Add Check: Don't process .CTR.* files within this function either ***
    if [[ "$base_name" == ".CTR."* ]]; then
         echo "# Skipping metadata file: ${file_rel_path}" >&2
         # Return empty string and success status, as it's not an error to skip them
         return 0
    fi


    if [[ ! -f "$file_abs_path" || ! -r "$file_abs_path" ]]; then
        echo "# Error reading file: ${file_rel_path}" >&2
        echo "# Error reading file: ${file_rel_path}"
        return 1
    fi

    # 1. Try extracting from file
    if [[ -n "$prefix" ]]; then
        local escaped_prefix=$(sed -e 's/[]\/$*.^|[]/\\&/g' <<< "$prefix")
        ctr_output=$(grep -E "^${escaped_prefix}[[:space:]]*CTR" "$file_abs_path")
        [[ -n "$ctr_output" ]] && found_ctr=true
    fi

    # 2. Check .CTR. file if needed
    if [[ "$found_ctr" == false ]]; then
         # We already know the current file isn't a .CTR file itself from the check above
         if [[ -f "$meta_file" && -r "$meta_file" ]]; then
            local meta_content=$(grep -E "^CTR" "$meta_file")
            if [[ -n "$meta_content" ]]; then
                ctr_output="$meta_content"
                found_ctr=true
            fi
         fi
    fi

    # 3. Run R.ctr.sh if needed (only if no CTR found AND it's not a .CTR file)
    if [[ "$found_ctr" == false ]]; then
        echo "# Info: No CTR found for ${file_rel_path}. Running R.ctr.sh..." >&2
        local ctr_run_output
        local ctr_run_status
        # Pass absolute path to R.ctr.sh
        ctr_run_output=$("$R_CTR_SCRIPT_PATH" "$file_abs_path" 2>&1)
        ctr_run_status=$?

        if [[ "$ctr_run_status" -eq 0 ]]; then
            # Try extracting again
            local retry_output=""
            if [[ -n "$prefix" ]]; then
                escaped_prefix=$(sed -e 's/[]\/$*.^|[]/\\&/g' <<< "$prefix")
                retry_output=$(grep -E "^${escaped_prefix}[[:space:]]*CTR" "$file_abs_path")
            fi
            if [[ -z "$retry_output" ]]; then
                # Check the corresponding metafile again AFTER R.ctr.sh ran
                if [[ -f "$meta_file" && -r "$meta_file" ]]; then
                    local meta_content=$(grep -E "^CTR" "$meta_file")
                    [[ -n "$meta_content" ]] && retry_output="$meta_content"
                fi
            fi

            if [[ -n "$retry_output" ]]; then
                 ctr_output="$retry_output"
                 found_ctr=true
            else
                 echo "# Warning: R.ctr.sh ran but no CTR line could be extracted for ${file_rel_path}." >&2
                 ctr_output="# Warning: R.ctr.sh ran but no CTR line could be extracted."
            fi
        else
             echo "# Warning: R.ctr.sh failed for ${file_rel_path}. Output: ${ctr_run_output}" >&2
             ctr_output="# Warning: R.ctr.sh failed. Error: ${ctr_run_output}"
        fi
    fi

    if [[ -n "$ctr_output" ]]; then
        echo "$ctr_output"
    fi
    return 0
}


# --- Main Logic ---

find . -mindepth 1 -print0 | sort -z | while IFS= read -r -d $'\0' entry; do
    # entry is relative to '.' e.g., ./file.txt, ./subdir

    # *** ADD CHECK: Skip .CTR.* files early in the loop ***
    base_name=$(basename "$entry")
    if [[ "$base_name" == ".CTR."* ]]; then
        continue # Skip to the next entry found by find
    fi

    abs_path=$(realpath "$entry")
    rel_path_home=$(realpath --relative-to="$HOME" "$abs_path" 2>/dev/null || echo "$abs_path")

    # Determine the display path (use ~ if possible)
    display_path=""
    if [[ "$rel_path_home" != /* && "$rel_path_home" != ".."* ]]; then
         display_path="~/${rel_path_home}"
    else
         display_path="$abs_path" # Fallback to absolute path
    fi

    # Get relative path from script root dir for structure
    rel_path_script_root=$(realpath --relative-to="$root_dir_abs" "$abs_path")
    # Combine root display path with relative part for full display string
    full_display_path="${root_dir_display}/${rel_path_script_root}"


    if [[ -d "$entry" ]]; then
        echo "${full_display_path}/" >> "$output_file_abs"
    elif [[ -f "$entry" ]]; then
        echo "${full_display_path}" >> "$output_file_abs"

        # Call get_ctr_lines which now also handles skipping .CTR.* intrinsically
        ctr_lines_output=$(get_ctr_lines "$abs_path")
        get_ctr_status=$?

        if [[ "$get_ctr_status" -eq 0 && -n "$ctr_lines_output" ]]; then
             while IFS= read -r line; do
                 printf "%s%s\n" "$INDENT" "$line" >> "$output_file_abs"
             done <<< "$ctr_lines_output"
        elif [[ "$get_ctr_status" -ne 0 ]]; then
             # If get_ctr_lines reported an error
             printf "%s%s\n" "$INDENT" "$ctr_lines_output" >> "$output_file_abs"
        fi
         echo "" >> "$output_file_abs" # Add blank line after file entry
    fi
done


echo "Recursive listing with control lines saved to ${output_file_abs}"