
# Prompt user for the new GitHub repo name
echo -n "What is the GitHub new repo name? "
read reponame

# Validate input
if [[ -z "$reponame" ]]; then
  echo "❌ Repository name is required. Exiting."
  exit 1
fi

# Create repo if README.md exists
if [[ ! -f "README.md" ]]; then
  echo "# $reponame" > README.md
fi

# Run git commands
git init
git add .
git commit -m "first commit"
git branch -M main
git remote add origin "git@github.com:mohdazlanabas/${reponame}.git"
git push -u origin main
