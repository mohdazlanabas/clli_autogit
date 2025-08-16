# Check for .ignore file in the current directory
if [[ -f ".ignore" ]]; then
  echo ".ignore already exists. No action taken."
else
  # Check if gitignore.txt exists in the same directory as this script
  script_dir="$(dirname "$0")"
  source_file="$script_dir/gitignore.txt"

  if [[ -f "$source_file" ]]; then
    cp "$source_file" .gitignore
    echo ".gitignore created using gitignore.txt content."
  else
    echo "gitignore.txt not found in script directory."
    exit 1
  fi
fi
