# Operating system to use
FROM ubuntu

#
copy entryPoint.sh /entryPoint.sh

# Change out entryPoint script to an executable
RUN chmod +x /entryPoint.sh

# The command that our action will run, when it starts
ENTRYPOINT ["/entryPoint.sh"]
