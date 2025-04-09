#CTR (01) [UTC-2025-04-09-00=06-51] ./R.codebase.sh [Summary: ] [Next steps: ] [Notes: ]
bash -c 'timestamp=$(date "+%Y%m%d_%H%M"); outfile="Codebase${timestamp}.txt"; find . -type f ! -name ".env" -print0 | while IFS= read -r -d "" file; do
  if file --mime "$file" | grep -q text; then
    echo -e "\n--- $file ---" >> "$outfile"
    cat "$file" >> "$outfile"
  fi
done; echo "Output saved to $outfile"'
