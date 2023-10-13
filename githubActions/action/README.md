Description
Secrets
Environment variables
Arguments
Examples

jobs:

   build:
      runs-on: ubuntu-latest
	   steps:
	   - uses: actions/checkout@v1
	   - uses: automate6500/keyword-releaser-action@master
	     env:
		    GITHUB_TOKEN: ${{ SECRETS.github_token }}
		 with: 
            args: 'FIXED'		 
