#CTR (01) [UTC-2025-04-09-00=06-51] ./R.README.md [Summary: ] [Next steps: ] [Notes: ]
Okay, here is a draft for the `R.README.md` file documenting your script suite. You can save this content into a file named `R.README.md` within your `~/scripts/` directory or a parent directory if you prefer.

```markdown
# R. Scripts: File Metadata Management Suite

This suite of scripts provides tools for managing structured metadata comments, referred to as "Control Lines" (`#CTR`), within source code files and associated metadata files. It allows for generating, viewing, and cleaning this metadata across your projects.

## Features

*   **Metadata Injection (`R.ctr`)**: Adds standardized `#CTR` lines to files.
    *   Handles files with common comment syntax (e.g., `#`, `//`, `<!--`).
    *   Creates external `.CTR.<filename>` files for types without standard comments.
    *   Respects shebang (`#!`) lines, inserting metadata *after* them.
    *   Options for recursive processing, output redirection, and error handling.
*   **Metadata Listing (`R.ls`)**: Generates a recursive file listing showing associated `#CTR` lines.
    *   Displays `#CTR` lines found within files or in corresponding `.CTR.` files.
    *   Automatically runs `R.ctr` to add default metadata if none is found (can modify files).
    *   Formats output with indented metadata lines.
*   **Metadata Cleanup (`R.ctr.cleanup`)**: Removes `#CTR` lines from files and deletes associated `.CTR.` files.
    *   Options for recursive cleaning and excluding specific files/directories via regex patterns.
*   **Command-Line Interface**: Scripts are designed to be run from the command line with various options.
*   **Convenience**: Setup allows calling scripts from any directory without the `.sh` extension (e.g., `R.ls` instead of `~/scripts/R.ls.sh`).

## Scripts Overview

*   **`R.ctr`**: The core script for **adding/updating** CTR lines.
*   **`R.ls`**: The script for **viewing** the file structure and associated CTR lines.
*   **`R.ctr.cleanup`**: The script for **removing** CTR lines and metadata files.
*   **`R.codebase`**: (Assumed) A script potentially related to reporting or analyzing the codebase based on CTR metadata. *[Add specific details here if available]*

## CTR Line Format

The standard format for a Control Line managed by these scripts is:

`[Prefix]CTR (NN) [UTC-YYYY-MM-DD-HH=MM-SS] ./relative/path/filename [Summary: ] [Next steps: ] [Notes: ]`

*   `[Prefix]`: The appropriate comment prefix for the file type (`#`, `//`, etc.) or absent if stored in a `.CTR.` file.
*   `CTR`: Control Line identifier.
*   `(NN)`: A numerical identifier (e.g., `(01)`).
*   `[UTC-...]`: Timestamp of the last relevant action (often creation/update).
*   `./relative/path/filename`: Path to the file, usually relative to its location within the CTR line itself.
*   `[...]`: Placeholder fields for metadata (Summary, Next steps, Notes).

## Installation and Setup

1.  **Prerequisites**: A Linux/Unix-like environment with `bash` and standard utilities (`find`, `sort`, `grep`, `sed`, `realpath`, `getopt`, `mktemp`, `cat`, `tail`, `ln`, `chmod`, `mv`, `rm`).
2.  **Placement**: Place all `R.*.sh` scripts into the `~/scripts/` directory.
    ```bash
    mkdir -p ~/scripts
    # Copy or move your R.*.sh files here
    cp R.ctr.sh R.ls.sh R.ctr.cleanup.sh R.codebase.sh ~/scripts/
    ```
3.  **Permissions**: Make the scripts executable:
    ```bash
    chmod +x ~/scripts/R.*.sh
    ```
4.  **PATH Configuration**: To run scripts from any directory, add `~/scripts` to your `PATH`. Edit your shell configuration file (e.g., `~/.bashrc`):
    ```bash
    nano ~/.bashrc
    ```
    Add this line at the end:
    ```bash
    export PATH="$HOME/scripts:$PATH"
    ```
    Save the file (`Ctrl+X`, `Y`, `Enter` in nano) and apply the changes:
    ```bash
    source ~/.bashrc
    ```
5.  **Callable Names (Optional but Recommended)**: To call scripts without the `.sh` extension (e.g., `R.ls`), create symbolic links within the `~/scripts` directory:
    ```bash
    cd ~/scripts
    ln -s R.ctr.sh R.ctr
    ln -s R.ls.sh R.ls
    ln -s R.ctr.cleanup.sh R.ctr.cleanup
    ln -s R.codebase.sh R.codebase # Add others as needed
    cd - # Go back to previous directory
    ```

## Usage

### `R.ctr`

Adds or manages CTR lines.

**Syntax:**

```
R.ctr [target] [options] [<destination>]
```

*   **`[target]`**: The file or directory to process.
    *   Default: `.` (current directory).
    *   If file: Processes only that file.
    *   If directory (no `-a`/`-ar`): Processes files directly within the directory.
*   **`[options]`**:
    *   `-a`, `--all`: Process directory metadata (`.CTR.<dirname>`) and all files directly within the target directory (no recursion).
    *   `--all-recursive` (`-ar`): Like `-a`, but also processes subdirectories recursively.
    *   `-d`, `--display`: Display the generated CTR lines to standard output as they are processed.
    *   `--error <mode>[:<file>]` (`-e:...`): Control error handling.
        *   `-e:s` (suppress): Hide errors.
        *   `-e:screen` (default): Print errors to stderr as they occur.
        *   `-e:T`: Group errors and print to stderr at the top (after other output).
        *   `-e:T:<file>`: Group errors and prepend them to `<file>`.
        *   `-e:b`: Group errors and print to stderr at the bottom.
        *   `-e:b:<file>`: Group errors and append them to `<file>`.
        *   `-e:f:<file>`: Write errors to a separate `<file>` as they occur.
*   **`<destination>`**: Optional file path.
    *   If specified, **prevents modification** of target files/creation of `.CTR.` files.
    *   *Only newly generated* CTR lines are written to this file.
    *   Cannot be a directory.

**Behavior:**

*   Checks if a file needs a CTR line (based on comment prefix or `.CTR.` file existence).
*   If missing, generates a default CTR line.
*   Writes the CTR line into the file (after shebang if present) or creates/updates a `.CTR.<filename>` file, unless `<destination>` is specified.

### `R.ls`

Lists files recursively and displays their associated CTR lines.

**Syntax:**

```
R.ls
```
*(No arguments or options currently)*

**Behavior:**

*   Starts in the current directory.
*   Uses `find` to locate all files and directories.
*   Prints directory paths ending with `/`.
*   Prints file paths.
*   For each file:
    *   Attempts to extract existing `#CTR` lines from within the file (respecting comment prefixes).
    *   If none found, checks for a corresponding `.CTR.<filename>` file and reads its content.
    *   If still none found, it **calls `R.ctr`** on that file to generate default metadata (this **modifies** the file system). It then reads the newly generated metadata.
    *   Prints the found/generated CTR lines indented below the file path.
*   Creates an output file named `R.ls.[UTC-YYYY-MM-DD-HH=MM-SS].txt` in the current directory.

### `R.ctr.cleanup`

Removes CTR lines from files and deletes `.CTR.*` metadata files.

**Syntax:**

```
R.ctr.cleanup [target] [options]
```

*   **`[target]`**: The file or directory to clean.
    *   Default: `.` (current directory).
    *   If file: Cleans only that file and deletes its associated `.CTR.<filename>` if present.
    *   If directory: Cleans files/metadata within that directory (subject to `-r`).
*   **`[options]`**:
    *   `-r`, `--recursive`: Clean recursively into subdirectories. Ignored if the target is a file.
    *   `-e <pattern>`, `--exclude <pattern>`: Exclude files or directories whose **basename** matches the provided POSIX Extended Regular Expression (ERE) `<pattern>`.

**Behavior:**

*   **Warning:** This script modifies files (`sed -i`) and deletes files (`rm`). **Use with caution. Backup important data.**
*   If target is a file, removes inline CTR lines and deletes `.CTR.<target_basename>`.
*   If target is a directory:
    *   Iterates through entries.
    *   Deletes `.CTR.*` files (unless the original filename matches exclude pattern).
    *   Removes inline CTR lines from files (unless filename matches exclude pattern).
    *   If `-r` is used, recurses into subdirectories (unless directory name matches exclude pattern).

## Examples

```bash
# Add CTR lines to all supported files in the current directory (non-recursive)
R.ctr

# Add CTR lines recursively to all files/dirs in 'my_project', display progress
R.ctr my_project -ar -d

# Add CTR lines recursively, redirect *new* CTRs to report.txt, errors to errors.log
R.ctr . -ar report.txt --error f:errors.log

# Generate the recursive listing with CTR data for the current project
R.ls

# Clean CTR data from just one file
R.ctr.cleanup path/to/specific_file.py

# Clean CTR data non-recursively from the current directory
R.ctr.cleanup

# Clean CTR data recursively from '~/projects/old_code'
R.ctr.cleanup ~/projects/old_code -r

# Clean recursively, but exclude all hidden files/dirs and log files
R.ctr.cleanup -re '^\.|\.log$'
```

---

```
